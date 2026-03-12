# Task: Refactor `aid-sessions` — Extract Shared Components

**Status:** Ready to implement  
**Branch:** `feature/orchestrator`  
**Scope:** `lib/sessions/`, `lib/orchestrator.sh`

---

## Background

During implementation of the `d`-key delete flow in `aid-sessions`, two reusable components were already extracted:

- `aid-popup` — generic `tmux display-menu` wrapper (shipped in `d675402`)

A follow-up audit of the full `lib/sessions/` + `lib/orchestrator.sh` surface identified five more extraction candidates with genuine duplication. This document specifies each one.

---

## Candidates

### 1. `_dbg` — Debug Logger

**Problem:** Defined independently in `aid-sessions` and `aid-popup` with a slightly different signature.

```bash
# aid-sessions (parametric category)
_dbg() {
  [[ -z "${AID_DEBUG_LOG:-}" ]] && return 0
  local cat="$1"; shift
  local ms; ms=$(date +%s%3N 2>/dev/null || printf '%s000' "$(date +%s)")
  printf '%s %s %s\n' "$ms" "$cat" "$*" >> "$AID_DEBUG_LOG"
}

# aid-popup (hardcoded POPUP category)
_dbg() {
  [[ -z "${AID_DEBUG_LOG:-}" ]] && return 0
  local _ms; _ms=$(date +%s%3N 2>/dev/null || printf '%s000' "$(date +%s)")
  printf '%s POPUP %s\n' "$_ms" "$*" >> "$AID_DEBUG_LOG"
}
```

**Fix:** Move the `aid-sessions` variant (parametric category) into `aid-meta`. Both files source `aid-meta` already. `aid-popup` calls `_dbg POPUP ...`.

**Files affected:** `aid-meta`, `aid-sessions`, `aid-popup`

---

### 2. `_orc_port_for` — opencode Port Resolution

**Problem:** The same three-line tmux env lookup appears in three places:

```bash
# aid-sessions: standalone function (canonical)
_orc_port_for() { ... tmux show-environment -t "$1" AID_ORC_PORT ... }

# aid-sessions: _load_conversation — inline duplicate
orc_port=$(tmux -L aid show-environment -t "$tmux_session" AID_ORC_PORT 2>/dev/null \
  | cut -d= -f2- || true)

# aid-sessions-list — inline duplicate, no validation
_orc_port=$(tmux -L aid show-environment -t "$_session" AID_ORC_PORT 2>/dev/null \
  | cut -d= -f2- || true)
```

**Fix:** Move `_orc_port_for` into `aid-meta`. Replace both inline copies with a call to it. `aid-sessions-list` already sources `aid-meta`.

**Files affected:** `aid-meta`, `aid-sessions`, `aid-sessions-list`

---

### 3. `aid-api` — opencode HTTP Helpers

**Problem:** opencode API calls are spread across `aid-sessions` (3 call sites) and `aid-sessions-list` (1 call site) with no shared abstraction. The base URL pattern `http://127.0.0.1:${port}/...` is repeated everywhere.

**Current call sites:**

| File | Call | Endpoint |
|---|---|---|
| `aid-sessions` | `_opencode_delete_conv` | `DELETE /session/{id}` |
| `aid-sessions` | `_opencode_delete_all_convs` | `GET /session` + loop |
| `aid-sessions` | `_load_conversation` | `POST /tui/select-session` |
| `aid-sessions-list` | `_opencode_conversations` | `GET /session` |

**Fix:** Create `lib/sessions/aid-api` (sourceable, not executable). Define:

```bash
# _api_list_convs <port> [repo_path_filter]
# Prints TSV: id \t title \t updated_epoch_ms
# Filters by .directory == repo_path when provided.

# _api_delete_conv <port> <conv_id>
# DELETE /session/{conv_id}. Prints curl rc to debug log.

# _api_select_session <port> <conv_id>
# POST /tui/select-session {"sessionID": conv_id}
```

