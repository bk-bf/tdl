# Roadmap

## Near-term

- [ ] Fix `.aidignore` — audit current behaviour; ensure patterns are applied consistently across nvim-tree, Telescope, and the sidebar
- [ ] Redo `aid` CLI flags — replace bare subcommands (`aid new`) with POSIX-style flags (`aid -n` / `aid --new`); audit all subcommands for consistency
- [ ] `aid -h` / `aid --help` — inline man page / usage output
- [ ] Support non-Arch distros in `install.sh` (apt/brew pynvim install)
- [ ] Add `aid update` command — git pull + re-run `install.sh`
- [ ] Test on non-Arch machines and environments (Ubuntu, macOS, SSH, tmux version variance)

## Medium-term

- [ ] Opencode pane opt-in via flag to `aid` (`aid --no-ai` skips opencode pane)
- [ ] Self-contained theme system — aid owns its color palette; bufferline, statusbar, treemux, and opencode driven from a single source in the repo (no external theme dependency)

## Deferred / under consideration

- [ ] Dev branch for bleeding-edge work
- [ ] Consider `main` + feature-branches workflow (currently single `master`)
- [ ] Terminal theme sync hook — optional integration point for syncing aid's palette with the host terminal emulator theme

## Done

- [x] **2026-03**: Fix lazygit `--git-dir` worktree detection (use `--git-dir` not `--git-common-dir`; `--git-common-dir` returns bare root, causing phantom deleted files)
- [x] **2026-03**: Move nvim config into aid repo (`aid/nvim/`), symlink `~/.config/nvim → aid/nvim/`
- [x] **2026-03**: Default install path → `~/.local/share/aid` (XDG compliant)
- [x] **2026-03**: Braille spinner on headless nvim sync steps
- [x] **2026-03**: Bare repo + worktree structure (`aid/main/` + `aid/docs/`)
- [x] **2026-03**: Full environment isolation — dedicated tmux server socket (`tmux -L tdl -f`), `NVIM_APPNAME=nvim-tdl`, no tmux.conf injection, `~/.config/nvim` left untouched
- [x] **2026-03**: `sync.lua` — added `reload()` entry point (`<leader>R`): hot-reloads tmux + nvim config then calls `sync()`
- [x] **2026-03**: Fix cheatsheet auto-open (was broken by `nvim .` → fixed to bare `nvim`)
- [x] **2026-03**: Fix `ensure_treemux.sh` layout enforcement (sidebar_pane scoping bug + early exit bug)
- [x] **2026-03**: Fix `status-interval 0` breaking prefix indicator in status bar
- [x] **2026-03**: Move `sync.lua` → `nvim/lua/sync.lua` (fix `module 'sync' not found`)
- [x] **2026-03**: Convert `aid()` shell function in `aliases.sh` to standalone `aid.sh` script; symlinked into `~/.local/bin/aid` by `install.sh`; `TDL_DIR` resolved via `realpath "${BASH_SOURCE[0]}"`
- [x] **2026-03**: Session routing in `aid.sh` — auto-attach to single session; numbered menu for multiple; `aid ls` / `aid new` / `aid <name>` subcommands
- [x] **2026-03**: Stable pane IDs — capture `editor_pane_id` and `opencode_pane_id` by `#{pane_id}` immediately after creation; immune to treemux sidebar insertion
- [x] **2026-03**: Editor pane restart loop — `while true; do rm -f <socket>; nvim --listen <socket>; done`; pane is never a bare shell
- [x] **2026-03**: `NVIM_APPNAME` set in tmux server env (`set-environment -g`) and inline in send-keys (belt-and-suspenders)
- [x] **2026-03**: `OPENCODE_CONFIG_DIR` set in tmux server env + inline in opencode send-keys; isolates opencode config to `aid/opencode/`
- [x] **2026-03**: `TDL_NVIM_SOCKET` set in tmux server env before `ensure_treemux.sh` runs; sidebar nvim reads it at startup to set `g:nvim_tree_remote_socket_path`
- [x] **2026-03**: `@treemux-tree-width 21` moved to `tmux.conf` (must be set before `sidebar.tmux` runs)
- [x] **2026-03**: Fix treemux file-open creating unwanted split — `tabnew_follow_symlinks` sets `tmux_opts.pane = nil` to disable fallback split
- [x] **2026-03**: Fix line numbers / sign column missing after cheatsheet dismissed (BUG-004) — moved OPTIONS block to top of `init.lua` before all plugins/autocmds; explicit `setlocal number signcolumn=yes` in dismiss + `BufWinEnter` belt-and-suspenders autocmd
- [x] **2026-03**: Fix cheatsheet `VimEnter` autocmd registered too late — moved from inside nvim-tree's `config` function to top-level AUTOCMDS section of `init.lua`
- [x] **2026-03**: Fix cheatsheet restore when last file is closed — `BufEnter` autocmd detects empty unnamed buffer and calls `_cs_open()`
- [x] **2026-03**: Fix bufferline not rendering on startup — `event = "VimEnter"` + `config` with `vim.defer_fn(redrawtabline, 50)`
- [x] **2026-03**: Fix cheatsheet gmatch crash (`init.lua:82`) — `for pre, key, post` had 3 captures but pattern only yielded 2; fixed to `for pre, post`
- [x] **2026-03**: Add `numhl = true` to gitsigns — line numbers colored by git status (add/change/delete)
- [x] **2026-03**: Disable spell checking by default — removed `spell = true` from FileType autocmd; `<leader>sS` still toggles; German (`de`) spelllang still available via `<leader>sd`
- [x] **2026-03**: Add opencode custom commands — `commit.md` (conventional commit from staged diff), `udoc.md` (update docs to reflect code changes)
- [x] **2026-03**: README — usage gif/screenshot added
- [x] **2026-03**: Expand nvim config docs — plugin list, keymaps, LSP setup documented
