<!-- LOC cap: 288 (source: 2057, ratio: 0.14, updated: 2026-03) -->
# Architecture

## Overview

aid is an open-source, terminal-native AI IDE: tmux workspace orchestration + nvim config + persistent Opencode AI pane, all in one repo.

It reconstructs the VS Code/Cursor UX entirely in the terminal — no Electron, no GUI, SSH-friendly. Three persistent panes: file-tree sidebar (left), nvim editor (middle), Opencode AI assistant (right). A single `boot.sh` curl gives a fully working IDE on any machine.

**Identity**: not a Neovim distribution (like LazyVim) — a *workspace environment* that orchestrates multiple nvim instances and tmux panes into a cohesive IDE. LazyVim configures an editor; aid builds a workspace around one.

Install path: `~/.local/share/aid` (override: `TDL_DIR`).

## Boot sequence

```
boot.sh (curl | bash)
  └── git clone → $DEST   (or git pull if already installed)
  └── install.sh
        ├── 1. pynvim (Arch only)
        ├── 2. TPM clone
        ├── 3. treemux plugin via TPM headless (tmux -L tdl -f <TDL_DIR>/tmux.conf)
        ├── 4. symlinks:
        │       ~/.config/nvim-tdl       → aid/nvim/
        │       ~/.config/nvim-treemux/  → aid/nvim-treemux/ (individual files)
        │       ~/.config/tmux/plugins/treemux/.../watch_and_update.sh → aid/nvim-treemux/
        │       ~/.config/tmux/ensure_treemux.sh → aid/ensure_treemux.sh
        │       ~/.local/bin/aid         → aid/aid.sh
        ├── 5. nvim-treemux headless lazy sync  (NVIM_APPNAME=nvim-treemux) ← spinner
        ├── 5b. main nvim headless lazy sync    (NVIM_APPNAME=nvim-tdl)     ← spinner
        └── 6. (no shell injection — aid is a standalone script in PATH)
```

## Runtime sequence (`aid` command)

`aid.sh` is a standalone script symlinked into `~/.local/bin/aid`. `TDL_DIR` is resolved via `realpath "${BASH_SOURCE[0]}"` — no shell function, no `aliases.sh` dependency.

### Session routing

```
aid -l / --list   → list sessions (tmux list-sessions) and exit
aid -a            → interactive list; auto-attach if only one session
aid -a <name>     → attach to named session directly and exit
aid               → create a new session in $PWD
```

`attach_or_switch` helper uses `switch-client` when already inside tmux (attach fails inside a session).

### Session creation

```
aid.sh
  ├── resolve TDL_DIR via realpath
  ├── session name: aid@<basename> (deduplicated with numeric suffix)
  ├── parse .aidignore (walks up from launch_dir, up to 20 levels)
  ├── tmux -L tdl -f <TDL_DIR>/tmux.conf new-session -d -s <session>
  ├── set-environment -g:
  │       TDL_DIR             → <TDL_DIR>
  │       TDL_IGNORE          → comma-separated .aidignore entries
  │       OPENCODE_CONFIG_DIR → <TDL_DIR>/opencode
  │       NVIM_APPNAME        → nvim-tdl
  │       TDL_NVIM_SOCKET     → /tmp/tdl-nvim-<session>.sock
  │   (all panes inherit these; must be set before ensure_treemux.sh runs)
  ├── sleep 1.5  (wait for sidebar.tmux to register @treemux-key-Tab)
  ├── capture editor_pane_id (list-panes -F "#{pane_id}" | head -1)
  ├── split-window -h -p 29 → spawned directly into opencode process
  │       (no shell prompt — bypasses zsh autocorrect, no send-keys mangling)
  │       capture opencode_pane_id
  ├── select-pane editor_pane_id
  ├── run-shell ensure_treemux.sh -t editor_pane_id  (opens sidebar)
  ├── respawn-pane -k editor_pane_id → nvim restart loop
  │       cd <launch_dir>; while true; do
  │         rm -f <nvim_socket>
  │         NVIM_APPNAME=nvim-tdl nvim --listen <nvim_socket>
  │       done
  │       (bypasses interactive shell entirely — zsh autocorrect/send-keys
  │        mangling cannot fire; pane is never a bare shell)
  └── attach -t <session>
```

