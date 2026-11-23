#!/usr/bin/env bash
# child.sh — a minimal passing suite that reports its root and its socket.
set -u
. "$FLIGHTDECK/tests/harness.sh"
harness_start
echo "sock=$(T display-message -p '#{socket_path}')"
echo "root=$HARNESS_ROOT"
t "echo x"
wait_for "$(pane stdout)" '^x$' 5
check "H-12 probe: the suite runs" "$?" '^0$'
harness_stop
