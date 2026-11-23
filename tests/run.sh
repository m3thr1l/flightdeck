#!/usr/bin/env bash
# flightdeck's own tests. Needs tmux, zsh, python3; fzf for the pick test.
set -u
cd "$(dirname "$0")/.."

. tests/harness.sh
harness_start "$PWD"
OUT=$(pane stdout); ERR=$(pane stderr); MAN=$(pane man)

check "four panes" "$(T list-panes -F '#{pane_title}' | tr '\n' ' ')" 'stdin stdout stderr man'
keys "echo out; echo err >&2; false" Enter
wait_for "$ERR" 'exit 1'
check "stdout split" "$(cap "$OUT" 3)" '^out$'
check "stderr split and exit stamp" "$(cap "$ERR" 3 | tr '\n' '|')" 'err.*exit 1'

modes=$(t_out "deck mode; deck mode nope")
check "deck mode lists modes" "$modes" 'mode man \(available: man .*files\)'
check "unknown mode refused" "$modes" 'no such mode: nope'
t "_deck_cmd_hello() { echo hello \$1 }"
check "plugin subcommand" "$(t_out "deck hello world")" '^hello world$'

if man -w ls >/dev/null 2>&1; then
    keys "ls -l"; wait_for "$MAN" ' ls ' 6; check "man follower" "$(T capture-pane -p -t "$MAN" | head -1)" '^ ls '
    keys C-u
else echo "skip man follower (no man pages)"; fi

keys "cat .gi"; wait_for "$MAN" '\.gi\*' 6
check "path-aware listing" "$(T capture-pane -p -t "$MAN" | head -1)" '^ \./  \.gi\*'
keys C-u
keys "cat .github/wor"; wait_for "$MAN" 'workflows' 6
check "listing of a subdirectory" "$(T capture-pane -p -t "$MAN" | head -3 | tr '\n' '|')" '\.github/.*workflows'
keys C-u

if command -v fzf >/dev/null; then
    keys "cat tests/har"; keys C-]; wait_for "$HARNESS_PROMPT" '[0-9]+/[0-9]+'; keys Enter
    wait_last "$HARNESS_PROMPT" 'cat tests/harness\.sh'
    keys C-a "echo BUF:" Enter; wait_for "$OUT" 'BUF:'
    check "fzf pick inserts the path" "$(cap "$OUT" 2)" 'BUF:cat tests/harness.sh'
else echo "skip fzf pick (no fzf)"; fi

keys Escape m; wait_title ' files$'; check "Alt-m leaves man mode" "$(T list-panes -F '#{pane_title}' | tr '\n' ' ')" 'stdin stdout stderr [a-z]+ ' 
check "Alt-m: not man" "$(T list-panes -F '#{pane_title}' | tail -1)" '^(files|script|net|cisco)$'
keys Escape m; wait_title ' man$'
check "Alt-m cycles back to man" "$(T list-panes -F '#{pane_title}' | tail -1)" '^man$'

if [ "$(T show-options -pv -t "$OUT" allow-set-title 2>/dev/null)" = off ]; then
    t "printf '\\e]2;HIJACK\\a'; echo HIJACK-DONE-\$((6*7))"; wait_for "$OUT" 'HIJACK-DONE-42'
    check "output panes ignore title escapes" "$(T list-panes -F '#{pane_title}' | tr '\n' ' ')" 'stdout stderr'
else echo "skip title protection ($(tmux -V) has no allow-set-title pane option)"; fi

t "path=($PWD/tests/bin \$path); deck off; deck"
t "vim -c q"
check "H-05 a DECK_TTY_CMDS program runs with the window zoomed" "$(cat "$HARNESS_ROOT/zoom" 2>/dev/null)" '^1$'
check "deck-tty restores zoom" "$(T display-message -p '#{window_zoomed_flag}')" '^0$'

t "deck off"
check "deck off closes panes" "$(T list-panes -F '#{pane_title}' | wc -l | tr -d ' ')" '^1$'
t "echo AFTER-OFF-\$((6*7))"
check "H-06 after deck off the prompt pane prints the command's output" "$(cap "$HARNESS_PROMPT" 3)" '^AFTER-OFF-42$'
harness_stop
