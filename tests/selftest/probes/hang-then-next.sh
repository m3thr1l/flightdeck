#!/usr/bin/env bash
# hang-then-next.sh — with the follower off, a line that outlives its bound,
# then a line that works.
set -u
. "$FLIGHTDECK/tests/harness.sh"
harness_start
t "DECK_FOLLOW=0"
t "sleep 30" 2
echo "first-rc=$?"
t "echo NEXT-\$((6*7))"
echo "next-rc=$?"
wait_for "$(pane stdout)" 'NEXT-42' 3
echo "next-shown=$?"
harness_stop
