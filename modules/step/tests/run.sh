#!/usr/bin/env bash
# flightdeck-step tests: shell and Python stepping inside the deck.
set -u
cd "$(dirname "$0")/.."
zsh -n step.zsh && sh -n deck-step && python3 -c "import ast; ast.parse(open('deck-step-py').read())" || exit 1
echo "ok   syntax"
FLIGHTDECK=${FLIGHTDECK:-$(cd ../.. && pwd)}
. "$FLIGHTDECK/tests/harness.sh"
harness_start "$PWD" "$PWD/step.zsh"
OUT=$(pane stdout); ERR=$(pane stderr)
t "DECK_FOLLOW=0"

check "script mode registered" "$(t_out "deck mode")" 'script'
keys "deck step tests/t.sh" Enter; wait_for "$(pane script)" 't\.sh:2' 6
check "shell: source painted with marker" "$(T capture-pane -p -t "$(pane script)" | head -3 | tr '\n' '|')" 't\.sh:2.*\[n\]ext.*>   2 x=1'
keys n; wait_for "$(pane script)" 't\.sh:6' 6
check "shell: n advances (x=1 -> f a at line 6)" "$(T capture-pane -p -t "$(pane script)" | head -1)" 't\.sh:6'
keys c; wait_for "$OUT" '^2$' 6
check "shell: output stamped per command" "$(T capture-pane -p -t "$OUT" | grep -v '^$' | tr '\n' '|')" 't\.sh:4 ❯ echo "in f \$1"\|in f a'
check "shell: trace in stderr" "$(cap "$ERR" 4 | tr '\n' '|')" 't\.sh:8 ❯ echo \$i'
check "shell: exit 0, mode restored" "$(t_out "echo rc=\$? mode=\$DECK_MODE")" 'rc=0 mode=man'

keys "deck step tests/t.py" Enter; wait_for "$(pane script)" 't\.py:2' 6
check "python: source painted" "$(T capture-pane -p -t "$(pane script)" | head -1)" 't\.py:2.*\[n\]ext'
keys c; wait_for "$OUT" 'done 2 6' 8
check "python: values after assignments" "$(T capture-pane -p -S -60 -t "$OUT" | grep -E '^   [a-z]+ = ' | tr '\n' ' ')" 'x = 1 .*y = 2 .*z = 2 .*total = 6'
check "python: exit 0" "$(t_out "echo rc=\$?")" 'rc=0'

keys "tests/t.sh"; keys Escape x; wait_for "$(pane script)" 't\.sh:2' 6
check "Alt-x wraps the line in deck step" "$(T capture-pane -p -t "$(pane script)" | head -1)" 't\.sh:2'
keys q; wait_for "$ERR" 'exit 130' 6
check "q aborts with 130" "$(t_out "echo rc=\$?")" 'rc=130'

harness_stop; rc=$?
harness_suites tests/suites; exit $(( rc + $? ))
