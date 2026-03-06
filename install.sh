#!/usr/bin/env bash
# install.sh — set up tdl on a fresh machine
# Run once after cloning: bash install.sh
set -euo pipefail

TDL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> tdl install starting from $TDL"

# ── 1. Dependencies ──────────────────────────────────────────────────────────
# Arch/CachyOS: pynvim is required by the treemux watch script
if command -v pacman &>/dev/null; then
  echo "==> Installing pynvim..."
  sudo pacman -S --needed --noconfirm python-pynvim
fi

# ── 2. TPM ───────────────────────────────────────────────────────────────────
TPM_DIR="$HOME/.config/tmux/plugins/tpm"
if [[ ! -d "$TPM_DIR" ]]; then
  echo "==> Installing TPM..."
  git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
else
  echo "==> TPM already present"
fi

# ── 3. Treemux plugin (via TPM headless install) ──────────────────────────────
TREEMUX_DIR="$HOME/.config/tmux/plugins/treemux"
if [[ ! -d "$TREEMUX_DIR" ]]; then
  echo "==> Installing treemux via TPM..."
  # TPM headless install requires a running tmux server
  # Start a throwaway server, source the config, install plugins, kill server
  tmux new-session -d -s _tdl_install 2>/dev/null || true
  tmux source-file "$HOME/.config/tmux/.tmux.conf" 2>/dev/null || true
  "$TPM_DIR/bin/install_plugins"
  tmux kill-session -t _tdl_install 2>/dev/null || true
else
  echo "==> treemux plugin already present"
fi

# ── 4. Symlinks ───────────────────────────────────────────────────────────────
echo "==> Creating symlinks..."

# ~/.config/nvim → tdl/nvim/  (main nvim config)
if [[ -d "$HOME/.config/nvim" && ! -L "$HOME/.config/nvim" ]]; then
  echo "  WARNING: ~/.config/nvim is a real directory — backing up to ~/.config/nvim.bak"
  mv "$HOME/.config/nvim" "$HOME/.config/nvim.bak"
fi
ln -sfn "$TDL/nvim" "$HOME/.config/nvim"

# ~/.config/nvim-treemux/ → tdl/nvim-treemux/
mkdir -p "$HOME/.config/nvim-treemux"
ln -sf "$TDL/nvim-treemux/treemux_init.lua"    "$HOME/.config/nvim-treemux/treemux_init.lua"
ln -sf "$TDL/nvim-treemux/watch_and_update.sh" "$HOME/.config/nvim-treemux/watch_and_update.sh"

# treemux plugin's watch script → our custom version
ln -sf "$TDL/nvim-treemux/watch_and_update.sh" \
       "$TREEMUX_DIR/scripts/tree/watch_and_update.sh"

# ~/.config/tmux/ensure_treemux.sh → tdl/ensure_treemux.sh
ln -sf "$TDL/ensure_treemux.sh" "$HOME/.config/tmux/ensure_treemux.sh"

# ── 5. nvim-treemux plugin bootstrap (headless lazy sync) ────────────────────
_spin() {
  local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0 msg="$1"
  while kill -0 "$2" 2>/dev/null; do
    printf "\r  \033[38;5;208m%s\033[0m  %s" "${frames:$((i%10)):1}" "$msg"
    i=$((i+1)); sleep 0.08
  done
  printf "\r\033[2K"
}

echo "==> Bootstrapping nvim-treemux plugins (lazy sync)..."
NVIM_APPNAME=nvim-treemux nvim --headless "+Lazy! sync" +qa 2>/dev/null &
_nvim_pid=$!
_spin "syncing nvim-treemux plugins…" $_nvim_pid
wait $_nvim_pid || echo "  (headless sync exited non-zero — likely fine on first run, plugins still installed)"

echo "==> Bootstrapping main nvim plugins (lazy sync)..."
nvim --headless "+Lazy! sync" +qa 2>/dev/null &
_nvim_pid=$!
_spin "syncing main nvim plugins…" $_nvim_pid
wait $_nvim_pid || echo "  (headless sync exited non-zero — likely fine on first run, plugins still installed)"

# ── 6. Shell integration — inject source lines if not already present ────────
echo "==> Wiring shell integration..."

ALIASES_FILE="$HOME/.config/.aliases"
TMUX_CONF="$HOME/.config/tmux/.tmux.conf"
ALIASES_LINE="source $TDL/aliases.sh"
TMUX_LINE="source-file $TDL/tmux.conf"

if [[ -f "$ALIASES_FILE" ]]; then
  if grep -qF "$ALIASES_LINE" "$ALIASES_FILE"; then
    echo "==> $ALIASES_FILE already sources aliases.sh"
  else
    printf '\n# tdl IDE layout (treemux | nvim | opencode)\n%s\n' "$ALIASES_LINE" >> "$ALIASES_FILE"
    echo "==> Added source line to $ALIASES_FILE"
  fi
else
  echo "==> $ALIASES_FILE not found — add manually: $ALIASES_LINE"
fi

if [[ -f "$TMUX_CONF" ]]; then
  if grep -qF "$TMUX_LINE" "$TMUX_CONF"; then
    echo "==> $TMUX_CONF already sources tmux.conf"
  else
    printf '\n# tdl IDE layout — treemux plugin config, Tab keybind, session hook\n%s\n' "$TMUX_LINE" >> "$TMUX_CONF"
    echo "==> Added source-file line to $TMUX_CONF"
  fi
else
  echo "==> $TMUX_CONF not found — add manually: $TMUX_LINE"
fi

echo ""
echo "==> tdl install complete. Reload tmux with: tmux source-file ~/.config/tmux/.tmux.conf"
