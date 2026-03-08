#!/usr/bin/env bash
# aid.sh — main entry point. Symlinked into ~/.local/bin/aid by install.sh.
#
# Isolation: aid runs on its own tmux server socket (-L aid) with its own
# config (-f), and sets XDG_CONFIG_HOME=$HOME/.config/aid so nvim reads from
# there. NVIM_APPNAME=nvim resolves to ~/.config/aid/nvim.
# The user's ~/.config/nvim and existing tmux sessions are never touched.
#
# Layout: two tmux panes — editor (nvim with nvim-tree split inside) | opencode.
#
# Usage:
#   aid                       launch new session in current directory
#   aid -a, --attach          attach to a session (interactive list, or -a <name>)
#   aid -l, --list            list all running sessions
#   aid -d, --debug           verbose output (set -x + step tracing)
#   aid -h, --help            show this help

set -euo pipefail

# Always resolves correctly because this file is executed, not sourced.
AID_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"

# ── Debug mode ───────────────────────────────────────────────────────────────
# Consume -d/--debug before the main case so it composes with other flags.
# e.g. `aid --debug -a mySession` works correctly.
AID_DEBUG=0
_args=()
for _arg in "$@"; do
  if [[ "$_arg" == "-d" || "$_arg" == "--debug" ]]; then
    AID_DEBUG=1
  else
    _args+=("$_arg")
  fi
done
set -- "${_args[@]+"${_args[@]}"}"
if [[ "$AID_DEBUG" -eq 1 ]]; then
  set -x
fi

# dbg <msg> — print step trace only in debug mode
dbg() { [[ "$AID_DEBUG" -eq 1 ]] && echo "[aid:debug] $*" >&2 || true; }

# attach_or_switch <session>
# Use switch-client when already inside tmux (attach fails inside a session).
attach_or_switch() {
  dbg "attach_or_switch: target=$1 TMUX=${TMUX:-<unset>}"
  if [[ -n "${TMUX:-}" ]]; then
    tmux -L aid switch-client -t "$1"
  else
    tmux -L aid attach -t "$1"
  fi
}

# ── Argument parsing ─────────────────────────────────────────────────────────

case "${1:-}" in
  -h|--help)
    cat <<'EOF'
aid — AI-assisted dev environment

Usage:
  aid                   launch new session in current directory
  aid -a, --attach      interactive session list to attach to
  aid -a <name>         attach directly to named session
  aid -l, --list        list running sessions
  aid -d, --debug       verbose output (set -x + step tracing)
  aid -h, --help        show this help
