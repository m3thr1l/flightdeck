#!/usr/bin/env bash
# flightdeck-net tests: inventory, parsers, the net follower, automatic ingest.
set -u
cd "$(dirname "$0")/.."
zsh -n net.zsh && sh -n install.sh && python3 -c "import ast; ast.parse(open('deck-hosts').read())" || exit 1
echo "ok   syntax"
export DECK_NET_DIR=$(mktemp -d)
trap 'rm -rf "$DECK_NET_DIR"' EXIT
./deck-hosts ingest nmap tests/nmap.txt >/dev/null && ./deck-hosts ingest tests/arp.txt >/dev/null
. "${FLIGHTDECK:-$(cd ../flightdeck && pwd)}/tests/harness.sh"
check "list" "$(./deck-hosts list | tr '\n' '|')" '10\.0\.0\.40.*printer\.lan.*\|.*10\.0\.0\.1 .*router\.lan.*3 open'
check "show by name" "$(./deck-hosts show router.lan | tr '\n' '|')" 'Ubiquiti.*22/tcp.*ssh.*OpenSSH'
check "show by mac" "$(./deck-hosts show aa:bb:cc:dd:ee:ff | head -1)" '^10\.0\.0\.23'
out=$(./deck-hosts show 10.9.9.9 2>&1); rc=$?
check "unknown host" "$out rc=$rc" 'unknown host rc=1'

harness_start "$PWD" "$PWD/net.zsh"
t "deck mode net"; M=$(pane net)
keys "ssh 10.0.0.40"; wait_for "$M" 'printer' 6
check "card for the address under the cursor" "$(T capture-pane -p -t "$M" | head -3 | tr '\n' '|')" 'host  10\.0\.0\.40\|10\.0\.0\.40  printer\.lan\|.*mac'
keys " -p"; wait_for "$M" '^ ssh ' 6
check "man page when the cursor is on an option" "$(T capture-pane -p -t "$M" | head -1)" '^ ssh  -p'
keys " 10.0.0.0/24"; wait_for "$M" 'subnet' 6
check "subnet view" "$(T capture-pane -p -t "$M" | head -1)" 'subnet  10\.0\.0\.0/24  \(3 hosts\)'
keys C-u
t "nmap() { command cat tests/nmap.txt }"
t "nmap -sV 10.0.0.1"; sleep 1.5
check "automatic ingest of a tool run" "$(./deck-hosts show 10.0.0.1 | tr '\n' '|')" 'Ubiquiti Networks.*80/tcp'
keys "ping router.lan"; wait_for "$M" 'host  10\.0\.0\.1' 6
check "card by name" "$(T capture-pane -p -t "$M" | head -1)" 'host  10\.0\.0\.1$'
keys C-u
harness_stop
