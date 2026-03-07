# Decisions

Architecture decision records — why things are the way they are.

---

## ADR-001: Install path `~/.local/share/aid`

**Date**: 2026-03
**Decision**: Default install to `~/.local/share/aid`, override with `TDL_DIR`.
**Reason**: XDG Base Directory spec — `~/.local/share` is the correct location for user-installed application data (scripts, plugins, runtime files). Previous default `~/Documents/Projects/special_projects/tdl` was personal/idiosyncratic.

---

## ADR-002: Orphan `dev-docs` branch for private documentation

**Date**: 2026-03
**Decision**: Keep architecture, roadmap, bugs, and decisions in an orphan `dev-docs` branch with a git worktree at `aid/docs/`. Never merge into `master` or any code branch.
**Reason**: Documentation must be markdown + version-controlled for LLM-driven workflow, but should not be cloned by users running `boot.sh`. A separate private repo adds context-switching overhead; an orphan branch with a worktree gives file-system access without contaminating the public install.

---

## ADR-003: Sourced vs symlinked integration *(superseded by ADR-006)*

**Date**: 2026-03
**Decision**: `aliases.sh` and `tmux.conf` are sourced from user config files. nvim config and treemux scripts are symlinked.
**Reason**: Source lines in user config are visible, annotated, and easy to remove. Symlinks for nvim and nvim-treemux allow `install.sh` re-runs to transparently update files without modifying any user-owned config.
**Superseded**: ADR-006 eliminates the `tmux.conf` source injection entirely and changes the nvim symlink target from `~/.config/nvim` to `~/.config/nvim-tdl`.

---

## ADR-004: nvim config lives in aid repo *(superseded by ADR-006)*

**Date**: 2026-03
**Decision**: Move `~/.config/nvim/` into `aid/nvim/` and symlink `~/.config/nvim → aid/nvim/`. Remove from dotfiles repo (bk-bf/.config).
**Reason**: aid is an IDE distribution — the nvim config is tightly coupled to the workspace (lazygit worktree fix, treemux keybinds, opencode integration). Co-locating it in aid makes the full IDE reproducible from a single `boot.sh` curl — no separate dotfiles clone required on a fresh machine.
**Superseded**: ADR-006 changes the symlink target from `~/.config/nvim` to `~/.config/nvim-tdl` (via `NVIM_APPNAME=nvim-tdl`) so the user's existing `~/.config/nvim` is not overwritten.

---

## ADR-005: `--git-dir` not `--git-common-dir` for lazygit worktree detection

**Date**: 2026-03
**Decision**: The `<leader>gg` keybind uses `git rev-parse --git-dir` to resolve `GIT_DIR`, not `--git-common-dir`.
**Reason**: `--git-common-dir` returns the bare repo root (e.g. `aid/`). When set as `GIT_DIR` with `GIT_WORK_TREE=aid/main/`, git treats the bare root as the work-tree and sees all committed files as deleted + all files in `main/` as untracked. `--git-dir` returns the worktree-specific path (e.g. `aid/worktrees/main`) which correctly scopes the index to the checked-out branch, giving lazygit a clean view.

---

## ADR-006: Full environment isolation

**Date**: 2026-03
**Decision**: aid must not conflict with the user's existing nvim or tmux setup. All runtime state is isolated:
- tmux: dedicated server socket `tmux -L tdl -f <TDL_DIR>/tmux.conf` — `-f` suppresses all user tmux configs
- nvim: `NVIM_APPNAME=nvim-tdl` — config at `~/.config/nvim-tdl → aid/nvim/`; `~/.config/nvim` is never touched
- install.sh: no longer injects into `~/.config/tmux/.tmux.conf`; only injects `source <TDL_DIR>/aliases.sh` into `~/.config/.aliases`
- All scripts (`ensure_treemux.sh`, `sync.lua`): use `tmux -L tdl` for every tmux command

**Reason**: The previous model (symlink `~/.config/nvim → aid/nvim/`, source `aid/tmux.conf` from user's tmux config) overwrote the user's nvim config and polluted their tmux config. A new machine install of aid should be truly zero-conflict — users who already have an nvim config or complex tmux config must be able to install and run aid without any breakage to their existing environment.

**Supersedes**: ADR-003 (tmux.conf injection removed), ADR-004 (nvim symlink target changed to `~/.config/nvim-tdl`).

---

## ADR-007: OPTIONS block must be at the top of `init.lua`

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
