-- sync.lua — central git-sync coordinator
--
-- Single entry point: require("sync").sync()
-- Refreshes all git-aware components after an external git operation
-- (branch switch, pull, stash pop, etc.) so that nvim and the treemux
-- sidebar never show stale state.
--
-- Triggered by:
--   • FocusGained   — nvim regains focus after any external tool
--   • TermClose     — lazygit float closes
--   • explicit call — post vim.cmd("LazyGit") in the <leader>gg keybind
--
-- Components refreshed:
--   1. nvim buffers    — checktime (reloads files changed on disk)
--   2. gitsigns        — refresh() (re-reads HEAD, recomputes hunk signs)
--   3. nvim-tree       — tree.reload() (full tree + git status)
--   4. treemux sidebar — :NvimTreeRefresh via tmux send-keys
--
-- Treemux pane lookup (approach 1: tmux option):
--   ensure_treemux.sh stores the sidebar pane ID in the tmux option
--   @-treemux-registered-pane-<main_pane_id>. We read that option here.
--
-- TODO: research and compare with approach 2 (nvim-tree-remote RPC transport):
--   transport.exec(ex, addr_override) already sends arbitrary Ex commands to
--   main nvim via msgpack-rpc. The reverse direction — main nvim pushing a
--   refresh command into treemux's nvim — could use the same channel by
--   looking up treemux's nvim socket via vim.fn.serverlist() in the treemux
--   nvim process. This would be more robust than tmux send-keys (no timing
--   issues, works even when the pane is not the active one) and should be
--   evaluated once the current approach is validated in daily use.

local M = {}

-- Refresh the treemux sidebar nvim-tree via tmux send-keys.
-- Reads @-treemux-registered-pane-$TMUX_PANE to find the sidebar pane ID.
local function _refresh_treemux_sidebar()
  local tmux_pane = vim.env.TMUX_PANE
  if not tmux_pane or tmux_pane == "" then return end

  -- ensure_treemux.sh stores: "<sidebar_pane_id>,<args>"
  local raw = vim.fn.system(
    "tmux show-option -gqv '@-treemux-registered-pane-" .. tmux_pane .. "'"
  ):gsub("%s+$", "")
  if raw == "" then return end

  local sidebar_pane = raw:match("^([^,]+)")
  if not sidebar_pane or sidebar_pane == "" then return end

  -- Verify the pane actually exists before sending
  local exists = vim.fn.system(
    "tmux list-panes -F '#{pane_id}' | grep -qF '" .. sidebar_pane .. "' && echo 1 || echo 0"
  ):gsub("%s+$", "")
  if exists ~= "1" then return end

  vim.fn.jobstart({
    "tmux", "send-keys", "-t", sidebar_pane, ":NvimTreeRefresh\r", "",
  })
end

-- Main sync entry point. Safe to call from any autocmd or keybind.
-- Uses vim.schedule so it never blocks the event loop.
function M.sync()
  vim.schedule(function()
    -- 1. Reload buffers that changed on disk (silent — no "press ENTER" prompts)
    vim.cmd("silent! checktime")

    -- 2. Refresh gitsigns (re-reads HEAD, recomputes all hunk signs + branch name)
    local ok_gs, gs = pcall(require, "gitsigns")
    if ok_gs then
      pcall(gs.refresh)
    end

    -- 3. Reload nvim-tree (full tree rebuild + git status)
    local ok_nt, nt = pcall(require, "nvim-tree.api")
    if ok_nt then
      pcall(nt.tree.reload)
    end

    -- 4. Refresh treemux sidebar (separate nvim process)
    _refresh_treemux_sidebar()
  end)
end

return M
