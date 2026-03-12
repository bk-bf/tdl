
                           █████╗ ██╗██████╗
                          ██╔══██╗██║██╔══██╗
                          ███████║██║██║  ██║
                          ██╔══██║██║██║  ██║
                          ██║  ██║██║██████╔╝
                          ╚═╝  ╚═╝╚═╝╚═════╝

              terminal IDE  ·  open source  ·  AI-native



━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  AI   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /commit          stage → conventional commit message from diff
  /udoc            update docs to reflect current code changes

  .aidignore       hide files from tree + search  (one glob per line)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  NAVIGATION  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  「leader」f     find files               「leader」1     search in files
  「leader」2     switch open buffers      「leader」t     toggle file tree
  「leader」tf    reveal file in tree

  「Tab」         next tab                 「S-Tab」        prev tab
  「leader」q     close tab                「leader」tb    toggle tab bar

  「C-d」         scroll down (centered)   「C-u」         scroll up (centered)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  BOOKMARKS  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  「leader」ba    add file / dir           「leader」bd    remove bookmark
  「leader」bb    open bookmarks           cross-project · stored globally


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   GIT   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  「leader」gg    open lazygit             「leader」do    diff vs last commit
  「leader」dx    close diff               「leader」j     next hunk
  「leader」k     prev hunk                「leader」hp    preview hunk
  「leader」hl    toggle line highlight


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   LSP   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  「gd」          go to definition         「K」           hover docs
  「gr」          references               「leader」rn    rename symbol
  「leader」ca    code action              「leader」7     next diagnostic
  「leader」8     prev diagnostic          「leader」9     show diagnostic

  :Mason         install LSP servers, linters, formatters, DAP adapters


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  FORMAT / LINT  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  「leader」F     format buffer            auto-formats on save (LSP fallback)
  linters run on save · add tools via :Mason · configure in .nvim.lua


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  DEBUG  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  「leader」dc    continue / start         「leader」db    toggle breakpoint
  「leader」dB    conditional breakpoint   「leader」di    step into
  「leader」do    step over                「leader」dO    step out
  「leader」dr    open REPL                「leader」dq    terminate
  「leader」du    toggle debug UI

  install DAP adapters via :Mason · UI opens automatically on session start


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  EDITING  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  「J」/「K」     move lines down/up (visual)
  「leader」u     undo tree                「leader」r     reload file
  「leader」R     reload workspace         「C-Space」     trigger completion
  「CR」          confirm completion


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  SESSION  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  「leader」ss    restore session (cwd)    「leader」sl    restore last session
  「leader」sd    don't save on exit


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   SPELL   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  「leader」sS    toggle spell (en)        「leader」se    English only
  「leader」sn    spell off


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  MARKDOWN  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  「leader」mp    preview in browser       「leader」ms    stop preview


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  TMUX   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  「C-h/j/k/l」      navigate panes           aid              new session (cwd)
  「M-←/→/↑/↓」    navigate panes (alt)     aid -a [name]    attach to session
  「M-q」            close pane               「M-Q」          kill session (confirm)
  「leader」?        reopen this cheatsheet   aid -l           list sessions

  「prefix+1」       IDE window               「prefix+2」     orchestrator window
                     tree · editor · AI        navigator · opencode · diff


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  ORCHESTRATOR  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  navigator (left pane — active in prefix+2 window)

  「↑/k」「↓/j」    move cursor              「Enter」        load conversation
  「n」              new session              「r」            rename session
  「d」              delete session           「C-R」          force refresh

  diff pane (right pane — active in prefix+2 window)

  「↑/k」「↓/j」    scroll                   「Enter/Space」  expand file diff
  「t」              cycle mode               「r」            refresh
                     HEAD · staged · unstaged


                      ── open any file to start editing ──

