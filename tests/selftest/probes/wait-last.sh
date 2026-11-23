#!/usr/bin/env bash
# wait-last.sh — two output lines in the stdout pane; wait_last for the last
# one and for the one before it.
set -u
. "$FLIGHTDECK/tests/harness.sh"
harness_start
OUT=$(pane stdout)
t "echo EARLY-\$((6*7)); echo LATE-\$((6*7))"
wait_for "$OUT" 'LATE-42'
s=$SECONDS
out=$(wait_last "$OUT" '^LATE-42$' 2)
rc=$?
echo "last rc=$rc elapsed=$(( SECONDS - s )) out=$out"
s=$SECONDS
out=$(wait_last "$OUT" '^EARLY-42$' 2)
rc=$?
echo "earlier rc=$rc elapsed=$(( SECONDS - s )) out=$out"
harness_stop
