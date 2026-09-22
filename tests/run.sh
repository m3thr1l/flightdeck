#!/usr/bin/env bash
# flightdeck's own tests. Needs tmux, zsh, python3; fzf for the pick test.
set -u
cd "$(dirname "$0")/.."
for f in deck.zsh; do zsh -n "$f" || exit 1; done
for f in deck-tty install.sh; do sh -n "$f" || exit 1; done
for f in deck-man deck-src; do bash -n "$f" || exit 1; done
echo "ok   syntax ($(tmux -V), $(zsh --version))"

. tests/harness.sh
harness_start "$PWD"
OUT=$(pane stdout); ERR=$(pane stderr); MAN=$(pane man)

check "four panes" "$(T list-panes -F '#{pane_title}' | tr '\n' ' ')" 'stdin stdout stderr man'
keys "echo out; echo err >&2; false" Enter
wait_for "$ERR" 'exit 1'
check "stdout split" "$(cap "$OUT" 3)" '^out$'
check "stderr split and exit stamp" "$(cap "$ERR" 3 | tr '\n' '|')" 'err.*exit 1'

t "deck mode >/tmp/deckci.$$ 2>&1; deck mode nope >>/tmp/deckci.$$ 2>&1"
check "deck mode lists modes" "$(cat /tmp/deckci.$$)" 'mode man \(available: man .*files\)'
check "unknown mode refused" "$(cat /tmp/deckci.$$)" 'no such mode: nope'
t "_deck_cmd_hello() { echo hello \$1 }"
t "deck hello world >/tmp/deckci.$$ 2>&1"; check "plugin subcommand" "$(cat /tmp/deckci.$$)" '^hello world$'
rm -f /tmp/deckci.$$

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
    keys "cat tests/har"; keys C-]; sleep 2; keys Enter; sleep 1.5
    keys C-a "echo BUF:" Enter; wait_for "$OUT" 'BUF:'
    check "fzf pick inserts the path" "$(cap "$OUT" 2)" 'BUF:cat tests/harness.sh'
else echo "skip fzf pick (no fzf)"; fi

keys Escape m; sleep 1; check "Alt-m leaves man mode" "$(T list-panes -F '#{pane_title}' | tr '\n' ' ')" 'stdin stdout stderr [a-z]+ ' 
check "Alt-m: not man" "$(T list-panes -F '#{pane_title}' | tail -1)" '^(files|script|net|cisco)$'
for i in 1 2 3 4 5; do [ "$(T list-panes -F '#{pane_title}' | tail -1)" = man ] && break; keys Escape m; sleep 1; done
check "Alt-m cycles back to man" "$(T list-panes -F '#{pane_title}' | tail -1)" '^man$'

if [ "$(T show-options -pv -t "$OUT" allow-set-title 2>/dev/null)" = off ]; then
    t "printf '\\e]2;HIJACK\\a'"; sleep 0.5
    check "output panes ignore title escapes" "$(T list-panes -F '#{pane_title}' | tr '\n' ' ')" 'stdout stderr'
else echo "skip title protection ($(tmux -V) has no allow-set-title pane option)"; fi

t "vim -c q 2>/dev/null || true"; check "deck-tty restores zoom" "$(T display-message -p '#{window_zoomed_flag}')" '^0$'

t "deck off"; sleep 0.5
check "deck off closes panes" "$(T list-panes -F '#{pane_title}' | wc -l | tr -d ' ')" '^1$'
harness_stop
