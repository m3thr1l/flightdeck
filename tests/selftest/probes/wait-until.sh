#!/usr/bin/env bash
# wait-until.sh — wait_until without tmux: a function that succeeds on its
# third call, false, a command with arguments, and a command that prints.
set -u
calls=$(mktemp "${TMPDIR:-/tmp}/calls.XXXXXX") || exit 1
. "$FLIGHTDECK/tests/harness.sh"
third() { echo call >>"$calls"; [ "$(wc -l <"$calls" | tr -d ' ')" -ge 3 ]; }
s=$SECONDS
wait_until 5 third
rc=$?
echo "third rc=$rc calls=$(wc -l <"$calls" | tr -d ' ') elapsed=$(( SECONDS - s ))"
rm -f "$calls"
s=$SECONDS
wait_until 2 false
rc=$?
echo "false rc=$rc elapsed=$(( SECONDS - s ))"
wait_until 1 test 1 = 1
echo "args-true rc=$?"
wait_until 1 test 1 = 2
echo "args-false rc=$?"
out=$(wait_until 2 echo LOUD)
rc=$?
echo "quiet rc=$rc out=$out"
