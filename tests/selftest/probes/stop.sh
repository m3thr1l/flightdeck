#!/usr/bin/env bash
# stop.sh — one passing and one failing check, then harness_stop twice,
# reporting what each call printed and returned and whether the server lives.
set -u
. "$FLIGHTDECK/tests/harness.sh"
harness_start
sock=$(T display-message -p '#{socket_path}')
root=$HARNESS_ROOT
echo "sock=$sock"
echo "root=$root"
[ -n "$root" ] && [ -d "$root" ] && echo "root-before=dir" || echo "root-before=none"
check "H-13 probe: passes" a '^a$'
check "H-13 probe: fails on purpose" a '^b$'
echo "<<stop1"
harness_stop
echo "stop1>> rc=$?"
T has-session 2>/dev/null && echo "server-after=running" || echo "server-after=gone"
echo "<<stop2"
harness_stop
echo "stop2>> rc=$?"
exit 0