Move `_opencode_conversations` (from `aid-sessions-list`), `_opencode_delete_conv`, and the select-session curl call (from `_load_conversation` in `aid-sessions`) into `aid-api`. `_opencode_delete_all_convs` becomes a thin wrapper that calls `_api_list_convs` then loops `_api_delete_conv`.

Both `aid-sessions` and `aid-sessions-list` source `aid-api`.

**Files affected:** `aid-api` (new), `aid-sessions`, `aid-sessions-list`

---

### 4. `aid-meta-touch` — Remove jq Duplication

**Problem:** `aid-meta-touch` reimplements the exact jq mutation from `_meta_touch` in `aid-meta` rather than calling it.

```bash
# aid-meta-touch (lines 18-21) — duplicate of aid-meta::_meta_touch
now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq --arg s "$tmux_session" --arg t "$now" \
  'map(if .tmux_session==$s then .last_active=$t else . end)' \
  "$metadata_file" > "${metadata_file}.tmp" && mv "${metadata_file}.tmp" "$metadata_file"
```

**Fix:** `aid-meta-touch` sources `aid-meta` and calls `_meta_touch "$1"`. Body becomes 5 lines.

**Files affected:** `aid-meta-touch`

---

### 5. `_respawn_pane` — Pane Spawn Helper in `orchestrator.sh`

**Problem:** The log-before + `respawn-pane -k` + log-after triple is repeated 4 times in `spawn_orc_session` — for `orc_pane`, `nav_pane`, `dbg_pane`, `nvim_pane`.

```bash
# Repeated pattern (example: orc pane)
_spawn_log "$debug_log" "respawn orc_pane=${orc_pane}: opencode ..."
tmux -L aid respawn-pane -k -t "$orc_pane" "ENV=... command"
_spawn_log "$debug_log" "orc_pane=${orc_pane} respawned (opencode)"
```

**Fix:** Add a private helper inside `orchestrator.sh`:

```bash
# _respawn_pane <log> <pane> <label> <cmd>
# Logs "respawn <pane>: <label>", runs respawn-pane -k, logs "<pane> respawned (<label>)".
_respawn_pane() {
  local _log="$1" _pane="$2" _label="$3" _cmd="$4"
  _spawn_log "$_log" "respawn ${_pane}: ${_label}"
  tmux -L aid respawn-pane -k -t "$_pane" "$_cmd"
  _spawn_log "$_log" "${_pane} respawned (${_label})"
}
```

**Files affected:** `orchestrator.sh` only (internal refactor)

---

## What is NOT being extracted

| Pattern | Reason |
|---|---|
| Timestamp `date +%s%3N` | One-liner; a function call adds more noise than the duplication |
| `_switch_to_session` / `_attach_or_switch` | The two callers have different contexts (inside pane vs. launcher); extracting adds a cross-file source dependency for marginal gain |
| fzf `--bind` debug strings | Run in a forked shell context — cannot call functions defined in the parent |

---

## Implementation Order

1. `aid-meta` — add `_dbg` and `_orc_port_for`
2. `aid-sessions` — remove `_dbg`, remove `_orc_port_for`, use `_orc_port_for` in `_load_conversation`
3. `aid-popup` — remove `_dbg`, use the one from `aid-meta`
4. `aid-sessions-list` — remove inline port lookup, call `_orc_port_for`
5. `aid-api` (new) — move `_opencode_conversations`, `_opencode_delete_conv`, select-session curl; add `_api_list_convs`, `_api_delete_conv`, `_api_select_session`
6. `aid-sessions` — source `aid-api`, replace internal functions with API calls
7. `aid-sessions-list` — source `aid-api`, replace `_opencode_conversations` with `_api_list_convs`
8. `aid-meta-touch` — source `aid-meta`, call `_meta_touch`
9. `orchestrator.sh` — add `_respawn_pane`, replace 4 call sites

Run `shellcheck -x` on every changed file before committing.