EOF
    exit
    ;;
  -l|--list)
    tmux -L aid list-sessions 2>/dev/null || echo "no aid sessions"
    exit
    ;;
  -a|--attach)
    shift
    if [[ -n "${1:-}" ]]; then
      # aid -a <name>
      attach_or_switch "$1"
      exit
    fi
    # aid -a with no name — interactive list
    mapfile -t _sessions < <(tmux -L aid list-sessions -F "#{session_name}" 2>/dev/null)
    if [[ ${#_sessions[@]} -eq 0 ]]; then
      echo "no aid sessions running"
      exit 1
    elif [[ ${#_sessions[@]} -eq 1 ]]; then
      attach_or_switch "${_sessions[0]}"
      exit
    fi
    echo "aid sessions:"
    for i in "${!_sessions[@]}"; do
      printf "  [%d] %s\n" "$((i+1))" "${_sessions[$i]}"
    done
    printf "attach to [1-%d]: " "${#_sessions[@]}"
    read -r _choice
    if [[ "$_choice" =~ ^[0-9]+$ ]] && (( _choice >= 1 && _choice <= ${#_sessions[@]} )); then
      attach_or_switch "${_sessions[$((_choice-1))]}"
    else
      echo "invalid choice"
      exit 1
    fi
    exit
    ;;
  -*)
    echo "unknown flag: $1  (try aid --help)" >&2
    exit 1
    ;;
esac

# No flag — fall through to create a new session in current directory.

# Capture launch dir before tmux changes context
launch_dir="$PWD"
dbg "launch_dir=$launch_dir"

# Pick a unique session name from current dir (strip leading dots, replace special chars).
# Session names take the form aid@<dirname> — the @ is intentional branding; tmux,
# the filesystem, and all aid tooling handle it correctly. Fight to keep it if issues arise.
base=$(basename "$launch_dir" | sed 's/^\.*//' | tr -cs '[:alnum:]-_' '-' | sed 's/-$//')
[[ -z "$base" ]] && base="dev"
session="aid@$base"
n=2
while tmux -L aid has-session -t "$session" 2>/dev/null; do
  session="aid@${base}${n}"
  (( n++ ))
done
dbg "session=$session"

# Parse .aidignore (walks up from launch_dir) and build AID_IGNORE=comma,separated,list.
# If no .aidignore is found anywhere, create an empty one in launch_dir so the
# file watcher in nvim has a file to watch from the start.
AID_IGNORE=""
_aidignore_file=""
_dir="$launch_dir"
for _i in $(seq 1 20); do
  if [[ -f "$_dir/.aidignore" ]]; then
    _aidignore_file="$_dir/.aidignore"
    break
  fi
  _parent="$(dirname "$_dir")"
  [[ "$_parent" == "$_dir" ]] && break
  _dir="$_parent"
done
if [[ -z "$_aidignore_file" ]]; then
  touch "$launch_dir/.aidignore"
  _aidignore_file="$launch_dir/.aidignore"
fi
if [[ -n "$_aidignore_file" ]]; then
  AID_IGNORE=$(grep -v '^\s*#' "$_aidignore_file" | grep -v '^\s*$' | paste -sd ',' || true)
fi
export AID_IGNORE
dbg "aidignore=$_aidignore_file AID_IGNORE=${AID_IGNORE:-<empty>}"

# Start the aid-isolated tmux server with its own config
dbg "starting tmux session"
tmux -L aid -f "$AID_DIR/tmux.conf" new-session -d -s "$session" \
  -x "$(tput cols)" -y "$(tput lines)"

# Export AID_DIR, AID_IGNORE, XDG_CONFIG_HOME, and OPENCODE_CONFIG_DIR into the server environment
# so all panes inherit them. XDG_CONFIG_HOME isolates all nvim config under ~/.config/aid/.
# OPENCODE_CONFIG_DIR isolates opencode to aid's own
# config dir (commands/, package.json) instead of ~/.config/opencode/.
tmux -L aid set-environment -g AID_DIR "$AID_DIR"
tmux -L aid set-environment -g AID_IGNORE "$AID_IGNORE"
tmux -L aid set-environment -g XDG_CONFIG_HOME "$HOME/.config/aid"
tmux -L aid set-environment -g OPENCODE_CONFIG_DIR "$AID_DIR/opencode"
# NVIM_APPNAME in the server environment means every pane shell inherits it —
# no dependency on the send-keys command being delivered intact.
tmux -L aid set-environment -g NVIM_APPNAME "nvim"

# nvim socket path — used by the editor restart loop so nvim is always reachable
# at a stable path (e.g. for external tooling or future RPC use).
# @ is legal in UNIX socket paths and /tmp filenames.
nvim_socket="/tmp/aid-nvim-${session}.sock"
dbg "nvim_socket=$nvim_socket"

# IDE layout sizes — two panes: editor (nvim, nvim-tree split inside) | opencode.
# opencode=29% of total width; editor gets the remainder.
# No layout correction needed — no sidebar insertion shifts the proportions.

# Find the initial (only) pane and capture its stable ID before any splits.
editor_pane_id=$(tmux -L aid list-panes -t "$session" -F "#{pane_id}" | head -1)
dbg "editor_pane_id=$editor_pane_id"

# Split right: opencode occupies 29% of width, spawned directly into opencode
# (no shell prompt — avoids zsh intercept, send-keys mangling, autocorrect).
dbg "splitting opencode pane"
tmux -L aid split-window -h -p 29 -t "$editor_pane_id" \
  "OPENCODE_CONFIG_DIR=$(printf '%q' "$AID_DIR/opencode") opencode $(printf '%q' "$launch_dir")"
opencode_pane_id=$(tmux -L aid list-panes -t "$session" -F "#{pane_id} #{pane_left}" \
  | sort -k2 -n | tail -1 | cut -d' ' -f1)
dbg "opencode_pane_id=$opencode_pane_id"
tmux -L aid select-pane -t "$editor_pane_id"

# Respawn the editor pane directly into the nvim restart loop — bypasses the
# interactive shell entirely so zsh autocorrect / send-keys mangling can't fire.
# The pane is never a bare shell: when the user quits nvim (:q) the loop
# immediately restarts it on the same socket.
# To kill the session entirely: close the tmux window or run `aid kill`.
dbg "respawning editor pane into nvim loop"
tmux -L aid respawn-pane -k -t "$editor_pane_id" \
  "cd $(printf '%q' "$launch_dir") && while true; do rm -f $(printf '%q' "$nvim_socket"); XDG_CONFIG_HOME=$(printf '%q' "$HOME/.config/aid") NVIM_APPNAME=nvim nvim --listen $(printf '%q' "$nvim_socket"); done"

dbg "attaching to session=$session"
attach_or_switch "$session"
