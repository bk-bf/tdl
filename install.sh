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

# ── 4. Symlinks: nvim-treemux config ─────────────────────────────────────────
echo "==> Creating symlinks..."

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
echo "==> Bootstrapping nvim-treemux plugins (lazy sync)..."
NVIM_APPNAME=nvim-treemux nvim --headless "+Lazy! sync" +qa 2>/dev/null || \
  echo "  (headless sync exited non-zero — likely fine on first run, plugins still installed)"

# ── 6. Shell integration reminder ────────────────────────────────────────────
echo ""
echo "==> Done. Add the following to ~/.config/.aliases (or wherever you source shell config):"
echo ""
echo "    source $TDL/aliases.sh"
echo ""
echo "    And to ~/.config/tmux/.tmux.conf:"
echo ""
echo "    source-file $TDL/tmux.conf"
echo ""
echo "    Then reload: tmux source-file ~/.config/tmux/.tmux.conf"
