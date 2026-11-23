#!/usr/bin/env bash
# t-out.sh — t_out on a line that writes to stdout and stderr, t_out on a line
# that never returns, then t on a line; and a count of t_out's text in panes.
set -u
. "$FLIGHTDECK/tests/harness.sh"
harness_start
echo "<<t_out"
t_out "echo TO-OUT-\$((6*7)); echo TO-ERR-\$((6*7)) >&2"
echo "t_out>> rc=$?"
echo "<<t_out-bad"
t_out "echo [x]" 2
echo "t_out-bad>> rc=$?"
t "echo CTRL-\$((6*7))"
wait_for "$(pane stdout)" 'CTRL-42' 5
echo "control-shown=$?"
echo "in-panes=$(for p in $(T list-panes -F '#{pane_id}'); do T capture-pane -p -S - -t "$p"; done | grep -cE 'TO-(OUT|ERR)-42')"
harness_stop
