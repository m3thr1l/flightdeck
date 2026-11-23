#!/usr/bin/env bash
# titles.sh — titles after harness_start; wait_title for a change of mode and
# for a pattern that never matches; titles after the change.
set -u
. "$FLIGHTDECK/tests/harness.sh"
harness_start
out=$(titles)
rc=$?
echo "before rc=$rc lines=$(printf '%s' "$out" | awk 'END { print NR }') text=$out"
t "deck mode files"
s=$SECONDS
out=$(wait_title ' files$')
rc=$?
echo "match rc=$rc elapsed=$(( SECONDS - s )) out=$out"
echo "after text=$(titles)"
s=$SECONDS
out=$(wait_title 'no-such-title' 2)
rc=$?
echo "never rc=$rc elapsed=$(( SECONDS - s )) out=$out"
harness_stop