### Editor pane restart loop

The editor pane is respawned via `respawn-pane -k` directly into the nvim restart loop — bypassing the interactive shell entirely. When the user quits nvim (`:q`), the loop immediately restarts it on the same socket path. The pane is **never** a bare shell — the only way to exit is to close the tmux window.

### Stable pane IDs

`editor_pane_id` and `opencode_pane_id` are captured by stable `#{pane_id}` tokens immediately after creation. Subsequent operations (treemux inserting the sidebar, layout changes) do not affect them.

## Environment variables (tmux server scope)

Set via `tmux -L tdl set-environment -g` before any pane is created. All child shells inherit them automatically.

| Variable | Value | Purpose |
|---|---|---|
| `TDL_DIR` | path to `aid/main/` | Lets scripts locate the repo without assumptions about install path |
| `TDL_IGNORE` | comma-separated patterns | Populated from `.aidignore` (found by walking up from `$PWD`) |
| `NVIM_APPNAME` | `nvim-tdl` | Isolates nvim config to `~/.config/nvim-tdl` |
| `OPENCODE_CONFIG_DIR` | `$TDL_DIR/opencode` | Isolates opencode config (commands, package.json) from `~/.config/opencode` |
| `TDL_NVIM_SOCKET` | `/tmp/tdl-nvim-<session>.sock` | Sidebar nvim reads this at startup to set `g:nvim_tree_remote_socket_path` |

## Pane ownership

All pane geometry is owned by `aid.sh` and `ensure_treemux.sh`. `tmux.conf` owns only plugin config and keybinds — **never sizes** — with one exception: `@treemux-tree-width 26` must live in `tmux.conf` so treemux reads it before `sidebar.tmux` runs (it cannot be set in `aid.sh` after the sidebar is already open).

`aid.sh` does the initial editor/opencode split at `-p 29` (29% for opencode). After `ensure_treemux.sh` opens the sidebar, it re-enforces the opencode column count to 28% of the total window width via `resize-pane -x`, accounting for the sidebar's added width.

## Isolation strategy

aid runs entirely isolated from the user's existing nvim and tmux setup.

| Layer | Isolation mechanism |
|---|---|
| tmux server | `tmux -L tdl` — dedicated named socket, separate from the default server |
| tmux config | `tmux -L tdl -f <TDL_DIR>/tmux.conf` — `-f` suppresses `~/.tmux.conf` and `~/.config/tmux/tmux.conf` entirely |
| main nvim | `NVIM_APPNAME=nvim-tdl` — config at `~/.config/nvim-tdl` → `aid/nvim/` |
| sidebar nvim | `NVIM_APPNAME=nvim-treemux` — config at `~/.config/nvim-treemux/` |
| opencode | `OPENCODE_CONFIG_DIR=$TDL_DIR/opencode` — commands and package.json at `aid/opencode/`, not `~/.config/opencode` |
| shell | `aid` is a standalone script in `~/.local/bin` — no shell function injection, no `~/.bashrc` modification |

Symlink table:

| Config path | Points to |
|---|---|
| `~/.config/nvim-tdl` | `aid/nvim/` |
| `~/.config/nvim-treemux/` | `aid/nvim-treemux/` (individual files) |
| `~/.config/tmux/ensure_treemux.sh` | `aid/ensure_treemux.sh` |
| `~/.config/tmux/plugins/treemux/.../watch_and_update.sh` | `aid/nvim-treemux/watch_and_update.sh` |
| `~/.local/bin/aid` | `aid/aid.sh` |

`~/.config/nvim` is **not touched** — the user's existing nvim config (if any) is preserved.

## `nvim/init.lua` structure

