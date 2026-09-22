#!/usr/bin/env bash
# flightdeck-cisco tests: a session against the fake device, inside the deck.
set -u
cd "$(dirname "$0")/.."
zsh -n cisco.zsh && sh -n install.sh && python3 -c "import ast; ast.parse(open('deck-net').read()); ast.parse(open('tests/fake-ios').read())" || exit 1
echo "ok   syntax"
FLIGHTDECK=${FLIGHTDECK:-$(cd ../flightdeck && pwd)}
. "$FLIGHTDECK/tests/harness.sh"
harness_start "$PWD" "$PWD/cisco.zsh"
OUT=$(pane stdout); ERR=$(pane stderr)

keys "deck net --exec tests/fake-ios" Enter; wait_for %0 'Switch>' 6; sleep 1.5   # deck's delayed title-setter, then deck-net's reassert
check "title follows the device mode" "$(T list-panes -F '#{pane_title}' | tr '\n' ' ')" 'stdin ▸ Switch exec.* cisco'
keys "show version" Enter; wait_for "$OUT" 'uptime' 6
check "output to stdout pane, stamped" "$(cap "$OUT" 3 | tr '\n' '|')" '❯ show version\|Cisco IOS.*\|uptime'
keys "bogus" Enter; wait_for "$ERR" 'Invalid input' 6
check "errors to stderr pane" "$(cap "$ERR" 2 | tr '\n' '|')" '\^\|% Invalid input'
keys "show ip ?"; wait_for "$(pane cisco)" 'interfaces' 6
check "? answered in the follower" "$(T capture-pane -p -t "$(pane cisco)" | grep -v '^$' | tr '\n' '|')" 'interfaces.*Interface status'
keys C-u
keys "show long" Enter; wait_for "$OUT" 'line 7 of' 12
check "pager answered, all lines in stdout" "$(T capture-pane -p -S -40 -t "$OUT" | grep -c 'of a long listing')" '^7$'
check "prompt pane clean after pager" "$(cap %0 3 | grep -c 'of a long listing')" '^0$'
keys "write" Enter; wait_for %0 'yes/no' 6
check "question shown at once" "$(cap %0 1)" 'Save configuration\? \[yes/no\]:'
keys "yes" Enter; wait_for "$OUT" '\[OK\]' 6
check "answer and reply in stdout" "$(cap "$OUT" 3 | tr '\n' '|')" 'yes/no\]: yes\|Building.*\|\[OK\]'
keys "reload" Enter; wait_for %0 'confirm' 6; keys n; wait_for "$OUT" 'cancelled' 6
check "one-key answer" "$(cap "$OUT" 1)" 'Reload cancelled'
keys "enable" Enter; sleep 0.5; keys "conf t" Enter; sleep 1
check "config mode in title" "$(T list-panes -F '#{pane_title}' | head -1)" 'Switch \(config\)'
keys -l "end"; keys Enter; sleep 0.5; keys -l "exit"; keys Enter; sleep 1.5
t "echo mode=\$DECK_MODE >/tmp/deckci.$$"; check "mode restored" "$(cat /tmp/deckci.$$)" 'mode=man'
rm -f /tmp/deckci.$$
harness_stop
