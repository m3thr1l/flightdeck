#!/usr/bin/env bash
# quiet-tail.sh — with the deck and its man follower on, put a man that logs
# every call first on the pane shell's path, then type lines whose own command
# needs no manual page (an assignment) and report what the follower looked up
# while t typed them; then a line whose command has a page, as the control.
set -u
. "$FLIGHTDECK/tests/harness.sh"
real=$(command -v man) || { echo "no-man"; exit 0; }
log=$HARNESS_ROOT/man.log
mkdir "$HARNESS_ROOT/bin"
printf '%s\n' '#!/bin/sh' "printf '%s\\n' \"\$*\" >>'$log'" "exec '$real' \"\$@\"" >"$HARNESS_ROOT/bin/man"
chmod +x "$HARNESS_ROOT/bin/man"
# Exported before the server starts, so the pane shell has it without a
# typed path (typing a long path is work for the follower in its own right).
export PATH="$HARNESS_ROOT/bin:$PATH"
harness_start
t "H26=0"
: >"$log"
t "H26=1"
echo "quiet>> rc=$? lookups=$(wc -l <"$log" | tr -d ' ') log=$(tr '\n' '|' <"$log")"
: >"$log"
t "ls >/dev/null"
echo "control>> rc=$? log=$(tr '\n' '|' <"$log")"
harness_stop
