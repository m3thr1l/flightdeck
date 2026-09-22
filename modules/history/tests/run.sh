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
t "echo MYSTORY-MARK-$$; echo to-stderr >&2"
sleep 3
t "deck history MYSTORY-MARK-$$ >/tmp/deckci.$$ 2>&1"
check "command recorded" "$(cat /tmp/deckci.$$)" "MYSTORY-MARK-$$"
t "deck history -o MYSTORY-MARK >/tmp/deckci.$$ 2>&1"
check "output recorded" "$(cat /tmp/deckci.$$)" "MYSTORY-MARK-$$"
rm -f /tmp/deckci.$$
harness_stop
