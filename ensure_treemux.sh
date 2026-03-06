#!/usr/bin/env bash
# ensure_treemux.sh — open treemux sidebar if not already open; never closes it.
# Called from nvim VimEnter and the session-created hook.

TREEMUX_SCRIPTS=~/.config/tmux/plugins/treemux/scripts

# ARGS string is stored by sidebar.tmux under @treemux-key-Tab
ARGS=$(tmux show-option -gqv '@treemux-key-Tab')
PANE_ID="${TMUX_PANE:-$(tmux display-message -p '#{pane_id}')}"

if [ -z "$ARGS" ]; then
    # sidebar.tmux hasn't run yet (race at session start); bail out silently
    exit 0
fi

# Check if sidebar is already registered and the pane actually exists
existing=$(tmux show-option -gqv "@-treemux-registered-pane-$PANE_ID")
if [ -n "$existing" ]; then
    sidebar_pane=$(echo "$existing" | cut -d',' -f1)
    if tmux list-panes -F "#{pane_id}" | grep -q "^${sidebar_pane}$"; then
        exit 0  # already open, do nothing
    fi
fi

"$TREEMUX_SCRIPTS/toggle.sh" "$ARGS" "$PANE_ID"
