# `aid --mode orchestrator` — Feature Breakdown & Analysis Report

---

## Executive Summary

`aid --mode orchestrator` is a tmux-native solo orchestration layout for the `aid` CLI that replicates the T3/Codex parallel workflow in a terminal-native environment. Unlike `aid --fleet` (which fans out decomposed sub-tasks to parallel agents in isolated worktrees), the orchestrator mode is designed around a **human operator** who runs multiple live opencode sessions simultaneously — one per project context — and switches between them with full spatial continuity. All sessions stay alive in the background; the operator moves focus, not the agents.

---

## The Core Premise: Sessions as First-Class Objects

In `aid --fleet`, opencode instances are ephemeral workers — spawned for a task, merged, discarded. In `aid --mode orchestrator`, each opencode session is a **persistent, named, project-scoped environment** that maps 1:1 to a tmux session. The operator accumulates sessions over time (one per project, one per feature branch, one per experiment) and the layout makes all of them navigable from a single keybind.

This is the T3/Codex workflow: parallel context windows, each fully live, with a session picker overlay to move between them.

---

## The Three-Pane Layout

```
┌─────────────────────────────────────────────┬──────────────────────┐
│                                             │                      │
│               opencode                      │      lazygit         │
│           (active session)                  │    (diff review)     │
│                                             │                      │
│              ~75% width                     │     ~25% width       │
│                                             │                      │
└─────────────────────────────────────────────┴──────────────────────┘
  [tmux tab: nvim]  ← separate tmux window, switch with prefix+n

  prefix+s  →  session navigator popup overlay (see below)
```

### Pane Responsibilities

| Pane | Content | Width |
| :-- | :-- | :-- |
| **Main** | Active opencode session | ~75% |
| **Right** | lazygit, rooted to the active session's repo | ~25% |
| **Tab: nvim** | Neovim + treemux sidebar, rooted to the repo | full |
| **prefix+s** | Session navigator popup — all aid sessions + opencode conversations | overlay |

---

## Session Model: One tmux Session Per Project

Each project launched under `aid --mode orchestrator` gets its own **tmux session** named:

```
aid@<name>
```

where `<name>` is the sanitised basename of the repo directory (same derivation as regular `aid` sessions). A numeric suffix is appended for collisions: `aid@my-project`, `aid@my-project2`.

Sessions are tagged with `@aid_mode=orchestrator` at creation so they can be distinguished from plain `aid` sessions sharing the same tmux server.

### What lives inside each `aid@<name>` session

- **Window 0**: opencode (main pane, ~75%) + lazygit (right, ~25%)
- **Window 1 (`nvim`)**: full-width nvim + treemux sidebar
- **Session env vars**: `AID_ORC_NAME`, `AID_ORC_REPO`, `AID_ORC_PORT` (opencode HTTP port)

### opencode HTTP server

Each opencode instance is started with a **fixed, deterministic port**:

```
port = 4200 + (cksum(name) % 1000)
```

This port is stored in `AID_ORC_PORT` in the tmux session environment and used by the navigator to communicate with that session's opencode instance via its HTTP API.

---

## The Session Navigator: prefix+s Popup

The navigator is a **tmux popup overlay** bound to `prefix+s`. It opens on top of any session, lets the operator pick a session or conversation, then closes. No persistent left pane — the popup approach is simpler, more reliable, and avoids all `switch-client` visibility problems.

### What the navigator shows

```
aid@my-project  [live]  /home/user/my-project  (feature/auth)
  > Fix auth token refresh bug          3m ago   ← active conversation
    Refactor db schema                  1h ago

aid@other-proj  [live]  /home/user/other
    Initial setup                       2d ago

aid@old-work    [dead]                  5d ago
```

- **Session headers** (`aid@<name>`) — selectable: switches tmux client to that session
- **Conversations** — opencode conversations from that session's HTTP API, grouped under their session, sorted by last updated. Selecting one calls `POST /tui/select-session` on that session's opencode port — instant, no restart.
- **Dead sessions** — sessions in metadata but not in tmux. Selectable: resurrects the layout.

### Navigation keys

| Key | Action |
| :-- | :-- |
| `Enter` | Switch to session / load conversation |
| `n` | New session (auto-named from cwd basename) |
| `d` | Delete session with confirmation |
| `r` | Rename session |
| `z` | Toggle collapse/expand session group |
| `ctrl-r` | Refresh list |
| `q` / `esc` | Close navigator |

---

## opencode HTTP API Integration

opencode exposes a full HTTP API when running with `--port`. This is the correct integration point — not DB queries, not tmux send-keys, not process restarts.

### Key endpoints used by the navigator

| Method | Endpoint | Purpose |
| :-- | :-- | :-- |
| `GET` | `/session` | List all conversations for this opencode instance |
| `POST` | `/tui/select-session` | Switch the running TUI to a specific conversation |
| `POST` | `/tui/open-sessions` | Open opencode's own session picker dialog |

### Conversation switching (no restart)

```bash
curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "{\"sessionID\": \"ses_abc123\"}" \
  "http://localhost:${AID_ORC_PORT}/tui/select-session"
```

Returns `true` on success. The opencode TUI switches instantly — no kill, no respawn, no lost state.

### Session listing

```bash
curl -s -H "Accept: application/json" \
  "http://localhost:${AID_ORC_PORT}/session"
```

Returns JSON array with `id`, `title`, `directory`, `time.updated`. Filter by `directory == repo_path` to show only conversations relevant to this session's project.

### Port derivation

