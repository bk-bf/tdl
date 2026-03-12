# Orchestrator mode

## Overview

Orchestrator mode (`aid --mode orchestrator`) is a multi-session layout for running many opencode conversations in parallel, each in its own isolated tmux session, all navigable from a single persistent sidebar.

It replaces the standard aid layout (sidebar + nvim + opencode in one session) with a T3/Codex-style workspace:

```
┌─────────────────────┬────────────────────────────────────────┐
│  aid@aid  sessions  │                                        │
│                     │           opencode TUI                 │
│ ❯ aid          live │                                        │
│  ├─ ● Conv title    │                                        │
│  └─ ○ Other conv    │                                        │
│                     │                                        │
├─────────────────────┴────────────────────────────────────────┤
│  debug log pane  (only with -d / AID_DEBUG=1)                │
└──────────────────────────────────────────────────────────────┘
```

Each `aid@<name>` tmux session contains:
- **Left pane** (~25%): `aid-sessions.ts` — the TypeScript/Bun navigator
- **Right pane** (~75%): `opencode` — the AI TUI
- **Bottom pane** (full width, debug mode only): `aid-sessions-debug` — live log viewer

## Entry point

```
aid --mode orchestrator                      launch / attach
aid -d --mode orchestrator                   same, with debug pane + log
aid --branch <b> --mode orchestrator         run from a feature branch install
```

`aid.sh` consumes `--mode` in its pre-pass and dispatches to
`lib/orchestrator.sh` via `exec`. All `AID_*` vars are exported before the
exec so `orchestrator.sh` inherits the same environment.

## Boot sequence

```
aid.sh --mode orchestrator
  └── exec lib/orchestrator.sh
        ├── _ensure_server          — start tmux -L aid server if not running
        ├── check for existing orchestrator sessions (@aid_mode=orchestrator)
        │     none found → _new_session_from_cwd
        │     found      → _attach_or_switch to most recently used
        └── _new_session_from_cwd / spawn_orc_session
              ├── tmux new-session -d -s aid@<name>
              ├── set-environment: AID_ORC_PORT, AID_ORC_NAME, AID_ORC_REPO,
              │                    AID_NVIM_SOCKET, AID_ORC_NAV_PANE, AID_ORC_ORC_PANE
              ├── [debug] split bottom 25% → dbg_pane (sleep infinity placeholder)
              ├── split right 75% → orc_pane (sleep infinity placeholder)
              ├── respawn orc_pane  → opencode --port <AID_ORC_PORT> <repo_path>
              ├── respawn nav_pane  → aid-sessions.ts
              ├── [debug] respawn dbg_pane → aid-sessions-debug
              ├── set-option @aid_mode orchestrator  (for session discovery)
              ├── _meta_write <name> <repo_path>     (persist to sessions.json)
              ├── set-hook pane-focus-in → aid-meta-touch (last_active timestamp)
              └── _attach_or_switch aid@<name>
```

### Session naming

Session name: `aid@<sanitised-basename-of-repo>`. Numeric suffix appended if
the name already exists (`aid@project`, `aid@project2`, …).

### `_attach_or_switch`

Uses `switch-client -c "$AID_CALLER_CLIENT" -t "$target"` when `TMUX` is set
and `AID_CALLER_CLIENT` is available — so the correct terminal is switched even
when called from a pane subprocess (e.g. the `n` key in `aid-sessions`).
Falls back to plain `switch-client -t` when the var is absent, and
`tmux attach` when not inside tmux at all.

`AID_CALLER_CLIENT` is resolved once by `aid-sessions.ts` at startup (from
`#{client_tty}` of the nav pane, or `tty(1)` as fallback) and exported so all
subprocesses inherit it.

### Opencode isolation

Each session's opencode instance is started with:
```
XDG_DATA_HOME=<AID_DATA>           — per-branch conversation store
OPENCODE_CONFIG_DIR=<AID_DIR>/opencode
OPENCODE_TUI_CONFIG=<AID_DIR>/opencode/tui.json
opencode --port <AID_ORC_PORT> <repo_path>
```

`XDG_DATA_HOME` is injected **inline** on the `respawn-pane` command (not just
as a global tmux env var) because `respawn-pane` inline commands do not inherit
the global tmux environment. Without it, opencode falls back to
`~/.local/share/opencode` and serves the user's entire cross-project history.

`AID_ORC_PORT` is a deterministic port derived from the session name:
`4200 + (cksum(name) % 1000)` — stable across restarts.

## Session metadata (`aid-meta`)

Session records are stored in `$AID_DATA/sessions.json` as a JSON array.
Dead sessions (tmux gone, metadata present) are shown in the navigator and
can be resurrected.

### Schema

```json
{
  "tmux_session": "aid@project",
  "repo_path":    "/home/user/project",
  "branch":       "main",
  "created_at":   "2026-03-11T22:00:00Z",
  "last_active":  "2026-03-12T00:01:00Z"
}
```

