#!/usr/bin/env bash
# flightdeck-step tests: shell and Python stepping inside the deck.
set -u
cd "$(dirname "$0")/.."
zsh -n step.zsh && sh -n deck-step && sh -n install.sh && python3 -c "import ast; ast.parse(open('deck-step-py').read())" || exit 1
echo "ok   syntax"
FLIGHTDECK=${FLIGHTDECK:-$(cd ../.. && pwd)}
. "$FLIGHTDECK/tests/harness.sh"
harness_start "$PWD" "$PWD/step.zsh"
OUT=$(pane stdout); ERR=$(pane stderr)

t "deck mode >/tmp/deckci.$$"; check "script mode registered" "$(cat /tmp/deckci.$$)" 'script'
keys "deck step tests/t.sh" Enter; wait_for "$(pane script)" 't\.sh:2' 6
check "shell: source painted with marker" "$(T capture-pane -p -t "$(pane script)" | head -3 | tr '\n' '|')" 't\.sh:2.*\[n\]ext.*>   2 x=1'
keys n; sleep 0.5; check "shell: n advances (x=1 -> f a at line 6)" "$(T capture-pane -p -t "$(pane script)" | head -1)" 't\.sh:6'
keys c; wait_for "$OUT" '^2$' 6
check "shell: output stamped per command" "$(T capture-pane -p -t "$OUT" | grep -v '^$' | tr '\n' '|')" 't\.sh:4 ❯ echo "in f \$1"\|in f a'
check "shell: trace in stderr" "$(cap "$ERR" 4 | tr '\n' '|')" 't\.sh:8 ❯ echo \$i'
t "echo rc=\$? mode=\$DECK_MODE >/tmp/deckci.$$"; check "shell: exit 0, mode restored" "$(cat /tmp/deckci.$$)" 'rc=0 mode=man'

keys "deck step tests/t.py" Enter; wait_for "$(pane script)" 't\.py:2' 6
check "python: source painted" "$(T capture-pane -p -t "$(pane script)" | head -1)" 't\.py:2.*\[n\]ext'
keys c; wait_for "$OUT" 'done 2 6' 8
check "python: values after assignments" "$(T capture-pane -p -S -60 -t "$OUT" | grep -E '^   [a-z]+ = ' | tr '\n' ' ')" 'x = 1 .*y = 2 .*z = 2 .*total = 6'
t "echo rc=\$? >/tmp/deckci.$$"; check "python: exit 0" "$(cat /tmp/deckci.$$)" 'rc=0'

keys "tests/t.sh"; keys Escape x; wait_for "$(pane script)" 't\.sh:2' 6
check "Alt-x wraps the line in deck step" "$(T capture-pane -p -t "$(pane script)" | head -1)" 't\.sh:2'
keys q; sleep 1; t "echo rc=\$? >/tmp/deckci.$$"; check "q aborts with 130" "$(cat /tmp/deckci.$$)" 'rc=130'
rm -f /tmp/deckci.$$
harness_stop
