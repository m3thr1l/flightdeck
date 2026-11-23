#!/usr/bin/env bash
# line.sh LINE [BOUND] — start a deck and turn the follower off, so that a
# bound measures the line and not the typing; then type LINE with
# `t LINE BOUND` (or `t LINE` when BOUND is empty), report what t printed, its
# status and its time, run one more check and stop.
set -u
. "$FLIGHTDECK/tests/harness.sh"
harness_start
t "DECK_FOLLOW=0"
echo "sock=$(T display-message -p '#{socket_path}')"
echo "root=$HARNESS_ROOT"
echo "before-t=$(date +%s)"
echo "<<t"
s=$SECONDS
t "$1" ${2:+"$2"}
rc=$?
echo "t>> rc=$rc elapsed=$(( SECONDS - s ))"
check "H-03 probe: a later check still runs" "later" '^later$'
harness_stop