```bash
orc_port=$(( 4200 + $(printf '%s' "$name" | cksum | cut -d' ' -f1) % 1000 ))
```

Deterministic and stable across restarts — no port discovery needed.

---

## Launch Behaviour

```bash
aid --mode orchestrator
```

1. Ensure the aid tmux server is running.
2. Find existing sessions tagged `@aid_mode=orchestrator`, sorted by `session_last_attached`.
3. **If sessions exist**: auto-attach to the most recently used one.
4. **If no sessions exist**: auto-create one from `$PWD` (name = sanitised `basename $PWD`).

No picker gate on launch — the operator lands directly in their last context.

### Creating additional sessions

From within any session, `prefix+s` → `n`. A new `aid@<basename_of_cwd>` session is created and the operator is switched to it immediately.

---

## Session Metadata

`aid` maintains `~/.local/share/aid[/<branch>]/sessions.json`:

```json
[
  {
    "tmux_session": "aid@my-project",
    "repo_path": "/home/user/my-project",
    "branch": "feature/auth-refactor",
    "created_at": "2026-03-10T09:00:00Z",
    "last_active": "2026-03-10T11:23:00Z"
  }
]
```

Used for:
- Showing repo path and branch in the navigator
- Dead session resurrection (repo_path needed to respawn layout)
- Last-active timestamps in the navigator display

---

## Comparison to `aid --fleet`

| Dimension | `aid --mode orchestrator` | `aid --fleet` |
| :-- | :-- | :-- |
| **Operator model** | Human switching between live sessions | Automated agents running in parallel |
| **Session lifecycle** | Persistent — accumulate, survive reboots | Ephemeral — spawned for a task, merged, discarded |
| **Parallelism** | All sessions alive; human moves focus | Workers execute concurrently on decomposed sub-tasks |
| **Task decomposition** | Human decides (manual per-session context) | `/fleet-plan` writes `tasks.md` automatically |
| **Git isolation** | Optional — each session can be on its own branch | Required — each worker in a dedicated git worktree |
| **Merge workflow** | Standard git / lazygit | `/fleet-merge` supervised AI merge |
| **Layout** | 2-pane (opencode + lazygit) + nvim tab + popup navigator | Half/half (opencode + status/diff supervisor) |
| **Entry point** | `aid --mode orchestrator` | `aid --fleet` |
| **Best for** | Multi-project juggling, long-running sessions, T3/Codex-style context switching | Single-project parallel task execution with LLM decomposition |

These two modes are **complementary**. The orchestrator mode is the daily driver for any developer running multiple opencode contexts; fleet mode is a power tool for a single large task that benefits from parallel sub-agents.

---

## Comparison to T3/Codex Workflow

| T3/Codex element | `aid --mode orchestrator` equivalent |
| :-- | :-- |
| Session/context list | `prefix+s` popup navigator |
| Coding agent | opencode in main pane |
| Diff review | lazygit in right pane |
| Switch to editor | `prefix+n` → nvim tab |

The key advantage over GUI-based equivalents (Codex Desktop, Cursor multi-session) is that this layout runs entirely in the terminal — over SSH, in tmux, survives disconnects, and requires no GUI.

---

## What `aid` Is Responsible For

1. **Bootstrap** the aid tmux server with correct config
2. **Spawn** new sessions on demand: opencode (`--port`) + lazygit + nvim tab
3. **Name** tmux sessions using `aid@<name>` convention, tag with `@aid_mode=orchestrator`
4. **Store** `AID_ORC_PORT` in session env for navigator → opencode HTTP communication
5. **Maintain** `sessions.json` for metadata persistence and dead session resurrection
6. **Provide** `aid-sessions` navigator script (fzf popup, `prefix+s`)

Everything else — what opencode does, what lazygit shows, what nvim edits — is outside `aid`'s responsibility.

---

## Implementation Notes

### Why popup, not persistent left pane

A persistent left pane in every session was attempted. The problems:
- After `tmux switch-client`, you are in a different session — the left pane of the previous session is no longer visible
- Linking windows across sessions is fragile and complex
- A fzf process running in a persistent pane with `exec` re-runs creates hard-to-debug restart loops

The popup approach (`prefix+s`) is strictly better: one keybind, works from any session or window, closes automatically after selection, zero persistent state to manage.

### Why opencode HTTP API, not DB queries

Direct SQLite/DB queries were attempted first. Problems:
- The DB path varies by `OPENCODE_CONFIG_DIR` and is not always at a predictable location
- No live session status (whether opencode is actively processing)
- Switching conversations required killing and restarting the opencode process — losing scroll position and any in-progress generation

The HTTP API (`GET /session`, `POST /tui/select-session`) is the correct integration point:
- Instant conversation switching with no process restart
- Returns live session metadata
- Stable — it's opencode's own public interface

### Port collision handling

The `cksum`-based port derivation gives deterministic ports in range 4200–5199. In the unlikely event of a collision between two sessions, opencode will fail to bind and print an error. A future improvement could detect this and pick the next free port.

---

## Key Differentiators

- **T3/Codex in the terminal** — the only terminal-native layout that directly replicates the session-list + agent + diff-review spatial workflow, with full SSH compatibility
- **True parallel sessions** — all sessions remain alive; background opencode instances continue running while you work in another session
- **opencode HTTP API** — conversation switching is instant via `POST /tui/select-session`, no process restarts
- **Zero GUI dependency** — runs over any SSH connection, survives disconnects, works in any terminal
- **Composable with `--fleet`** — orchestrator mode is the daily driver; fleet mode is invocable from within any orchestrator session when a task warrants parallel sub-agents
