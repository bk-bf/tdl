# `aid --mode orchestrator` — Feature Breakdown & Analysis Report

---

## Executive Summary

`aid --mode orchestrator` is a tmux-native solo orchestration layout for the `aid` CLI that replicates the T3/Codex parallel workflow in a terminal-native environment. Unlike `aid --fleet` (which fans out decomposed sub-tasks to parallel agents in isolated worktrees), the orchestrator mode is designed around a **human operator** who runs multiple live opencode sessions simultaneously — one per project context — and switches between them with full spatial continuity. All sessions stay alive in the background; the operator moves focus, not the agents.

---

## The Core Premise: Sessions as First-Class Objects

In `aid --fleet`, opencode instances are ephemeral workers — spawned for a task, merged, discarded. In `aid --mode orchestrator`, each opencode session is a **persistent, named, project-scoped environment** that maps 1:1 to a tmux session. The operator accumulates sessions over time (one per project, one per feature branch, one per experiment) and the layout makes all of them navigable from a single entry point.

This is the T3/Codex workflow: parallel context windows, each fully live, with a session picker to move between them.

---

## The Three-Pane Layout

```
┌──────────────┬───────────────────────────────┬──────────────────────┐
│ SESSIONS     │                               │                      │
│              │      opencode                 │    diff reviewer     │
│ > my-project │      (active session)         │    (see options)     │
│   feature-a  │                               │                      │
│   feature-b  │        ~50% width             │      ~25% width      │
│              │                               │                      │
│ other-proj   │                               │                      │
│   main       │                               │                      │
│              │                               │                      │
│  ~25% width  │                               │                      │
└──────────────┴───────────────────────────────┴──────────────────────┘
  [tmux tab: nvim]  ← separate tmux window, switch with prefix+n
```

### Pane Responsibilities

| Pane | Content | Width |
| :-- | :-- | :-- |
| **Left** | Session navigator — all `aid@*` sessions grouped with their opencode conversations | ~25% |
| **Center** | Active opencode instance | ~50% |
| **Right** | Diff reviewer (see options below) | ~25% |
| **Tab: nvim** | Neovim + treemux sidebar, rooted to the repo | full |

---

## The Left Pane: Session Navigator

The left pane runs `aid-sessions` — a persistent fzf-based navigator. It shows all `aid@*` orchestrator sessions as collapsible folder headers, with each session's opencode conversations listed as children.

### Display format

```
aid@my-project  [live]  /home/user/my-project  (feature/auth)
  > Fix auth token refresh bug          3m ago   ← active conversation
    Refactor db schema                  1h ago

aid@other-proj  [live]  /home/user/other
    Initial setup                       2d ago

aid@old-work    [dead]                  5d ago
```

- **Session headers** — selectable: switches tmux client to that session
- **Conversations** — opencode conversations for that session's repo, sorted by last updated. Selecting one switches the conversation in the center pane's opencode instance via `POST /tui/select-session` — instant, no process restart.
- **Dead sessions** — in metadata but not in tmux. Selectable: resurrects the layout.

### Navigation keys

| Key | Action |
| :-- | :-- |
| `Enter` | Switch to session / load conversation in center pane |
| `n` | New session (auto-named from cwd basename, no prompts) |
| `d` | Delete session with confirmation |
| `r` | Rename session |
| `z` | Toggle collapse/expand session group |
| `ctrl-r` | Refresh list |
| `q` / `esc` | Close navigator |

### The persistent left pane problem

The left pane must remain visible when the user switches between `aid@*` sessions. Since each tmux session has its own window set, a pane in session A disappears when `switch-client` moves the terminal to session B.

**Chosen solution: left pane lives in every session.** Each `aid@<name>` session spawns its own `aid-sessions` navigator in the left pane. When the user switches sessions, the new session's left pane also shows the full session tree. The navigator always reflects the global picture — all `aid@*` sessions and their conversations — regardless of which session you are currently in.

**Rejected alternative: `prefix+s` popup.** A popup overlay was implemented and works, but is inferior: you cannot see the session list while reading opencode output. The persistent left pane provides the spatial continuity that is the whole point of the T3/Codex layout.

---

## The Right Pane: Diff Reviewer

The right pane shows a diff/code review tool rooted to the active session's repo. **lazygit is the current placeholder** but is likely to be replaced — it does not integrate well as a passive diff viewer in a fixed right pane (it is an interactive git client that expects full focus).

### Options

| Tool | Pros | Cons |
| :-- | :-- | :-- |
| **lazygit** | Already a dependency, familiar | Designed for full-screen interactive use; awkward in 25% pane |
| **`git diff` + auto-refresh** | Zero deps, always current | No interactivity, no staging |
| **`watch git diff --stat`** | Live summary of changes | No inline diff content |
| **`tig`** | TUI git browser, works well in narrow panes | Separate dependency |
| **`delta` pager** | Beautiful diffs, syntax highlighted | Not interactive, needs piping |
| **custom `git diff --color` loop** | Fully controlled, no extra deps | Requires implementation |

**Recommendation:** `tig` in browse mode (`tig status`) is the best fit — it works well in narrow panes, is keyboard-navigable without needing full focus, and shows both status and inline diffs. It is a single binary available in all major distros.

**Fallback:** a `watch -n2 git -C <repo> diff --stat` pane costs nothing and gives a live summary of changed files without any dependency.

The right pane is a deferred concern — the opencode center pane and left navigator are the critical path.

---

## Session Model

Each project launched under `aid --mode orchestrator` gets its own **tmux session** named:

```
aid@<name>
```

where `<name>` is the sanitised basename of the repo directory (same derivation as regular `aid` sessions). A numeric suffix is appended on collision: `aid@my-project`, `aid@my-project2`.

