#!/usr/bin/env bash
# dead-server.sh — kill the suite's tmux server, then call t.
set -u
. "$FLIGHTDECK/tests/harness.sh"
harness_start
T kill-server
echo "<<t"
s=$SECONDS
t "echo x"
rc=$?
echo "t>> rc=$rc elapsed=$(( SECONDS - s ))"
harness_stop
