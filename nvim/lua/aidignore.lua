-- aidignore.lua — reads the nearest .aidignore from disk (walking up from cwd)
-- and returns pattern tables for nvim-tree and Telescope. Watches the file for
-- changes and re-applies filters to nvim-tree automatically when it is saved.
-- If no .aidignore is found, no patterns are applied and all files are shown.
--
-- Usage:
--   local aidignore = require("aidignore")
--   local pats = aidignore.patterns()
--   -- pats.raw       — plain strings for nvim-tree filters.custom
--   -- pats.telescope — Lua-pattern strings for Telescope file_ignore_patterns
--
--   aidignore.watch()   — start watching the current .aidignore (call after setup)
--   aidignore.reset()   — bust cache + restart watcher for new cwd (DirChanged)

local M = {}

local _cache    = nil
local _watcher  = nil   -- active vim.uv fs_event handle
local _watched  = nil   -- path currently being watched

-- Escape a plain string for use as a Lua pattern.
local function _escape(s)
  return s:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
end

-- Walk up from dir, return first .aidignore path found (or nil).
local function _find_aidignore(dir)
  local d = dir
  for _ = 1, 20 do
    local p = d .. "/.aidignore"
    if vim.fn.filereadable(p) == 1 then return p end
    local parent = vim.fn.fnamemodify(d, ":h")
    if parent == d then break end
    d = parent
  end
end

-- Read patterns from a file path. Returns list of plain strings.
local function _read_file(path)
  local raw = {}
  local f = io.open(path, "r")
  if not f then return raw end
  for line in f:lines() do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" and line:sub(1, 1) ~= "#" then
      table.insert(raw, line)
    end
  end
  f:close()
  return raw
end

-- Build pattern tables from a list of plain strings.
local function _build(raw)
  local telescope = {}
  for _, p in ipairs(raw) do
    local ep = _escape(p)
    table.insert(telescope, "^" .. ep .. "[/\\]")
    table.insert(telescope, "[/\\]" .. ep .. "[/\\]")
    table.insert(telescope, "^" .. ep .. "$")
    table.insert(telescope, "[/\\]" .. ep .. "$")
  end
  return { raw = raw, telescope = telescope }
end

-- Re-run nvim-tree setup with current patterns so filters.custom takes effect,
-- then reload the tree. nvim-tree requires a full re-setup to change filters.
local function _apply_to_nvimtree()
  local ok, api = pcall(require, "nvim-tree.api")
  if not ok then return end
  local ok2, nt = pcall(require, "nvim-tree")
  if not ok2 then return end

  local pats = M.patterns()
  -- Minimal re-setup: only update filters, preserve existing config.
  pcall(nt.setup, {
    filters = {
      dotfiles    = false,
      git_ignored = false,
      custom      = pats.raw,
    },
  })
  pcall(api.tree.reload)

  -- Also refresh the treemux sidebar (separate nvim process) via sync.
  local ok_sync, s = pcall(require, "sync")
  if ok_sync then pcall(s.sync) end
end

-- Returns { raw = {...}, telescope = {...} }
function M.patterns()
  if _cache then return _cache end

  -- Read from disk only. If no .aidignore found, no patterns — show everything.
  local path = _find_aidignore(vim.fn.getcwd())
  local raw = path and _read_file(path) or {}

  _cache = _build(raw)
  return _cache
end

-- Start (or restart) watching the .aidignore closest to cwd.
-- Called after nvim-tree setup and on DirChanged.
function M.watch()
  -- Stop any existing watcher.
  if _watcher then
    pcall(function() _watcher:stop() end)
    _watcher = nil
    _watched = nil
  end

  local path = _find_aidignore(vim.fn.getcwd())
  if not path then return end

  local handle = vim.uv.new_fs_event()
  if not handle then return end

  handle:start(path, {}, vim.schedule_wrap(function(err, _, _)
    if err then return end
    -- Bust cache and re-apply filters.
    _cache = nil
    _apply_to_nvimtree()
  end))

  _watcher = handle
  _watched = path
end

-- Bust cache, re-apply filters to nvim-tree, and restart watcher for current cwd.
-- Call from DirChanged autocmd and after workspace reload.
function M.reset()
  _cache = nil
  _apply_to_nvimtree()
  M.watch()
end

return M