### API (sourced by `orchestrator.sh`)

| Function | Purpose |
|---|---|
| `_meta_write <name> <repo>` | Upsert entry; preserves `created_at` from existing record |
| `_meta_touch <session>` | Update `last_active` timestamp (called by `pane-focus-in` hook via `aid-meta-touch`) |
| `_meta_remove <session>` | Delete entry by session name |
| `_meta_get <session> <field>` | Read one field; returns `""` when missing or jq absent |
| `_meta_all_sessions` | Print all `tmux_session` values, one per line |

All functions degrade gracefully when `jq` is absent (return 0, print nothing).

### Dead session prune

At `aid-sessions.ts` startup, `pruneDead()` removes entries from
`sessions.json` for sessions that no longer exist in tmux. Runs once in the
background so it does not delay the initial render.

## `aid-sessions.ts` — the navigator

`lib/sessions/aid-sessions.ts` is a self-contained Bun/TypeScript process that
owns the entire left pane. It renders directly to the terminal via ANSI escape
codes (alternate screen buffer, absolute cursor positioning), handles raw key
input, and calls the opencode HTTP API and tmux directly via `Bun.spawn` /
`fetch`.

There is no fzf dependency. The navigator is a persistent process for the
lifetime of the tmux session.

### Rendering

- **Alternate screen buffer** — no scrollback leak; `\x1b[?1049h` on start,
  `\x1b[?1049l` on exit.
- **Absolute cursor positioning** — every render clears the screen and redraws
  all lines via `\x1b[row;1H`. No `\n` is ever written (prevents scrollback
  accumulation).
- **`clampLine(s, cols)`** — hard-clamps every rendered line to the pane width
  by walking rune-by-rune and skipping ANSI escape sequences (zero-width).
  Nothing ever wraps regardless of terminal size.
- **Colors** — loaded at runtime from `nvim/lua/palette.lua` via `loadPalette()`
  (regex parses `M.key = "#rrggbb"` lines). No color values are hardcoded in
  the navigator itself.

### Visual structure

```
 aid@aid          sessions    ← title bar (row 1): blue bg, full-width
❯ aid          live           ← session header: purple caret when current
 ├─ ● Conv title    2m ago    ← active conv: purple ●, bold white title
 └─ ○ Other conv    5m ago    ← inactive conv: dim gray ○
```

- **Selection**: purple `▌` left-edge bar + very subtle bg tint. The bar is the
  primary cursor signal so bold/color on the row text is never obscured.
- **`●`/`○` markers**: purple filled = currently active in opencode; dim gray
  hollow = inactive.
- **Timestamps**: dim gray, right-aligned. Dropped gracefully when the pane is
  too narrow.
- **Tree lines** (`├─`/`└─`): lavender, connecting conv rows to their session.

### Sync strategy

Two-tier approach to keep the UI responsive:

| Tier | Trigger | What it does | Latency |
|---|---|---|---|
| **Optimistic patch** | Immediately on action | Mutates `state.items` in-place and calls `render()` | ~0ms |
| **Fast active sync** (`refreshActiveConvs`) | Every cursor move (↑↓jk, page) | Re-queries `AID_ORC_ACTIVE_CONV` from tmux env per session, patches `active` flags | ~1 tmux RTT per session |
| **Full refresh** (`refresh`) | After actions that change the list; 5s interval safety net | Rebuilds entire item list from tmux + opencode HTTP | ~1–2 full RTTs |

Optimistic patches are applied for:
- **Conv switch** (`Enter`): `active` flags flipped instantly before any tmux/HTTP calls.
- **Delete** (`dy`): item removed from list instantly; stranded `sep` rows cleaned up.
- **Rename** (`r`): title patched in-place instantly; reverts to full refresh (which re-reads from server) on HTTP failure.
- **New conversation** (`n`): `new conversation…` placeholder inserted at top of session group instantly; replaced with real item after HTTP POST returns.

### Keys

| Key | Action |
|---|---|
| `↑` / `k` | Move cursor up |
| `↓` / `j` | Move cursor down |
| `PgUp` / `PgDn` | Move cursor ±10 rows |
| `Enter` | Conv row: load conversation. Session header: no-op (already current). Dead session: resurrect. |
| `n` | New conversation in current session |
| `r` | Inline rename (conv title or session name) |
| `d` | Inline delete with `y`/`n` confirm |
| `Ctrl-R` | Force full refresh |
| `q` / `Esc` / `Ctrl-C` | Quit |

### Conversation loading

```
loadConversation(convId, session)
  1. Optimistically patch active flags in state.items → render()
  2. orcPort(session)  — tmux show-environment AID_ORC_PORT
  3. tmux set-environment AID_ORC_ACTIVE_CONV=<convId>
  4. POST /tui/select-session {"sessionID":"<convId>"}  → opencode switches TUI
  5. if current session ≠ target: switch-client -c $AID_CALLER_CLIENT -t target
```

### Rename

