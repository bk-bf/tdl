-- tdlignore.lua — reads .tdlignore from the cwd (or any ancestor) and returns
-- a list of patterns suitable for nvim-tree filters.custom and Telescope
-- file_ignore_patterns.
--
-- Usage:
--   local tdlignore = require("tdlignore")
--   local patterns  = tdlignore.patterns()   -- call once, result is cached
--
-- File format: one pattern per line, # = comment, blank lines ignored.
-- Patterns are plain strings (no regex). nvim-tree matches them as substrings
-- against the full path; Telescope uses them as Lua patterns, so we escape
-- any regex-special chars before passing to Telescope.

local M = {}

local _cache = nil  -- cached {path = ..., patterns = {...}}

-- Walk up from `start_dir` looking for .tdlignore. Returns the file path or nil.
local function _find(start_dir)
  local dir = start_dir or vim.fn.getcwd()
  for _ = 1, 20 do
    local candidate = dir .. "/.tdlignore"
    if vim.fn.filereadable(candidate) == 1 then
      return candidate
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then break end
    dir = parent
  end
  return nil
end

-- Parse the file, return list of raw pattern strings.
local function _parse(filepath)
  local result = {}
  local f = io.open(filepath, "r")
  if not f then return result end
  for line in f:lines() do
    line = line:match("^%s*(.-)%s*$")  -- trim whitespace
    if line ~= "" and line:sub(1, 1) ~= "#" then
      table.insert(result, line)
    end
  end
  f:close()
  return result
end

-- Escape a plain string for use as a Lua pattern (for Telescope).
local function _escape(s)
  return s:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
end

-- Returns { raw = {...}, telescope = {...} }
-- raw      — plain strings for nvim-tree filters.custom
-- telescope — Lua-pattern strings for Telescope file_ignore_patterns
function M.patterns()
  local cwd = vim.fn.getcwd()
  if _cache and _cache.cwd == cwd then
    return _cache.result
  end

  local filepath = _find(cwd)
  local raw = filepath and _parse(filepath) or {}
  local telescope = {}
  for _, p in ipairs(raw) do
    local ep = _escape(p)
    -- Two patterns: bare name at root, or preceded by a path separator.
    -- Telescope matches file_ignore_patterns as Lua patterns against the
    -- full relative path; Lua patterns have no | alternation, so we add two.
    table.insert(telescope, "^" .. ep .. "[/\\]")   -- at root: "hooks/"
    table.insert(telescope, "[/\\]" .. ep .. "[/\\]") -- mid-path: "/hooks/"
    table.insert(telescope, "^" .. ep .. "$")         -- exact bare name
    table.insert(telescope, "[/\\]" .. ep .. "$")     -- trailing: "/hooks"
  end

  local result = { raw = raw, telescope = telescope }
  _cache = { cwd = cwd, result = result }
  return result
end

-- Call this after a DirChanged event to bust the cache.
function M.reset()
  _cache = nil
end

return M
