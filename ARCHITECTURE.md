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
aid ls            → list sessions (tmux list-sessions) and exit
aid new           → skip routing, always create a new session
aid <name>        → attach to named session directly and exit
aid               → examine existing sessions:
                      0 sessions → fall through to create
                      1 session  → attach immediately and exit
                      2+ sessions → print numbered list, prompt for choice
                                    [n] = create new session in $PWD
```

### Session creation

```
aid.sh
  ├── resolve TDL_DIR via realpath
  ├── session name: nvim@<basename> (deduplicated with numeric suffix)
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
  ├── split-window -h -p 29 → opencode pane; capture opencode_pane_id
  ├── send-keys to opencode_pane_id:
  │       OPENCODE_CONFIG_DIR=<...> opencode <launch_dir>
  ├── select-pane editor_pane_id
  ├── run-shell ensure_treemux.sh -t editor_pane_id  (opens sidebar)
  ├── send-keys to editor_pane_id:
  │       cd <launch_dir>
  │       while true; do
  │         rm -f <nvim_socket>
  │         NVIM_APPNAME=nvim-tdl nvim --listen <nvim_socket>
  │       done
  └── attach -t <session>
```

### Editor pane restart loop

The editor pane runs nvim inside an infinite `while true` loop. When the user quits nvim (`:q`), the loop immediately restarts it on the same socket path. The pane is **never** a bare shell — the only way to exit is to close the tmux window or run `aid kill`.

`NVIM_APPNAME` is set both in the server environment (`set-environment -g`) and inline in the `send-keys` command (belt-and-suspenders: `set-environment` only affects shells started *after* the call).

### Stable pane IDs

`editor_pane_id` and `opencode_pane_id` are captured by stable `#{pane_id}` tokens immediately after creation. Subsequent operations (treemux inserting the sidebar, layout changes) do not affect them — all `send-keys` and `select-pane` calls target by ID, not by position.

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

All pane geometry is owned by `aid.sh`. `tmux.conf` owns only plugin config and keybinds — **never sizes** — with one exception: `@treemux-tree-width 21` must live in `tmux.conf` so treemux reads it before `sidebar.tmux` runs (it cannot be set in `aid.sh` after the sidebar is already open).

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
5. CHEATSHEET           — _cs_open(), _cs_apply_style(), BufEnter autocmds
6. BOOTSTRAP LAZY       — vim.opt.rtp:prepend(lazypath)
7. KEYMAPS              — vim.keymap.set() calls (reference sync, _cs_open, etc.)
8. PLUGINS              — require("lazy").setup({...})
9. APPEARANCE           — vim.api.nvim_set_hl(), vim.opt.guicursor
10. DIAGNOSTICS         — vim.diagnostic.config()
11. AUTOCMDS            — FileType, FocusGained, TermClose, DirChanged, VimEnter
```

The `VimEnter` autocmd (opens nvim-tree outside tmux; opens cheatsheet on empty buffer) lives at the **top level** of `init.lua` in the AUTOCMDS section — not inside any plugin's `config` function. Plugin `config` functions run during `lazy.setup()`, which itself runs before `VimEnter` fires. Registering a `VimEnter` autocmd inside a plugin config is safe only if the plugin loads eagerly before `VimEnter`; for reliability, top-level registration is required.

## Cheatsheet system

`nvim/cheatsheet.md` is displayed as a styled read-only welcome buffer when nvim starts with no file argument. It is auto-dismissed when a real file is opened, and auto-restored when the last real file is closed.

### Buffer lifecycle

```
VimEnter (is_empty=true)
  └── vim.schedule(_cs_open)
        └── edit cheatsheet.md → _cs_apply_style()
              sets: modifiable=false, readonly, buftype=nofile
              sets window-local: number=false, signcolumn=no, foldcolumn=0

BufEnter (real file opened)
  └── _cs_buf is valid + entering buf is a readable file
        → setlocal number signcolumn=yes ... (restore window options)
        → vim.schedule: nvim_buf_delete(_cs_buf)

BufEnter (empty unnamed buffer — last file was closed)
  └── bt=="" and name==""
        → vim.schedule(_cs_open)   [cheatsheet re-appears]

BufWinEnter (any normal file displayed)
  └── setlocal number signcolumn=yes ...
      (belt-and-suspenders: ensures gutter options are correct even if
       BufEnter dismiss fired before filereadable() could verify)