Sessions are tagged `@aid_mode=orchestrator` in the tmux session options at creation, so they are never confused with plain `aid` sessions sharing the same server.

### What lives inside each `aid@<name>` session

- **Window 0**: navigator (left, ~25%) + opencode (center, ~50%) + diff reviewer (right, ~25%)
- **Window 1 (`nvim`)**: full-width nvim + treemux sidebar
- **Session env vars**: `AID_ORC_NAME`, `AID_ORC_REPO`, `AID_ORC_PORT` (opencode HTTP port)

---

## opencode HTTP API Integration

opencode exposes a full HTTP API when started with `--port`. This is the correct integration point for the navigator — not DB queries, not `tmux send-keys`, not process restarts.

### Key endpoints

| Method | Endpoint | Purpose |
| :-- | :-- | :-- |
| `GET` | `/session` | List all conversations for this opencode instance |
| `POST` | `/tui/select-session` | Switch the running TUI to a specific conversation (instant) |
| `POST` | `/tui/open-sessions` | Open opencode's own session picker dialog |

### Conversation switching (no restart)

```bash
curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "{\"sessionID\": \"ses_abc123\"}" \
  "http://localhost:${AID_ORC_PORT}/tui/select-session"
```

Returns `true`. The opencode TUI switches instantly — no kill, no respawn, scroll position and in-progress generation preserved.

### Session listing (filtered by repo)

```bash
curl -s -H "Accept: application/json" \
  "http://localhost:${AID_ORC_PORT}/session"
```

Returns a JSON array with `id`, `title`, `directory`, `time.updated`. The navigator filters by `directory == repo_path` to show only conversations for this session's project.

### Port assignment

Each session gets a **deterministic fixed port** derived from the session name:

```bash
orc_port=$(( 4200 + $(printf '%s' "$name" | cksum | cut -d' ' -f1) % 1000 ))
```

Range: 4200–5199. Stable across restarts — no port discovery or coordination needed. Port stored in `AID_ORC_PORT` tmux session env.

**Note:** Direct SQLite/DB queries were attempted first and rejected. The DB path varies by `OPENCODE_CONFIG_DIR`, there is no live session status available, and switching conversations required killing the opencode process (losing scroll position and any active generation). The HTTP API is opencode's own public interface and the correct layer to use.

---

## Launch Behaviour

```bash
aid --mode orchestrator
```

1. Ensure the aid tmux server is running.
2. Find existing sessions tagged `@aid_mode=orchestrator`, sorted by `session_last_attached`.
3. **If sessions exist**: auto-attach to the most recently used one.
4. **If no sessions exist**: auto-create one from `$PWD` (name = sanitised `basename $PWD`), spawn the 3-pane layout, attach.

No picker gate on launch — the operator lands directly in their last context. The session navigator in the left pane is already visible and shows everything.

### Creating additional sessions

From within any session, press `n` in the left pane navigator. A new `aid@<basename_of_cwd>` session is spawned and the operator is switched to it.

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
- Dead session resurrection (`repo_path` needed to respawn the layout)
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
| **Merge workflow** | Standard git / diff reviewer | `/fleet-merge` supervised AI merge |
| **Layout** | 3-pane (navigator + opencode + diff) + nvim tab | Half/half (opencode + status/diff supervisor) |
| **Entry point** | `aid --mode orchestrator` | `aid --fleet` |
| **Best for** | Multi-project juggling, long-running sessions, T3/Codex-style context switching | Single-project parallel task execution with LLM decomposition |

These two modes are **complementary**. The orchestrator mode is the daily driver for any developer running multiple opencode contexts; fleet mode is a power tool for a single large task that benefits from parallel sub-agents.

---

## Comparison to T3/Codex Workflow

| T3/Codex element | `aid --mode orchestrator` equivalent |
| :-- | :-- |
| Session/context list | Left pane navigator (persistent, fzf) |
| Coding agent | opencode in center pane |
| Diff review | Right pane diff reviewer (tig / lazygit / custom) |
| Switch to editor | `prefix+n` → nvim tab |

The key advantage over GUI-based equivalents (Codex Desktop, Cursor multi-session) is that this layout runs entirely in the terminal — over SSH, in tmux, survives disconnects, and requires no GUI.

---

## What `aid` Is Responsible For

1. **Bootstrap** the aid tmux server with correct config
2. **Spawn** new sessions on demand: navigator (left) + opencode with `--port` (center) + diff reviewer (right) + nvim tab
3. **Name** tmux sessions `aid@<name>`, tag with `@aid_mode=orchestrator`
4. **Store** `AID_ORC_PORT` in session env for navigator → opencode HTTP communication
5. **Maintain** `sessions.json` for metadata persistence and dead session resurrection
6. **Provide** `aid-sessions` navigator (fzf, persistent left pane)

Everything else — what opencode does, what the diff tool shows, what nvim edits — is outside `aid`'s responsibility.

---

## Key Differentiators

- **T3/Codex in the terminal** — the only terminal-native layout that directly replicates the session-list + agent + diff-review spatial workflow, with full SSH compatibility
- **True parallel sessions** — all sessions remain alive; background opencode instances continue running while you work in another session
- **opencode HTTP API** — conversation switching is instant via `POST /tui/select-session`, no process restarts, no lost state
- **Zero GUI dependency** — runs over any SSH connection, survives disconnects, works in any terminal
- **Composable with `--fleet`** — orchestrator mode is the daily driver; fleet mode is invocable from within any orchestrator session when a task warrants parallel sub-agents


---
The start: bind (first load)
--bind "start:reload(aid-sessions-list 2>/dev/null || true)"
This fires once when fzf first opens. It doesn't need position preservation — there's no prior position — so it's a plain reload. Without this, fzf would show an empty list for the first 2 seconds until the ticker fires.