The load order within `init.lua` is intentional and must be preserved:

```
1. LEADER KEY           — vim.g.mapleader before any plugin reads it
2. netrw disable        — vim.g.loaded_netrw before VimEnter
3. OPTIONS              — vim.opt.* globals before plugins/autocmds fire
                          (critical: autocmds reading vim.o.number must see
                          the global value, not Neovim's built-in default)
4. GIT-SYNC require     — local sync = require("sync")
5. CHEATSHEET           — _cs_open() (plain edit, no styling/autocmds/buffer tracking)
6. BOOTSTRAP LAZY       — vim.opt.rtp:prepend(lazypath)
7. KEYMAPS              — vim.keymap.set() calls (reference sync, _cs_open, etc.)
8. PLUGINS              — require("lazy").setup({...})
9. APPEARANCE           — vim.api.nvim_set_hl(), vim.opt.guicursor
10. DIAGNOSTICS         — vim.diagnostic.config()
11. AUTOCMDS            — FileType, FocusGained, TermClose, DirChanged, VimEnter
```

The `VimEnter` autocmd (opens nvim-tree outside tmux; opens cheatsheet on empty buffer) lives at the **top level** of `init.lua` in the AUTOCMDS section — not inside any plugin's `config` function. Plugin `config` functions run during `lazy.setup()`, which itself runs before `VimEnter` fires. Registering a `VimEnter` autocmd inside a plugin config is safe only if the plugin loads eagerly before `VimEnter`; for reliability, top-level registration is required.

## Cheatsheet system

`nvim/cheatsheet.md` is opened as a normal file buffer (`vim.cmd("edit " .. path)`) when nvim starts with no file argument. No special read-only styling, no buffer tracking, no window-option autocmds — just a plain `edit`. Re-open at any time with `<leader>?`. Dismissed by opening any other file; no auto-restore logic.

The path is built from `TDL_DIR` (env, real path) rather than `stdpath("config")` (symlink) to avoid W13 "file created after editing started" on writes.

## Git-sync coordinator (`nvim/lua/sync.lua`)

Because the two nvim instances are isolated processes, external git operations (branch switch, pull, stash pop via lazygit) leave both instances with stale state: gitsigns shows old-branch hunks, the statusline branch name is wrong, nvim-tree holds paths that no longer exist on the new branch (→ crash on next refresh).

`nvim/lua/sync.lua` exports two functions:

**`sync()`** — lightweight git-state refresh, safe to call from autocmds:
```
sync.sync()
  1. silent! checktime          — reload all buffers changed on disk
  2. gitsigns.refresh()         — re-read HEAD, recompute hunk signs + branch name
  3. nvim-tree.api.tree.reload()— full tree rebuild + git status
  4. tmux -L tdl send-keys → sidebar — :lua require('aidignore').reset()
     mutates explorer.filters.ignore_list in-place then calls api.tree.reload();
     no setup() re-call, no visual disruption.
     (see aidignore.lua for private API notes and S2 fallback)
```

**`reload()`** — full workspace reload, bound to `<leader>R`:
```
sync.reload()
  1. tmux -L tdl source-file $TDL_DIR/tmux.conf — hot-reload tmux config
  2. source $MYVIMRC                             — hot-reload nvim config
  3. aidignore.reset()                           — re-read .aidignore from disk,
                                                   re-apply nvim-tree filters,
                                                   restart file watcher
  4. sync()                                      — git state + buffers + sidebar
```

Step 4 of `sync()` locates the sidebar pane by reading the tmux server option `@-treemux-registered-pane-$TMUX_PANE`, which `ensure_treemux.sh` writes when it opens the sidebar. It verifies the pane still exists before sending. All tmux calls use `tmux -L tdl` to target the isolated server socket.

All operations are `pcall`-wrapped and run inside `vim.schedule` — never blocks the event loop.

### Trigger points

`sync()` is wired to four trigger points in `nvim/init.lua`:

