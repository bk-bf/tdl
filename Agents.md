<!-- LOC cap: 344 (source: 2457, ratio: 0.14, updated: 2026-03-09) -->
# Agents.md — AI coding agent reference for aid

## Agent rules

- **Never commit or push to git unprompted.** Always wait for the user to explicitly ask, or for a slash command (e.g. `/commit`) to trigger it. This applies even when completing a large task — finish all code changes, then stop and wait. The user may have staged changes of their own that must not be conflated into your commit.
- **Roadmap task references**: open tasks in `docs/features/open/ROADMAP.md` are numbered `T-NNN` (e.g. `T-002`). When referencing a roadmap item in code comments, ADRs, bug notes, or commit messages, use the task number, not a description.
- **Date format**: always use `YYYY-MM-DD` (e.g. `2026-03-09`). Never use `YYYY-MM` alone. This applies everywhere: ADR `**Date**` fields, bug report `**First appeared**` / `**Fixed**` fields, roadmap `## Done` entries (`- [x] **YYYY-MM-DD**: ...`), LOC cap `updated:` comments, and archive filenames (`BUGS-YYYY-MM-DD.md`, `DECISIONS-YYYY-MM-DD.md`).
- **Archiving completed items**: never move completed roadmap items, closed bugs, or superseded ADRs to `docs/features/archive/` unless the user explicitly asks. Completed items stay in their current file until the user requests archiving.
- **One branch at a time**: only make changes to the branch the user specifies. Never edit files in two code branches (e.g. `main/` and a `feature/` worktree) in the same session without first asking the user. The `docs/` worktree (`dev-docs` branch) is always fair game alongside whichever code branch is active — it is not a "second code branch".
- **No architecture content in this file.** This file is orientation only. All architecture detail lives in `docs/` — see the reference section at the bottom. Do not add environment variables, pane layouts, plugin lists, isolation mechanisms, symlink maps, or boot/session sequences here. If you find yourself writing that kind of content, put it in `docs/ARCHITECTURE.md` instead.

## What this repo is

aid is an open-source, terminal-native AI IDE: tmux workspace orchestration + nvim config + persistent Opencode AI pane, all in one repo.

Three persistent panes: file-tree sidebar (left), nvim editor + shell (middle), Opencode AI assistant (right). A single `boot.sh` curl gives a fully working IDE on any machine. No dotfiles repo required.

**Identity**: not a Neovim distribution (like LazyVim) — a *workspace environment* that orchestrates multiple nvim instances and tmux panes. LazyVim configures an editor; aid builds a workspace around one.

## Repo layout

```
aid/                            ← bare git repo root
├── main/                       ← master branch worktree (all code lives here)
│   ├── boot.sh                 # curl bootstrapper — clones repo then runs install.sh
│   ├── install.sh              # one-shot setup: TPM, treemux, symlinks, headless nvim bootstrap
│   ├── aid.sh                  # main entry point — symlinked to ~/.local/bin/aid by install.sh
│   ├── tmux.conf               # loaded via -f on the dedicated tmux server socket
│   ├── ensure_treemux.sh       # idempotent sidebar opener; enforces 3-pane layout proportions
│   ├── .aidignore              # patterns hidden from nvim-tree and Telescope (parsed by aid.sh at launch)
│   ├── nvim/
│   │   ├── init.lua            # main nvim config (plugins, LSP, keymaps, options, autocmds)
│   │   ├── cheatsheet.md       # styled welcome buffer — opens on fresh aid launch, <leader>?
│   │   ├── lazy-lock.json      # plugin lockfile
│   │   └── lua/
│   │       ├── sync.lua        # central git-sync coordinator (see below)
│   │       └── aidignore.lua   # reads AID_IGNORE env var, returns patterns for nvim-tree + Telescope
│   ├── nvim-treemux/
│   │   ├── treemux_init.lua    # isolated nvim config for sidebar (NVIM_APPNAME=treemux)
│   │   └── watch_and_update.sh # custom fork — cd-follows root on any cd, not just exit
│   ├── opencode/
│   │   └── commands/           # custom slash commands (commit.md, udoc.md)
│   ├── README.md
│   └── Agents.md
└── docs/                       ← dev-docs branch worktree (orphan, never merge into master)
    ├── ARCHITECTURE.md
    ├── DECISIONS.md
    ├── PHILOSOPHY.md
    ├── bugs/
    │   └── BUGS.md
    └── features/
        ├── open/
        │   └── ROADMAP.md      # open tasks (T-NNN), deferred items, phase plan
        └── archive/
            └── ROADMAP-*.md    # completed items moved here by /udoc
```

## btca — documentation assistant

btca is a self-hosted AI tool that answers questions about specific codebases or documentation sets. Use it when you need accurate, up-to-date information about any of the indexed resources below — do not rely on training-data knowledge for these, as it may be stale or wrong.

**When to use it:** any question about tmux options/commands, Neovim Lua API, lazy.nvim plugin spec, opencode internals/config, nvim-tree API, or lualine config.

**How to invoke:**
- Slash command: `/btca <resource> <question>` (e.g. `/btca neovim vim.keymap.set signature`)
- MCP tool: call `ask` with `resource` and `question` parameters (the `listResources` tool returns the current list)

**Indexed resources:**

| Name | Source | Notes |
|---|---|---|
| `tmux` | github.com/tmux/tmux (master) | Full source tree — check `CHANGES`, man pages, and `.c` source |
| `neovim` | github.com/neovim/neovim (master, `runtime/doc`) | Vimdoc files for the full Neovim Lua API |
| `lazy-nvim` | github.com/folke/lazy.nvim (main) | README + source — plugin spec, config, lazy-loading |
| `opencode` | github.com/sst/opencode (dev) | Full source — internals, config schema, MCP, slash commands |
| `nvim-tree` | github.com/nvim-tree/nvim-tree.lua (master) | README + doc/ — API, config options, events |
| `lualine` | github.com/nvim-lualine/lualine.nvim (master) | README + doc/ — sections, components, themes |

**Always dispatch btca queries as a subagent** — never block the main thread waiting for a response. Spawn a subagent, let it run the query and return the answer, then continue.

## Documentation

All architecture detail lives in the `docs/` worktree (`dev-docs` branch). Start here:

| File | Contents |
|---|---|
| `docs/ARCHITECTURE.md` | Environment isolation, boot sequence, pane layout, env vars, sync.lua, aidignore, hot-reload, plugin lists |
| `docs/features/open/ROADMAP.md` | Open tasks (`T-NNN`), deferred items, and the bug cross-reference index |
| `docs/features/archive/ROADMAP-*.md` | Completed roadmap items archived by `/udoc` |
| `docs/DECISIONS.md` | Architecture Decision Records (ADR-001 … ADR-NNN) |
| `docs/PHILOSOPHY.md` | Design principles, seam rule, target user profile, scope constraints |
| `docs/bugs/BUGS.md` | All bug reports and their status |
