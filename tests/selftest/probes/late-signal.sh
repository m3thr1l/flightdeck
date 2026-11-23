#!/usr/bin/env bash
# late-signal.sh — with the follower off, a line that ignores Ctrl-C finishes
# after its bound and prints LATE-42; a later call must still wait for its own
# line.
set -u
. "$FLIGHTDECK/tests/harness.sh"
harness_start
t "DECK_FOLLOW=0"
t "( trap '' INT; sleep 3 ); echo LATE-\$((6*7))" 1
echo "first-rc=$?"
s=$SECONDS
t "sleep 4" 10
rc=$?
echo "second-rc=$rc second-elapsed=$(( SECONDS - s ))"
wait_for "$(pane stdout)" 'LATE-42' 3
echo "late-shown=$?"
harness_stop
