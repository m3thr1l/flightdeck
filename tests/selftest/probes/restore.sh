#!/usr/bin/env bash
# restore.sh — HOME, XDG_* and TMPDIR before sourcing the harness, while it
# runs, and after harness_stop ("<unset>" for a variable that is not set).
set -u
show() {
    local v out=$1
    for v in HOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME TMPDIR; do
        out="$out $v=$(eval "printf '%s' \"\${$v-<unset>}\"")"
    done
    echo "$out"
}
show before
. "$FLIGHTDECK/tests/harness.sh"
show during
harness_stop >/dev/null
show after
