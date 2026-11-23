#!/usr/bin/env bash
# isolation.sh — report HARNESS_ROOT, its mode, and HOME, XDG_* and TMPDIR as
# the suite sees them and as the shell in the panes sees them; then type a
# line so that the man follower writes its cache.
set -u
. "$FLIGHTDECK/tests/harness.sh"
echo "root=$HARNESS_ROOT"
echo "mode=$(ls -ld "$HARNESS_ROOT" 2>/dev/null | cut -c1-10)"
printf 'suite %s\n' "HOME=${HOME-}" "XDG_CONFIG_HOME=${XDG_CONFIG_HOME-}" "XDG_CACHE_HOME=${XDG_CACHE_HOME-}" \
    "XDG_DATA_HOME=${XDG_DATA_HOME-}" "XDG_STATE_HOME=${XDG_STATE_HOME-}" "TMPDIR=${TMPDIR-}"
harness_start
t_out 'printf "pane %s\n" "HOME=$HOME" "XDG_CONFIG_HOME=$XDG_CONFIG_HOME" "XDG_CACHE_HOME=$XDG_CACHE_HOME" "XDG_DATA_HOME=$XDG_DATA_HOME" "XDG_STATE_HOME=$XDG_STATE_HOME" "TMPDIR=$TMPDIR"'
keys "echo x"
wait_for "$(pane man)" ' echo ' 6
echo "man-shown=$?"
keys C-u
harness_stop
