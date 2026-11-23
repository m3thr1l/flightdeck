#!/usr/bin/env bash
# deck history tests: a command run inside the deck is recorded with its output.
set -u
cd "$(dirname "$0")/.."
zsh -n history.zsh && python3 -c "import ast; ast.parse(open('deck-history').read())" || exit 1
echo "ok   syntax"
export MYSTORY_DIR=$(mktemp -d); trap 'rm -rf "$MYSTORY_DIR"' EXIT
. "${FLIGHTDECK:-$(cd ../.. && pwd)}/tests/harness.sh"
harness_start "$PWD" "$PWD/history.zsh"
OUT=$(pane stdout)
t "echo MYSTORY-MARK-$$; echo to-stderr >&2" 60
_hist_ready() {
    ./deck-history "MYSTORY-MARK-$$" | grep -q "MYSTORY-MARK-$$" &&
        ./deck-history -o MYSTORY-MARK | grep -q "MYSTORY-MARK-$$"
}
wait_until 15 _hist_ready
check "command recorded" "$(t_out "deck history MYSTORY-MARK-$$")" "MYSTORY-MARK-$$"
check "output recorded" "$(t_out "deck history -o MYSTORY-MARK")" "MYSTORY-MARK-$$"
harness_stop; rc=$?
harness_suites tests/suites; exit $(( rc + $? ))