| Trigger | Why |
|---|---|
| `FocusGained` / `BufEnter` / `CursorHold` / `CursorHoldI` | nvim regains focus after any external tool |
| `TermClose` | fires the moment the lazygit float buffer closes |
| explicit call after `vim.cmd("LazyGit")` | belt-and-suspenders: catches the case where `TermClose` fires before the float is fully torn down |

### Treemux self-heal

The sidebar nvim cannot receive `sync()` calls directly (separate process, no shared Lua state). Instead, `treemux_init.lua` registers its own autocmds:

- `FileChangedShell` — sets `vim.v.fcs_choice = "reload"` (suppresses the blocking prompt) and calls `nvim-tree.api.tree.reload()`
- `FileChangedShellPost` — `silent! checktime` + `nvim-tree.api.tree.reload()` for files deleted by a branch switch

### Future direction (TODO)

The current sidebar refresh uses `tmux send-keys`, which has a minor timing dependency (the pane must be idle). The `nvim-tree-remote` plugin already maintains a msgpack-RPC channel between the two nvim instances (`transport.exec(ex, addr_override)`). The reverse direction — main nvim pushing a command into the sidebar nvim — could use the same channel via `vim.fn.sockconnect` to the sidebar's `$NVIM` socket. This would be more robust and should be evaluated once the current approach is validated in daily use.

## Opencode integration

Opencode runs in the rightmost pane (initial split 29%; resized to 28% after sidebar opens). It is isolated from the user's `~/.config/opencode` via `OPENCODE_CONFIG_DIR=$TDL_DIR/opencode`.

Custom slash commands live in `aid/opencode/commands/`:
- `commit.md` — generates a conventional commit message from staged diff
- `udoc.md` — updates `aid/docs/` to reflect recent code changes (with LOC cap, archiving, and pruning)

`aid/opencode/package.json` declares the project name for the opencode workspace.

## `.aidignore` system (`nvim/lua/aidignore.lua`)

`.aidignore` is a per-project file (one pattern per line, `#` comments, blank lines ignored) that drives file hiding in both nvim-tree and Telescope. `aid.sh` walks up from the launch dir to find the nearest `.aidignore` at startup; if none is found, an empty one is created in the launch dir so the file watcher has a target from day one.

### Module API

```
aidignore.patterns()  — returns { raw = {...}, telescope = {...} }
                         raw:       plain strings for nvim-tree filters.custom
                                    (glob patterns excluded — triggers E33 in vim.fn.match)
                         telescope: Lua patterns for file_ignore_patterns
                         result is cached until reset() or watch() fires

aidignore.watch()     — start (or restart) a vim.uv fs_event watcher on the
                         nearest .aidignore; on change: bust cache + re-apply
                         Called from reset() and directly after nvim-tree setup.

aidignore.reset()     — bust cache + _apply_to_nvimtree() + restart watch()
                         Called from DirChanged autocmd and reload().
```

### Live filter update mechanism (`_apply_to_nvimtree`)

nvim-tree does not expose a public API to change filters without calling `setup()` again. Calling `setup()` re-calls `purge_all_state()` which destroys the window/explorer — unacceptable for live reload.

The solution: mutate `require("nvim-tree.core").get_explorer().filters.ignore_list` in-place, then call `api.tree.reload()`. `ignore_list` is a `table<string, boolean>` read on every `should_filter()` call in nvim-tree's render loop. Mutating it + reloading updates the visible tree with zero visual disruption (no window close/reopen, cursor preserved).

**Stability**: `ignore_list` has existed under this exact name since nvim-tree's multi-instance refactor (PR #2841), with 33 commits to `filters.lua` since then — name unchanged.

**Fallback (S2)**: if `ignore_list` is ever renamed/removed, the fallback is `tmux kill-pane <sidebar_pane_id>` + re-run `ensure_treemux.sh`. ~0.5s visual glitch but fully public API. See comment in `aidignore.lua:99–103`.

### Sidebar integration

