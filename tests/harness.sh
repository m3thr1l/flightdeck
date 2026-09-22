# harness.sh — drive flightdeck inside a private tmux server and check the
# panes. Sourced by tests/run.sh here and in the plugin repositories:
#
#   FLIGHTDECK=/path/to/flightdeck   (default: the directory above this file)
#   . "$FLIGHTDECK/tests/harness.sh"
#   harness_start [DIR] [FILE...]    start zsh in DIR, source deck.zsh then FILEs, run `deck`
#   t CMD                            type CMD at the prompt and wait for it to finish
#   keys ...                         raw tmux send-keys
#   pane TITLE                       pane id by title (stdin stdout stderr man ...)
#   cap PANE [LINES]                 visible text of a pane, blank lines dropped, last LINES
#   wait_for PANE TEXT [SECONDS]     poll until the pane shows TEXT (grep -E)
#   check DESC TEXT PATTERN          pass/fail: TEXT matches PATTERN (grep -E)
#   harness_stop                     tear down; exit status = number of failures
#
# Needs tmux, zsh, bash, python3. Runs with LANG=C.UTF-8 and a bare zsh (-f),
# so nothing from the developer's dotfiles leaks in.
FLIGHTDECK=${FLIGHTDECK:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
export FLIGHTDECK
_hs_sock=deckci-$$
_hs_fail=0 _hs_pass=0

T() { tmux -L "$_hs_sock" "$@"; }
harness_start() {
    local dir=${1:-$PWD}; shift 2>/dev/null
    local src="source $FLIGHTDECK/deck.zsh"
    local f; for f in "$@"; do src="$src; source $f"; done
    T kill-server 2>/dev/null
    T -f /dev/null new-session -d -x 200 -y 45 -c "$dir" \
        "env LANG=C.UTF-8 LC_ALL=C.UTF-8 ZDOTDIR=/nonexistent zsh -f -i" || return 1
    T set-option -g status off
    t "$src"
    t "deck"
    wait_for "$(pane man)" '.' 2 >/dev/null 2>&1 || true
}
t() { T send-keys "$1; tmux -L $_hs_sock wait-for -S ok" Enter; T wait-for ok; }
keys() { T send-keys "$@"; }
pane() { T list-panes -F '#{pane_id} #{pane_title}' | awk -v n="$1" '$2==n{print $1; exit}'; }
cap() { T capture-pane -p -t "$1" | grep -v '^$' | tail -"${2:-1}"; }
wait_for() {
    local p=$1 txt=$2 i n=$(( ${3:-5} * 4 ))
    for (( i = 0; i < n; i++ )); do
        T capture-pane -p -t "$p" 2>/dev/null | grep -qE -- "$txt" && return 0
        sleep 0.25
    done
    return 1
}
check() {
    if printf '%s' "$2" | grep -qE -- "$3"; then _hs_pass=$(( _hs_pass + 1 )); echo "ok   $1"
    else _hs_fail=$(( _hs_fail + 1 )); echo "FAIL $1"; echo "     got: $(printf '%s' "$2" | tr '\n' '|' | cut -c1-200)"; echo "     want: $3"; fi
}
harness_stop() {
    T kill-server 2>/dev/null
    echo "$_hs_pass passed, $_hs_fail failed"
    return $_hs_fail
}
