#!/usr/bin/env bash
# tdl.sh — executed directly under bash (never sourced).
# Called by the tdl() shim in ~/.config/.aliases.
#
# Isolation: tdl runs on its own tmux server socket (-L tdl) with its own
# config (-f), and launches nvim as NVIM_APPNAME=nvim-tdl so it never
# touches the user's ~/.config/nvim or existing tmux sessions.

set -euo pipefail

# Always resolves correctly because this file is executed, not sourced.
TDL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${1:-}" ]]; then
  tmux -L tdl attach -t "$1"
  exit
fi

# Capture launch dir before tmux changes context
launch_dir="$PWD"

# Pick a unique session name from current dir (strip leading dots, replace special chars)
base=$(basename "$launch_dir" | sed 's/^\.*//' | tr -cs '[:alnum:]-_' '-' | sed 's/-$//')
[[ -z "$base" ]] && base="dev"
session="nvim@$base"
n=2
while tmux -L tdl has-session -t "$session" 2>/dev/null; do
  session="nvim@${base}${n}"
  (( n++ ))
done

# Parse .tdlignore (walks up from launch_dir) and build TDL_IGNORE=comma,separated,list
TDL_IGNORE=""
_tdlignore_file=""
_dir="$launch_dir"
for _i in $(seq 1 20); do
  if [[ -f "$_dir/.tdlignore" ]]; then
    _tdlignore_file="$_dir/.tdlignore"
    break
  fi
  _parent="$(dirname "$_dir")"
  [[ "$_parent" == "$_dir" ]] && break
  _dir="$_parent"
done
if [[ -n "$_tdlignore_file" ]]; then
  TDL_IGNORE=$(grep -v '^\s*#' "$_tdlignore_file" | grep -v '^\s*$' | paste -sd ',')
fi
export TDL_IGNORE

# Start the tdl-isolated tmux server with its own config
tmux -L tdl -f "$TDL_DIR/tmux.conf" new-session -d -s "$session" \
  -x "$(tput cols)" -y "$(tput lines)"

# Export TDL_DIR and TDL_IGNORE into the server environment so all panes inherit them
tmux -L tdl set-environment -g TDL_DIR "$TDL_DIR"
tmux -L tdl set-environment -g TDL_IGNORE "$TDL_IGNORE"

# IDE layout sizes — all pane geometry owned here, not scattered in tmux.conf
# sidebar=21, right (opencode)=28% of total width; editor gets the remainder
tmux -L tdl set-option -t "$session" @treemux-tree-width 21

# Wait for sidebar.tmux to finish setting @treemux-key-Tab
sleep 1.5

main_pane=$(tmux -L tdl list-panes -t "$session" -F "#{pane_index} #{pane_width}" \
  | sort -k2 -n | tail -1 | cut -d' ' -f1)

tmux -L tdl split-window -h -p 29 -t "$session:0.$main_pane"
tmux -L tdl send-keys -t "$session:0.$((main_pane + 1))" "opencode $launch_dir" Enter
tmux -L tdl select-pane -t "$session:0.$main_pane"

# Open treemux sidebar: run-shell -t executes inside the tdl server with $TMUX
# and $TMUX_PANE set, which toggle.sh's bare tmux calls require.
main_pane_id=$(tmux -L tdl list-panes -t "$session:0.$main_pane" -F "#{pane_id}")
tmux -L tdl run-shell -t "$main_pane_id" "$TDL_DIR/ensure_treemux.sh"

tmux -L tdl send-keys -t "$session:0.$main_pane" \
  "cd $(printf '%q' "$launch_dir") && NVIM_APPNAME=nvim-tdl nvim" Enter

tmux -L tdl attach -t "$session"