`aidignore.lua` lives in `nvim/lua/`. The sidebar nvim (`nvim-treemux`) is a separate process with its own `package.path`. To allow `require("aidignore")` from `treemux_init.lua`, `aid.sh` exports `TDL_DIR` into the tmux server environment, and `treemux_init.lua` prepends `TDL_DIR/nvim/lua` to `package.path` before any `require()` call.

Note: `rtp` would not work here — nvim's `rtp` expects directories that *contain* a `lua/` subdir, not the `lua/` dir itself. `package.path` is correct.

At startup, `treemux_init.lua` populates nvim-tree `filters.custom` from `TDL_IGNORE` env (set by `aid.sh` from `.aidignore` at session start). After `nvim-tree.setup()`, it calls `aidignore.watch()` for live updates. When the main nvim's `sync()` fires (e.g. after a git op), it sends `:lua require('aidignore').reset()` to the sidebar pane — this re-reads `.aidignore` from disk, mutates `ignore_list`, and reloads the tree.

## Differentiators

### vs. GUI IDEs (VS Code, Cursor)
- Terminal-native: runs in tmux, SSH-friendly, no Electron
- Opencode (MIT, provider-agnostic) replaces proprietary Copilot/Cursor AI
- AI lives in a tmux pane — persistent across editor restarts, can interact with the terminal directly

### vs. Neovim distributions (LazyVim, SpaceVim)
- **Workspace vs. editor**: aid orchestrates multiple nvim instances + tmux panes; LazyVim only configures the editor process
- **Persistent sidebar**: separate `NVIM_APPNAME=nvim-treemux` instance — never closes on focus loss, tracks any `cd`
- **Cross-project bookmarks**: `~/.local/share/nvim/global_bookmarks` — unlike Harpoon, works across unrelated directories
- **Unified statusline**: `vim-tpipeline` exports nvim statusline to tmux status bar, visible across all panes
- **Session management**: `ensure_treemux.sh` auto-recreates the layout on reattach

### vs. Omarchy's tdl (the original inspiration)
- Adds persistent sidebar management, global bookmarks, statusline integration, and worktree-aware lazygit
- `watch_and_update.sh` fork: sidebar root changes on *any* `cd`, not just when exiting the current root
- Upstream treemux bug fixes: symlink handling, dotfile visibility

## Key design decisions

- **`aid.sh` is a standalone script, not a shell function**: symlinked into `~/.local/bin/aid` by `install.sh`. `TDL_DIR` resolved via `realpath "${BASH_SOURCE[0]}"`. No `aliases.sh`, no shell injection, no `~/.bashrc` modification.
- **Session routing in `aid.sh`**: `aid` with no args creates a new session. `-a` attaches (interactive list or named). `-l` lists sessions. No subcommands (`aid ls`, `aid new`) — flags only.
- **Symlinked** for nvim config and treemux scripts: allows `install.sh` re-runs to update transparently.
- **`NVIM_APPNAME=nvim-tdl`** (not `nvim`): aid's nvim config lives at `~/.config/nvim-tdl`, leaving `~/.config/nvim` untouched for the user's personal config.
- **`tmux -L tdl`** for all tmux commands: every script (`aid.sh`, `ensure_treemux.sh`, `sync.lua`) targets the named socket explicitly — no ambiguity about which server is being addressed.
- **`TDL_DIR` env var** exported into the tmux server: `set-environment -g TDL_DIR` so that all panes and scripts can locate the repo root without assumptions about install path.
- **Orphan install**: `boot.sh` is designed to be piped directly from curl. No pre-existing clone required.
- **Idempotent**: all steps in `install.sh` are safe to re-run (directory guards, `ln -sfn` for dir symlinks).
- **`--git-dir` not `--git-common-dir`** for lazygit worktree detection: `--git-common-dir` returns the bare repo root, causing git to use it as the work-tree and see all files as deleted. `--git-dir` returns the worktree-specific path (`aid/worktrees/main`) which correctly scopes the index.
