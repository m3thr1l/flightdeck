#!/usr/bin/env bash
# Run the core tests and then every module's, as CI does.
cd "$(dirname "$0")/.." || exit 1
fail=0
tests/run.sh || fail=$(( fail + 1 ))
for m in modules/*/; do
    echo "=== ${m%/}"
    FLIGHTDECK=$PWD "$m/tests/run.sh" || fail=$(( fail + 1 ))
done
echo "=== $fail suite(s) failed"
exit $fail
