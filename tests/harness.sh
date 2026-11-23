# harness.sh — drive flightdeck inside a private tmux server and check the
# panes. Sourced by tests/run.sh here and in the plugin repositories:
#
#   FLIGHTDECK=/path/to/flightdeck   (default: the directory above this file)
#   . "$FLIGHTDECK/tests/harness.sh"
#   harness_start [DIR] [FILE...]    start zsh in DIR, source deck.zsh then FILEs, run `deck`;
#                                    defines _hs_ok in that shell, which t needs (a shell started
#                                    inside it does not have it, so t cannot be used there)
#   t CMD [SECONDS]                  type CMD at the prompt and wait at most SECONDS
#                                    (default $HARNESS_T_TIMEOUT, 20) for it to finish;
#                                    past the bound: print FAIL, count it, send Ctrl-C, return 1
#   t_out CMD [SECONDS]              t, with CMD's stdout and stderr printed here, not in a pane;
#                                    safe inside $( ): check "…" "$(t_out CMD)" PATTERN counts a
#                                    timeout as a failure, and its FAIL lines are not captured
#   T ARGS...                        tmux, on this suite's private server
#   keys ...                         raw tmux send-keys
#   pane TITLE                       pane id by title (stdin stdout stderr man ...)
#   titles                           all pane titles in pane order, on one line
#   cap PANE [LINES]                 visible text of a pane, blank lines dropped, last LINES
#   wait_for PANE TEXT [SECONDS]     poll until the pane shows TEXT (grep -E)
#   wait_last PANE TEXT [SECONDS]    poll until the pane's last non-blank line matches (default 5 s)
#   wait_title PATTERN [SECONDS]     poll until `titles` matches PATTERN (default 5 s)
#   wait_until SECONDS CMD [ARG...]  re-run CMD every 0.25 s until it succeeds; its output is dropped
#   check DESC TEXT PATTERN          pass/fail: TEXT matches PATTERN (grep -E)
#   harness_stop                     tear down and put back the caller's HOME, XDG_* and TMPDIR;
#                                    exit status = number of failures
#   harness_suites DIR               run each DIR/*.sh as its own process, with FLIGHTDECK and the
#                                    caller's original environment, after a "--- suites/NAME.sh"
#                                    line; returns how many exited non-zero. Works before or
#                                    after harness_stop. A module runner ends with:
#                                      harness_stop; rc=$?
#                                      harness_suites "$(dirname "$0")/suites"; exit $(( rc + $? ))
#
# SECONDS may be fractional; it is rounded up to whole seconds. Anything else
# that is not a number is refused with a message (t also counts a failure).
# Descriptor 9 is taken: it is the suite's stdout as it was when this file was
# sourced, and t prints its FAIL lines there.
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
_hs_stopped=
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
# t reports a failure in the suite's own output even when it is called inside
# $( ), where stdout is the captured text. bash 3.2 cannot pick a free
# descriptor, so the number is fixed (and documented above).
exec 9>&1
_hs_isolated=
if [ "${HARNESS_ISOLATE:-1}" != 0 ]; then
    # Remember the caller's values, and whether each was set at all, so that
    # harness_stop and harness_suites can put them back exactly.
    for _hs_v in HOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME TMPDIR; do
        eval "_hs_was_$_hs_v=\${$_hs_v+1} _hs_old_$_hs_v=\${$_hs_v-}"
    done
    _hs_isolated=1
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
# Put back the caller's HOME, XDG_* and TMPDIR, unset where they were unset.
_hs_restore_env() {
    [ -n "$_hs_isolated" ] || return 0
    local v
    for v in HOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME TMPDIR; do
        if eval "[ -n \"\$_hs_was_$v\" ]"; then eval "export $v=\"\$_hs_old_$v\""
        else unset "$v"; fi
    done
}
# _hs_whole SECONDS: set _hs_s to SECONDS rounded up to whole seconds, or say
# what is wrong and return 2. The polling loops count quarter seconds in shell
# arithmetic, which has no fractions.
_hs_whole() {
    case $1 in
        ''|.|*[!0-9.]*|*.*.*) echo "harness: not a number of seconds: $1" >&2; return 2 ;;
        *.*) local i=${1%%.*} f=${1#*.}; f=${f//0/}
             _hs_s=$(( 10#${i:-0} + (${#f} > 0) )) ;;
        *) _hs_s=$(( 10#$1 )) ;;
    esac
}

T() { tmux -L "$_hs_sock" "$@"; }
harness_start() {
    local dir=${1:-$PWD}; shift 2>/dev/null
    # The first line defines _hs_ok, which every line t types ends with (see
    # _hs_type). It is typed before deck.zsh is sourced, so no follower runs yet.
    local src="_hs_ok() { tmux -L $_hs_sock wait-for -S ok.\${1#-} }; source $FLIGHTDECK/deck.zsh"
    local f; for f in "$@"; do src="$src; source $f"; done
    local made
    T kill-server 2>/dev/null
    # Descriptor 9 is closed for the server, which outlives this call: a pipe
    # held open there would keep a reader of the suite's output waiting.
    made=$(T -f /dev/null new-session -d -P -F '#{pane_id} #{socket_path}' -x 200 -y 45 -c "$dir" \
        "env LANG=C.UTF-8 LC_ALL=C.UTF-8 ZDOTDIR=/nonexistent zsh -f -i" 9>&-) || return 1
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
# The tail typed after LINE is "; _hs_ok -N", not the tmux command itself:
# the man follower reacts to every keystroke, and a typed "tmux ... -S ok.N"
# made it repaint the tmux manual several times per line (1.3-1.5 s of every
# t under load). _hs_ok has no manual page, and the leading dash keeps N from
# being read as a subcommand, so after the first line the follower's lookups
# for the tail are all cached and it forks nothing.
# The call number and the failures of t live in files under the root, not in
# shell variables: a call inside $( ) runs in a subshell, whose variables are
# gone when it ends, and the next call must neither reuse its channel nor
# lose its failure. Calls are one after another, so the read-then-write of
# the call number needs no lock.
_hs_type() {
    local label=$1 secs=${3:-${HARNESS_T_TIMEOUT:-20}} call=0 ch n w
    _hs_whole "$secs" || { _hs_count_fail; return 2; }
    [ -r "$_hs_root/calls" ] && read -r call <"$_hs_root/calls"
    call=$(( call + 1 )); echo "$call" 2>/dev/null >"$_hs_root/calls"
    ch=ok.$call
    T send-keys "$2; _hs_ok -$call" Enter 2>/dev/null || {
        _hs_t_fail "tmux server is gone: $label"; return 1; }
    tmux -L "$_hs_sock" wait-for "$ch" 2>/dev/null 9>&- &
    w=$! n=$(( _hs_s * 4 ))
    while kill -0 "$w" 2>/dev/null; do
        if [ "$n" -le 0 ]; then
            kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
            _hs_t_fail "no prompt within $secs s: $label"
            T send-keys -t "$HARNESS_PROMPT" C-c 2>/dev/null
            return 1
        fi
        n=$(( n - 1 ))
        sleep 0.25   # sleep: polling interval of the bound
    done
    wait "$w" || { _hs_t_fail "tmux server is gone: $label"; return 1; }
}
_hs_t_fail() {
    local got
    got=$(cap "$HARNESS_PROMPT" 3 2>/dev/null)
    _hs_count_fail
    { echo "FAIL t: $1"
      echo "     got: $(printf '%s' "$got" | tr '\n' '|' | cut -c1-200)"; } >&9
}
# One line per failure of t; harness_stop adds them to the failed checks.
_hs_count_fail() { echo x 2>/dev/null >>"$_hs_root/failed"; }
keys() { T send-keys "$@"; }
pane() { T list-panes -F '#{pane_id} #{pane_title}' | awk -v n="$1" '$2==n{print $1; exit}'; }
titles() { T list-panes -F '#{pane_title}' | paste -sd ' ' -; }
cap() { T capture-pane -p -t "$1" | grep -v '^$' | tail -"${2:-1}"; }
wait_for() {
    local p=$1 txt=$2 i n
    _hs_whole "${3:-5}" || return 2
    n=$(( _hs_s * 4 ))
    for (( i = 0; i < n; i++ )); do
        T capture-pane -p -t "$p" 2>/dev/null | grep -qE -- "$txt" && return 0
        sleep 0.25   # sleep: polling interval
    done
    return 1
}
wait_until() {
    local n
    _hs_whole "$1" || return 2
    n=$(( _hs_s * 4 )); shift
    while :; do
        "$@" >/dev/null 2>&1 && return 0
        [ "$n" -gt 0 ] || return 1
        n=$(( n - 1 ))
        sleep 0.25   # sleep: polling interval
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
# Kill the server, remove its socket file (tmux leaves it behind) and the
# root, and point HOME, XDG_* and TMPDIR back where they were: anything the
# suite starts afterwards would otherwise find them inside a removed directory.
_hs_teardown() {
    T kill-server 2>/dev/null
    rm -f "$_hs_sockpath"
    if [ "${HARNESS_KEEP:-}" = 1 ]; then echo "kept $_hs_root"
    else rm -rf "$_hs_root"; fi
    _hs_restore_env
}
harness_stop() {
    if [ -z "$_hs_stopped" ]; then
        _hs_stopped=1
        [ -f "$_hs_root/failed" ] && _hs_fail=$(( _hs_fail + $(wc -l <"$_hs_root/failed") ))
        echo "$_hs_pass passed, $_hs_fail failed"
        _hs_teardown
    fi
    return $_hs_fail
}
harness_suites() {
    local dir=${1%/} f bad=0
    for f in "$dir"/*.sh; do
        [ -f "$f" ] || continue
        echo "--- ${dir##*/}/${f##*/}"
        # A subshell, so that putting the caller's environment back for the
        # child leaves this suite's own, still isolated, environment alone.
        ( _hs_restore_env; unset HARNESS_ROOT; export FLIGHTDECK; exec "$BASH" "$f" ) || bad=$(( bad + 1 ))
    done
    return $bad
}