Inline input field replaces the cursor row. `Enter` confirms, `Esc` cancels.

```
Conv rename:
  1. Patch title in state.items → render()  (optimistic)
  2. GET orcPort → PATCH /session/<convId> {"title":"<new>"}
  3. On failure: setStatus("rename failed") + full refresh

Session rename:
  1. tmux has-session check (bail if new name already exists)
  2. tmux rename-session old new
  3. writeMeta (update sessions.json)
  4. full refresh
```

### Delete

```
Conv delete (dy):
  1. Remove item from state.items, clamp cursor → render()  (optimistic)
  2. DELETE /session/<convId>
  3. full refresh

Session delete (dy):
  1. Remove session + all its convs from state.items → render()  (optimistic)
  2. GET /session → DELETE each conv
  3. full refresh

Dead session delete (dy):
  1. Remove item → render()  (optimistic)
  2. writeMeta (remove from sessions.json)
  3. full refresh
```

### Auto-refresh

```
boot()
  └── early-retry loop: polls every 500ms for 3s if 0 convs (opencode not ready yet)
  └── setInterval(refresh, 5000)  — safety-net full refresh every 5s (nav mode only)
```

The 5s interval is skipped while in `rename` or `delete-confirm` mode to avoid
interrupting user input.

## `aid-sessions-debug` — log viewer

Runs in the bottom pane when `AID_DEBUG=1`. Tails `AID_DEBUG_LOG` and renders
each event with colour-coded category labels and a `+Δms` delta column.

### Debug log format

```
<unix_ms> <CATEGORY> <message>
```

| Category | Meaning |
|---|---|
| `INIT` | Startup events |
| `SPAWN` | Pane lifecycle steps from `orchestrator.sh` |
| `SYNC` | Full refresh start/done |
| `KEY` | Raw key bytes received |
| `ACTN` | Higher-level action (new conv, resurrect) |
| `CONV` | Conversation load request |
| `RENAME` | Rename operation |
| `DEL` | Delete operation |
| `PRUNE` | Dead session metadata cleanup |
| `ERR` | Any error |

## Environment variables

### Session-local (set per `aid@<name>` session by `orchestrator.sh`)

| Variable | Value | Purpose |
|---|---|---|
| `AID_ORC_PORT` | `4200 + cksum(name) % 1000` | Opencode HTTP API port; stable across restarts |
| `AID_ORC_NAME` | `<name>` | Session short name (without `aid@` prefix) |
| `AID_ORC_REPO` | `<repo_path>` | Absolute path to the session's repo |
| `AID_ORC_NAV_PANE` | `%<id>` | Pane ID of the navigator (left pane) |
| `AID_ORC_ORC_PANE` | `%<id>` | Pane ID of the opencode TUI (right pane) |
| `AID_ORC_ACTIVE_CONV` | opencode session ID | Currently loaded conversation (best-effort) |
| `AID_NVIM_SOCKET` | `/tmp/aid-nvim-<session>.sock` | Unused in orchestrator mode (no nvim pane) |
| `AID_DEBUG_LOG` | `<repo>/log-<timestamp>.txt` | Debug log path (only when `AID_DEBUG=1`) |

### Per-process

| Variable | Set by | Purpose |
|---|---|---|
| `AID_CALLER_CLIENT` | `aid-sessions.ts` startup | tty of the terminal that launched aid; passed to `switch-client -c` so switches target the right screen |

## Key design decisions

- **TypeScript/Bun rewrite of bash+fzf**: the navigator is a single
  self-contained process with its own render loop, raw key handling, and HTTP
  client. No fzf dependency, no subprocess-per-keypress, no IPC pipes between
  the navigator and a background ticker.

- **Optimistic UI updates**: all mutations (switch, delete, rename, new conv)
  patch `state.items` and call `render()` synchronously before any async I/O.
  The subsequent HTTP/tmux call reconciles with a full `refresh()`. This makes
  every action feel instant regardless of network/tmux latency.

- **`clampLine` instead of terminal width truncation**: every rendered line is
  clamped in-process to `process.stdout.columns` visible characters. Prevents
  wrapping in narrow panes without relying on `stty cols` or terminal
  capabilities.

- **Palette loaded at runtime**: `loadPalette()` reads `nvim/lua/palette.lua`
  once at startup. No color values are duplicated between the navigator and the
  nvim theme — palette.lua is the single source of truth.

- **Deterministic opencode port**: `4200 + cksum(name) % 1000` — no port
  scanning, no dynamic discovery, stable across session restart. The navigator
  knows the port before opencode has started.

- **`XDG_DATA_HOME` inline on `respawn-pane`**: prevents opencode from serving
  the user's global `~/.local/share/opencode` history. Must be inline because
  `respawn-pane` commands do not inherit global tmux env vars.

- **`@aid_mode=orchestrator` session tag**: set on each session at spawn time
  so `orchestrator.sh` can list and attach to orchestrator sessions without
  interfering with plain aid sessions that might share the same tmux server.
