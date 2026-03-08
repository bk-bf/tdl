# Decisions

Architecture decision records — why things are the way they are.

ADR statuses:
- **Under consideration** — open question, no decision made, may block other work
- **Made** — decided and implemented
- **Superseded** — previously made, overridden by a later ADR (kept for historical record)

Archived ADRs (superseded and no longer referenced by active work) are in `archive/DECISIONS-2026-03.md`.

---

## Under Consideration

*(none)*

---

## Made

---

### ADR-013: Sidebar architecture — nvim-tree inside main nvim (treemux removed)

**Date**: 2026-03
**Status**: Made

**Decision**: Remove treemux. The file tree sidebar runs as a native nvim-tree split inside the main nvim instance. The layout is two tmux panes: editor (nvim, with nvim-tree split) | opencode.

**What was removed**:
- `nvim-treemux/` directory (`treemux_init.lua`, `watch_and_update.sh`, `lazy-lock.json`)
- `ensure_treemux.sh`
- `AID_NVIM_SOCKET` env var and socket wiring in `aid.sh`
- Treemux poll loop in `aid.sh` (`@treemux-key-Tab` wait)
- `@treemux-tree-width`, `@treemux-tree-client`, `@treemux-tree-nvim-init-file`, `@treemux-nvim-command`, `@treemux-python-command` options in `tmux.conf`
- TPM + treemux plugin lines in `tmux.conf`
- `NVIM_APPNAME=treemux` and `XDG_CONFIG_HOME` sidebar references
- `not vim.env.TMUX` guard on VimEnter nvim-tree autocmd in `init.lua`

**What replaces it**:
- nvim-tree was already fully configured in `init.lua` (lines 322–370) and already opened on VimEnter outside tmux; the guard was the only thing suppressing it inside tmux sessions
- `<leader>t` toggles the tree; VimEnter autocmd reopens it on nvim restart
- `aidignore` live reload works trivially — same process, no `package.path` hack needed
- Layout correction (`ensure_treemux.sh`) is gone — two-pane layout needs no correction

**Reason**: The treemux architecture accrued structural debt (second lazy.nvim stack, 1 s poll loop, cross-process RPC, `package.path` hack, TPM dependency) without delivering a meaningful benefit. The "sidebar survives `:q`" argument was moot because the editor pane runs in a `while true` restart loop — nvim never exits permanently. Bugs BUG-008 and BUG-010, and work item T-006, are dissolved by this change. The user experience is equivalent or better: `<leader>t` gives a toggle that treemux never provided.

**ADR-009 note**: ADR-009 (shared `package.path` for sidebar nvim) is now obsolete — kept for historical record.
**ADR-006 note**: ADR-006 reference to `NVIM_APPNAME=treemux` is now historical — the isolation model is preserved for main nvim; the treemux variant is gone.

---

### ADR-001: Install path `~/.local/share/aid`

**Date**: 2026-03
**Decision**: Default install to `~/.local/share/aid`, override with `TDL_DIR`.
**Reason**: XDG Base Directory spec — `~/.local/share` is the correct location for user-installed application data (scripts, plugins, runtime files). Previous default `~/Documents/Projects/special_projects/tdl` was personal/idiosyncratic.

---

### ADR-002: Orphan `dev-docs` branch for private documentation

**Date**: 2026-03
**Decision**: Keep architecture, roadmap, bugs, and decisions in an orphan `dev-docs` branch with a git worktree at `aid/docs/`. Never merge into `master` or any code branch.
**Reason**: Documentation must be markdown + version-controlled for LLM-driven workflow, but should not be cloned by users running `boot.sh`. A separate private repo adds context-switching overhead; an orphan branch with a worktree gives file-system access without contaminating the public install.

---

### ADR-005: `--git-dir` not `--git-common-dir` for lazygit worktree detection

**Date**: 2026-03
**Decision**: The `<leader>gg` keybind uses `git rev-parse --git-dir` to resolve `GIT_DIR`, not `--git-common-dir`.
**Reason**: `--git-common-dir` returns the bare repo root (e.g. `aid/`). When set as `GIT_DIR` with `GIT_WORK_TREE=aid/main/`, git treats the bare root as the work-tree and sees all committed files as deleted + all files in `main/` as untracked. `--git-dir` returns the worktree-specific path (e.g. `aid/worktrees/main`) which correctly scopes the index to the checked-out branch, giving lazygit a clean view.

---

### ADR-006: Full environment isolation

**Date**: 2026-03
**Decision**: aid must not conflict with the user's existing nvim or tmux setup. All runtime state is isolated:
- tmux: dedicated server socket `tmux -L aid -f <AID_DIR>/tmux.conf` — `-f` suppresses all user tmux configs
- nvim: `XDG_CONFIG_HOME=$HOME/.config/aid` set in the tmux server environment; `NVIM_APPNAME=nvim` (main) and `NVIM_APPNAME=treemux` (sidebar) resolve to `~/.config/aid/nvim` and `~/.config/aid/treemux` respectively. `~/.config/nvim` is never touched.
- opencode: `OPENCODE_CONFIG_DIR=$AID_DIR/opencode` — config reads from inside the repo, not `~/.config/opencode/`
- install.sh: does not inject into any user config file; `aid` is symlinked into `~/.local/bin/aid` — the only mutation to the user's environment
- All scripts (`ensure_treemux.sh`, `sync.lua`): use `tmux -L aid` for every tmux command

