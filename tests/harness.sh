# harness.sh — drive flightdeck inside a private tmux server and check the
# panes. Sourced by tests/run.sh here and in the plugin repositories:
#
#   FLIGHTDECK=/path/to/flightdeck   (default: the directory above this file)
#   . "$FLIGHTDECK/tests/harness.sh"
#   harness_start [DIR] [FILE...]    start zsh in DIR, source deck.zsh then FILEs, run `deck`
#   t CMD [SECONDS]                  type CMD at the prompt and wait at most SECONDS
#                                    (default $HARNESS_T_TIMEOUT, 20) for it to finish;
#                                    past the bound: print FAIL, count it, send Ctrl-C, return 1
#   t_out CMD [SECONDS]              t, with CMD's stdout and stderr printed here, not in a pane
#   keys ...                         raw tmux send-keys
#   pane TITLE                       pane id by title (stdin stdout stderr man ...)
#   titles                           all pane titles in pane order, on one line
#   cap PANE [LINES]                 visible text of a pane, blank lines dropped, last LINES
#   wait_for PANE TEXT [SECONDS]     poll until the pane shows TEXT (grep -E)
#   wait_last PANE TEXT [SECONDS]    poll until the pane's last non-blank line matches (default 5 s)
#   wait_title PATTERN [SECONDS]     poll until `titles` matches PATTERN (default 5 s)
#   wait_until SECONDS CMD [ARG...]  re-run CMD every 0.25 s until it succeeds; its output is dropped
#   check DESC TEXT PATTERN          pass/fail: TEXT matches PATTERN (grep -E)
#   harness_stop                     tear down; exit status = number of failures
#
# Variables:
#   HARNESS_ROOT       a private mode-700 directory made when this file is sourced, removed
#                      by harness_stop or when the suite exits
#   HARNESS_ISOLATE=0  keep the caller's HOME, XDG_* and TMPDIR; by default they are
#                      pointed into HARNESS_ROOT, for the suite and the shell in the panes
#   HARNESS_KEEP=1     keep HARNESS_ROOT at the end and print its path
#   HARNESS_T_TIMEOUT  the default bound of t, in seconds (20)
#   HARNESS_PROMPT     the prompt pane's id, set by harness_start
#
# Needs tmux, zsh, bash, python3. Runs with LANG=C.UTF-8 and a bare zsh (-f),
# so nothing from the developer's dotfiles leaks in. A suite that sets its own
# EXIT trap after sourcing this file calls harness_stop from it.
FLIGHTDECK=${FLIGHTDECK:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
export FLIGHTDECK
_hs_sock=deckci-$$
_hs_fail=0 _hs_pass=0
_hs_calls=0 _hs_stopped=
# tmux reports the socket it made; this is where it puts one when it does not say.
_hs_sockpath=${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/$_hs_sock

# Every run gets its own root, so a suite never writes into the developer's
# home and two suites started together never share a file.
_hs_tmp=${TMPDIR:-/tmp}
_hs_root=$(mktemp -d "${_hs_tmp%/}/deckci.XXXXXX") || {
    echo "harness: cannot create a run root under $_hs_tmp" >&2; exit 1; }
HARNESS_ROOT=$_hs_root
HARNESS_PROMPT=
export HARNESS_ROOT
if [ "${HARNESS_ISOLATE:-1}" != 0 ]; then
    mkdir "$_hs_root/home" "$_hs_root/config" "$_hs_root/cache" "$_hs_root/data" \
        "$_hs_root/state" "$_hs_root/tmp" || exit 1
    # Exported before the tmux server starts, so the shell in the panes and
    # every helper it runs inherit the same values as the suite itself.
    export HOME=$_hs_root/home XDG_CONFIG_HOME=$_hs_root/config XDG_CACHE_HOME=$_hs_root/cache \
        XDG_DATA_HOME=$_hs_root/data XDG_STATE_HOME=$_hs_root/state TMPDIR=$_hs_root/tmp
fi

# Clean up on every way out, then run the EXIT trap the caller set before
# sourcing this file (the net and history suites remove their stores there).
_hs_caller_trap=$(trap -p EXIT)
_hs_run_trap() { [ "$1" = -- ] && shift; eval "$1"; }
_hs_on_exit() {
    [ -n "$_hs_stopped" ] || { _hs_stopped=1; _hs_teardown; }
    [ -z "$_hs_caller_trap" ] || eval "_hs_run_trap ${_hs_caller_trap#trap }"
}
trap _hs_on_exit EXIT

T() { tmux -L "$_hs_sock" "$@"; }
harness_start() {
    local dir=${1:-$PWD}; shift 2>/dev/null
    local src="source $FLIGHTDECK/deck.zsh"
    local f; for f in "$@"; do src="$src; source $f"; done
    local made
    T kill-server 2>/dev/null
    made=$(T -f /dev/null new-session -d -P -F '#{pane_id} #{socket_path}' -x 200 -y 45 -c "$dir" \
        "env LANG=C.UTF-8 LC_ALL=C.UTF-8 ZDOTDIR=/nonexistent zsh -f -i") || return 1
    HARNESS_PROMPT=${made%% *}
    [ -z "${made#* }" ] || _hs_sockpath=${made#* }
    T set-option -g status off
    t "$src"
    t "deck"
    wait_for "$(pane man)" '.' 2 >/dev/null 2>&1 || true
}
t() { _hs_type "$1" "$1" "${2:-}"; }
t_out() {
    local f rc
    f=$(mktemp "$_hs_root/out.XXXXXX") || return 1
    _hs_type "$1" "{ $1; } >$(printf %q "$f") 2>&1" "${2:-}"
    rc=$?
    cat "$f"; rm -f "$f"
    return $rc
}
# _hs_type LABEL LINE [SECONDS]: type LINE and wait for it, naming LABEL on failure.
# Each call waits on a channel of its own, so the signal of a line that
# finished after its bound can never end a later call.
_hs_type() {
    local label=$1 secs=${3:-${HARNESS_T_TIMEOUT:-20}} ch n w
    _hs_calls=$(( _hs_calls + 1 )); ch=ok.$_hs_calls
    T send-keys "$2; tmux -L $_hs_sock wait-for -S $ch" Enter 2>/dev/null || {
        _hs_t_fail "tmux server is gone: $label"; return 1; }
    tmux -L "$_hs_sock" wait-for "$ch" 2>/dev/null &
    w=$! n=$(( secs * 4 ))
    while kill -0 "$w" 2>/dev/null; do
        if [ "$n" -le 0 ]; then
            kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
            _hs_t_fail "no prompt within $secs s: $label"
            T send-keys -t "$HARNESS_PROMPT" C-c 2>/dev/null
            return 1
        fi
        n=$(( n - 1 ))
        sleep 0.25
    done
    wait "$w" || { _hs_t_fail "tmux server is gone: $label"; return 1; }
}
_hs_t_fail() {
    local got
    got=$(cap "$HARNESS_PROMPT" 3 2>/dev/null)
    _hs_fail=$(( _hs_fail + 1 ))
    echo "FAIL t: $1"
    echo "     got: $(printf '%s' "$got" | tr '\n' '|' | cut -c1-200)"
}
keys() { T send-keys "$@"; }
pane() { T list-panes -F '#{pane_id} #{pane_title}' | awk -v n="$1" '$2==n{print $1; exit}'; }
titles() { T list-panes -F '#{pane_title}' | paste -sd ' ' -; }
cap() { T capture-pane -p -t "$1" | grep -v '^$' | tail -"${2:-1}"; }
wait_for() {
    local p=$1 txt=$2 i n=$(( ${3:-5} * 4 ))
    for (( i = 0; i < n; i++ )); do
        T capture-pane -p -t "$p" 2>/dev/null | grep -qE -- "$txt" && return 0
        sleep 0.25
    done
    return 1
}
wait_until() {
    local n=$(( $1 * 4 )); shift
    while :; do
        "$@" >/dev/null 2>&1 && return 0
        [ "$n" -gt 0 ] || return 1
        n=$(( n - 1 ))
        sleep 0.25
    done
}
_hs_titles_match() { titles | grep -qE -- "$1"; }
wait_title() { wait_until "${2:-5}" _hs_titles_match "$1"; }
_hs_last_matches() { cap "$1" 1 | grep -qE -- "$2"; }
wait_last() { wait_until "${3:-5}" _hs_last_matches "$1" "$2"; }
check() {
    if printf '%s' "$2" | grep -qE -- "$3"; then _hs_pass=$(( _hs_pass + 1 )); echo "ok   $1"
    else _hs_fail=$(( _hs_fail + 1 )); echo "FAIL $1"; echo "     got: $(printf '%s' "$2" | tr '\n' '|' | cut -c1-200)"; echo "     want: $3"; fi
}
# Kill the server, remove its socket file (tmux leaves it behind) and the root.
_hs_teardown() {
    T kill-server 2>/dev/null
    rm -f "$_hs_sockpath"
    if [ "${HARNESS_KEEP:-}" = 1 ]; then echo "kept $_hs_root"
    else rm -rf "$_hs_root"; fi
}
harness_stop() {
    if [ -z "$_hs_stopped" ]; then
        _hs_stopped=1
        echo "$_hs_pass passed, $_hs_fail failed"
        _hs_teardown
    fi
    return $_hs_fail
}
