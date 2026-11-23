#!/usr/bin/env bash
# early-exit.sh — a suite that sets an EXIT trap, sources the harness, starts
# it, and exits part-way without calling harness_stop.
set -u
trap 'echo caller-trap-ran' EXIT
. "$FLIGHTDECK/tests/harness.sh"
harness_start
echo "sock=$(T display-message -p '#{socket_path}')"
echo "root=$HARNESS_ROOT"
exit 1