**Reason**: The previous model (symlink `~/.config/nvim → aid/nvim/`, source `aid/tmux.conf` from user's tmux config) overwrote the user's nvim config and polluted their tmux config. A new machine install of aid should be truly zero-conflict — users who already have an nvim config or complex tmux config must be able to install and run aid without any breakage to their existing environment.

**Supersedes**: ADR-003, ADR-004 (see `archive/DECISIONS-2026-03.md`).

---

### ADR-007: OPTIONS block must be at the top of `init.lua`

**Date**: 2026-03
**Decision**: The `vim.opt.*` global options block (line numbers, sign column, tab settings, etc.) is placed at the very top of `init.lua` — immediately after leader key and netrw disable — before any `require()`, plugin setup, or `vim.api.nvim_create_autocmd()` call.

**Reason**: Neovim evaluates `init.lua` top-to-bottom. Autocmds registered with `vim.api.nvim_create_autocmd` capture a reference to the option at registration time only if they read it directly. More subtly: window-local option inheritance (`setlocal x<`) falls back to the *global* option (`vim.o.x`) at the moment the `setlocal x<` command executes — not to the value that will be set later in the file.

The cheatsheet dismiss autocmd uses:
```lua
vim.cmd("setlocal number relativenumber& signcolumn=yes ...")
```
The `&` suffix on `relativenumber` means "inherit global". If `vim.opt.relativenumber = false` has not yet been set when this executes, Neovim's built-in default (`false`) happens to match — but `vim.opt.number = true` must be set before any autocmd that reads or resets `number` can see the intended value.

Placing the OPTIONS block last (or after `lazy.setup()`) meant that:
1. `VimEnter` fired before `vim.opt.number = true` was reached.
2. The cheatsheet's window-local `number = false` override was applied.
3. When the cheatsheet was dismissed via `setlocal number ...`, the global `vim.o.number` was still `false` (Neovim's built-in default), so line numbers did not appear on the restored file buffer.

**Rule**: Any option that an autocmd or plugin `config` function needs to read must be set before that code runs. The safest position is immediately after `mapleader` and netrw disable — before all `require()` calls.

---

### ADR-008: `.aidignore` live reload via `explorer.filters.ignore_list` mutation

**Date**: 2026-03
**Decision**: Live-updating nvim-tree filters when `.aidignore` changes is done by mutating `require("nvim-tree.core").get_explorer().filters.ignore_list` in-place, then calling `api.tree.reload()`. No `setup()` re-call.

**Reason**: `nvim-tree.setup()` is not safe to call on a live tree — it calls `purge_all_state()` internally, which destroys the window/explorer (visible as a blank pane). The `ignore_list` field is a `table<string, boolean>` read on every `should_filter()` invocation inside nvim-tree's render loop. Mutating it in-place causes the next `reload()` to use the updated patterns with zero visual disruption — no window close/reopen, cursor preserved.

**Stability evidence**: `ignore_list` has existed under this exact name since nvim-tree's multi-instance refactor (PR #2841), with 33 commits to `filters.lua` since then — name unchanged. If the field is renamed in a future nvim-tree update, the code silently skips the mutation (guarded by `if explorer and explorer.filters and explorer.filters.ignore_list`).

**S2 fallback**: documented in `aidignore.lua:99–103`. If `ignore_list` is ever removed, fall back to `tmux kill-pane <sidebar_pane_id>` + re-run `ensure_treemux.sh` to reopen the sidebar fresh. ~0.5s visual glitch but uses only public APIs. (Note: this fallback is obsolete if ADR-013 resolves to removing treemux.)

**Alternatives rejected**:
- `setup()` re-call: destroys the live explorer (tested, reverted).
- Restart sidebar nvim entirely on every `.aidignore` change: too disruptive (~0.5s blank + state loss).

---

### ADR-009: Shared `package.path` for sidebar nvim via `AID_DIR/nvim/lua`

**Date**: 2026-03
**Decision**: `treemux_init.lua` prepends `AID_DIR/nvim/lua` to `package.path` at the top of the file, before any `require()`. This allows `require("aidignore")` (and other main-nvim modules) to work in the sidebar nvim without duplicating code.

**Reason**: The sidebar nvim (`NVIM_APPNAME=treemux`) is an isolated process with its own config directory. Shared Lua modules like `aidignore.lua` live in `nvim/lua/` under the main nvim config. Without the `package.path` addition, `require("aidignore")` in `treemux_init.lua` fails with `module not found`.

**Why `package.path` and not `rtp`**: `vim.opt.rtp:prepend(dir)` expects `dir` to be a directory that *contains* a `lua/` subdirectory (nvim's module resolution convention). `AID_DIR/nvim/lua` is the `lua/` dir itself — prepending it to `rtp` would make nvim look for `AID_DIR/nvim/lua/lua/aidignore.lua`, which doesn't exist. `package.path` is the correct mechanism for adding a plain directory of `.lua` files.

**Why not duplicate the file**: duplicating `aidignore.lua` into `nvim-treemux/` would create a maintenance burden — two copies of the same ignore-list logic, filter-application logic, and S2 fallback documentation would need to stay in sync.

**Note**: obsolete if ADR-013 resolves to removing treemux; kept for historical record until that decision is made.

---

### ADR-010: `tmux.conf` default keybinds

**Date**: 2026-03
**Decision**: `aid/tmux.conf` ships two categories of keybinds beyond the essential (reload, sidebar toggle, mouse):

1. **Pane navigation** (`M-Left/Right/Up/Down`, `C-h/j/k/l`, no prefix) — shipped as defaults.
2. **Pane management** (`M-v` split-h, `M-h` split-v, `M-q` kill-pane, `M-S-q` detach) — shipped as defaults, commented as opinionated.

The navigation binds (`C-h/j/k/l`) are functionally integrated with aid's nvim config via `tmux.nvim`, which intercepts them inside nvim and passes them to tmux when there is no nvim split in that direction. They cannot be omitted without breaking cross-pane navigation for the expected three-pane layout. The management binds are validated for aid's workflow but carry a note that users should remove or rebind if they conflict with their terminal emulator.

**Reason**: aid's tmux server is isolated — its config is the *only* config loaded; the user's personal `~/.config/tmux/.tmux.conf` is never sourced. Shipping no navigation binds would leave users unable to move between panes without mouse or the verbose `<prefix><arrow>`. The chosen binds have been validated against aid's three-pane layout over sustained daily use. Splitting, kill-pane, and detach are common enough to be useful defaults; they are clearly labelled so users know they can replace them.

---

### ADR-011: `XDG_CONFIG_HOME=~/.config/aid` for centralised nvim config

**Date**: 2026-03
**Decision**: `aid.sh` sets `XDG_CONFIG_HOME=$HOME/.config/aid` in the tmux server environment. Combined with `NVIM_APPNAME=nvim` (main editor) and `NVIM_APPNAME=treemux` (sidebar), nvim resolves config paths to `~/.config/aid/nvim` and `~/.config/aid/treemux`. Both are symlinks into the repo created by `install.sh`. The user's `~/.config/nvim` is never touched.

**Reason**: `NVIM_APPNAME` alone can only be a single path component — it cannot produce nested paths like `~/.config/aid/nvim`. The only way to get everything under a single `~/.config/aid/` root is to redirect `XDG_CONFIG_HOME`. Setting it in the tmux server environment (via `tmux set-environment -g`) means every process spawned inside an aid session inherits it automatically — including nvim invocations from shell prompts, not just the respawn-pane loop.

**Scope of `XDG_CONFIG_HOME` override**: The override is scoped to the aid tmux server process tree. It does not affect the user's login shell or any process outside an aid session. Subprocesses launched by nvim (LSP servers, formatters, shell commands via `!`) will also inherit the override, which is intentional — they should resolve config relative to the aid environment. The only known footgun is a tool that reads `XDG_CONFIG_HOME` to write user-global state (e.g. a tool that stores usage history there). Such tools are rare; document if one is found.

**Alternatives rejected**:
- `NVIM_APPNAME=aid` + `NVIM_APPNAME=aid-treemux`: gives `~/.config/aid` (main) but `~/.config/aid-treemux` (sidebar) — not truly nested.
- Pass `--cmd "set rtp+=..."` to nvim directly: requires rebuilding nvim's entire runtimepath resolution, fragile across nvim versions.

---

### ADR-012: User nvim and tmux config in `~/.config/aid` — intentionally separate from system config

**Date**: 2026-03
**Decision**: Users who want to customise nvim or tmux behaviour within aid must edit files under `~/.config/aid/` (which are symlinks back into the repo). There is no mechanism to layer a user's existing `~/.config/nvim` or `~/.config/tmux/.tmux.conf` into aid's environment.

**Reason**: The scope of safely merging arbitrary user nvim configs (plugins, autocmds, LSP setups, colorschemes) or tmux configs (key bindings, plugins, hooks) with aid's own config without breaking aid's functionality is large and undefined. Aid's nvim config depends on specific plugin load order, specific keybinds, and specific autocmds. A user's config could silently override any of these. Until aid has a defined extension/override API, the correct default is full isolation. Users are informed of this tradeoff in the README.

**Under consideration**: A structured override layer — e.g. a `~/.config/aid/nvim/lua/user.lua` that is `require()`d last in `init.lua`, giving users a safe insertion point. Not implemented yet; tracked in ROADMAP.md as T-019.

---

## Superseded

ADRs in this section were previously made but overridden by a later decision. Kept for historical record.

---

### ADR-003, ADR-004: Earlier isolation model

Superseded by ADR-006. Full text in `archive/DECISIONS-2026-03.md`.
