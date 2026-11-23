#!/usr/bin/env bash
# early-unset.sh — a suite under set -u that stops at an unset variable
# without calling harness_stop.
set -u
. "$FLIGHTDECK/tests/harness.sh"
harness_start
echo "sock=$(T display-message -p '#{socket_path}')"
echo "root=$HARNESS_ROOT"
echo "$probe_variable_that_is_never_set"
echo "not reached"