```

### Window option restoration

When cheatsheet is dismissed, `_cs_apply_style` set window-local overrides (`number=false`, `signcolumn=no`, etc.) that shadow the global `vim.opt.*` values. Restoration uses:

```lua
vim.cmd("setlocal number relativenumber& signcolumn=yes foldcolumn& statuscolumn& wrap& cursorline&")
```

The trailing `&` suffix means "inherit from global" for those options. `number` and `signcolumn` are set explicitly to their desired values (not inherited) because the global defaults must be positively asserted.

## Git-sync coordinator (`nvim/lua/sync.lua`)

Because the two nvim instances are isolated processes, external git operations (branch switch, pull, stash pop via lazygit) leave both instances with stale state: gitsigns shows old-branch hunks, the statusline branch name is wrong, nvim-tree holds paths that no longer exist on the new branch (→ crash on next refresh).

`nvim/lua/sync.lua` exports two functions:

**`sync()`** — lightweight git-state refresh, safe to call from autocmds:
```
sync.sync()
  1. silent! checktime          — reload all buffers changed on disk
  2. gitsigns.refresh()         — re-read HEAD, recompute hunk signs + branch name
  3. nvim-tree.api.tree.reload()— full tree rebuild + git status
  4. tmux -L tdl send-keys → sidebar — :NvimTreeRefresh in the treemux nvim instance
```

**`reload()`** — full workspace reload, bound to `<leader>R`:
```
sync.reload()
  1. tmux -L tdl source-file $TDL_DIR/tmux.conf — hot-reload tmux config
  2. source $MYVIMRC                             — hot-reload nvim config
  3. sync()                                      — git state + buffers + sidebar
```

Step 4 of `sync()` locates the sidebar pane by reading the tmux server option `@-treemux-registered-pane-$TMUX_PANE`, which `ensure_treemux.sh` writes when it opens the sidebar. It verifies the pane still exists before sending. All tmux calls use `tmux -L tdl` to target the isolated server socket.

All operations are `pcall`-wrapped and run inside `vim.schedule` — never blocks the event loop.

### Trigger points

`sync()` is wired to three trigger points in `nvim/init.lua`:

| Trigger | Why |
|---|---|
| `FocusGained` / `BufEnter` / `CursorHold` | nvim regains focus after any external tool |
| `TermClose` | fires the moment the lazygit float buffer closes |
| explicit call after `vim.cmd("LazyGit")` | belt-and-suspenders: catches the case where `TermClose` fires before the float is fully torn down |

### Treemux self-heal

The sidebar nvim cannot receive `sync()` calls directly (separate process, no shared Lua state). Instead, `treemux_init.lua` registers its own autocmds:

- `FileChangedShell` — sets `vim.v.fcs_choice = "reload"` (suppresses the blocking prompt) and calls `nvim-tree.api.tree.reload()`
- `FileChangedShellPost` — `silent! checktime` + `nvim-tree.api.tree.reload()` for files deleted by a branch switch

### Future direction (TODO)

The current sidebar refresh uses `tmux send-keys`, which has a minor timing dependency (the pane must be idle). The `nvim-tree-remote` plugin already maintains a msgpack-RPC channel between the two nvim instances (`transport.exec(ex, addr_override)`). The reverse direction — main nvim pushing a command into the sidebar nvim — could use the same channel via `vim.fn.sockconnect` to the sidebar's `$NVIM` socket. This would be more robust and should be evaluated once the current approach is validated in daily use.

## Opencode integration

Opencode runs in the rightmost pane (29% of total width). It is isolated from the user's `~/.config/opencode` via `OPENCODE_CONFIG_DIR=$TDL_DIR/opencode`.

Custom slash commands live in `aid/opencode/commands/`:
- `commit.md` — generates a conventional commit message from staged diff
- `udoc.md` — updates `aid/docs/` to reflect recent code changes

`aid/opencode/package.json` declares the project name for the opencode workspace.

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
- **Session routing in `aid.sh`**: `aid` with no args auto-attaches when one session exists, shows a numbered menu when multiple exist. `aid new` forces creation. `aid <name>` attaches directly. `aid ls` lists sessions.
- **Symlinked** for nvim config and treemux scripts: allows `install.sh` re-runs to update transparently.
- **`NVIM_APPNAME=nvim-tdl`** (not `nvim`): aid's nvim config lives at `~/.config/nvim-tdl`, leaving `~/.config/nvim` untouched for the user's personal config.
- **`tmux -L tdl`** for all tmux commands: every script (`aid.sh`, `ensure_treemux.sh`, `sync.lua`) targets the named socket explicitly — no ambiguity about which server is being addressed.
- **`TDL_DIR` env var** exported into the tmux server: `set-environment -g TDL_DIR` so that all panes and scripts can locate the repo root without assumptions about install path.
- **Orphan install**: `boot.sh` is designed to be piped directly from curl. No pre-existing clone required.
- **Idempotent**: all steps in `install.sh` are safe to re-run (directory guards, `grep -qF` before inject, `ln -sfn` for dir symlinks).
- **`--git-dir` not `--git-common-dir`** for lazygit worktree detection: `--git-common-dir` returns the bare repo root, causing git to use it as the work-tree and see all files as deleted. `--git-dir` returns the worktree-specific path (`aid/worktrees/main`) which correctly scopes the index.
