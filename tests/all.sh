#!/usr/bin/env bash
# Run every suite, as CI does: the syntax step, the harness self-test, the
# core tests, the suites in tests/suites, then each module's. The exit status
# is the number of suites that failed.
cd "$(dirname "$0")/.." || exit 1
fail=0
run() {
    echo "=== $1"
    shift
    "$@" || fail=$(( fail + 1 ))
}
run tests/syntax.sh tests/syntax.sh
run tests/selftest tests/selftest/run.sh
run tests/run.sh tests/run.sh
for s in tests/suites/*.sh; do
    [ -f "$s" ] || continue
    run "$s" "$s"
done
for m in modules/*/; do
    run "${m%/}" env FLIGHTDECK="$PWD" "$m/tests/run.sh"
done
echo "=== $fail suite(s) failed"
exit $fail
