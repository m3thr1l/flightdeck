#!/usr/bin/env bash
# The harness's own tests: tests/selftest/run.sh
#
# Runs each probe suite in tests/selftest/probes/ as a child process with a
# fresh empty HOME and TMPDIR and a deadline of its own, then checks what the
# probe printed, its exit status, its time and what it left behind; and runs
# tests/syntax.sh against small trees built here. Needs tmux, zsh, python3.
# Exit status: the number of failed checks.
set -u
cd "$(dirname "$0")/../.." || exit 1
FLIGHTDECK=$PWD
export FLIGHTDECK
PROBES=$PWD/tests/selftest/probes
SYNTAX=$PWD/tests/syntax.sh
unset HARNESS_ROOT HARNESS_ISOLATE HARNESS_KEEP HARNESS_T_TIMEOUT HARNESS_PROMPT
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/deck-selftest.XXXXXX") || exit 1
trap 'rm -rf "$SCRATCH"' EXIT
SOCKDIR=${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)
fail=0 pass=0

check() {
    if printf '%s' "$2" | grep -qE -- "$3"; then pass=$(( pass + 1 )); echo "ok   $1"
    else fail=$(( fail + 1 )); echo "FAIL $1"; echo "     got: $(printf '%s' "$2" | tr '\n' '|' | cut -c1-300)"; echo "     want: $3"; fi
}

newdir() { P=$(mktemp -d "$SCRATCH/p.XXXXXX") && mkdir "$P/home" "$P/tmp" "$P/work"; }
launch() {
    local out=$1; shift
    (
        cd "$P/work" || exit 97
        export HOME="$P/home" TMPDIR="$P/tmp"
        unset XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME
        while [ $# -gt 0 ] && [ "$1" != -- ]; do export "$1"; shift; done
        shift
        exec "$BASH" "$@"
    ) >"$out" 2>&1 &
}
await() {
    local pid=$1 limit=$2 start=$SECONDS
    while kill -0 "$pid" 2>/dev/null; do
        if [ $(( SECONDS - start )) -ge "$limit" ]; then
            pkill -TERM -P "$pid" 2>/dev/null
            kill -TERM "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            RC=killed END=$(date +%s) STATE="killed at its ${limit} s deadline: the harness hung"
            return
        fi
        sleep 0.25   # sleep: poll interval while a probe runs under its deadline
    done
    wait "$pid"
    RC=$? END=$(date +%s) STATE="exit $RC after $(( SECONDS - start )) s"
}
reap() {
    local pid
    for pid; do
        tmux -L "deckci-$pid" kill-server 2>/dev/null
        rm -f "$SOCKDIR/deckci-$pid"
    done
}

val() { awk -v k="$2=" 'index($0, k) == 1 { print substr($0, length(k) + 1); exit }' "$1"; }
line() { awk -v p="$2" 'index($0, p) == 1 { print; exit }' "$1"; }
between() { awk -v s="<<$2" -v e="$2>>" 'index($0, e) == 1 { f = 0 } f { print } $0 == s { f = 1 }' "$1"; }
has_line() { grep -Fxq -- "$2" "$1" && echo present || echo absent; }
after_line() { grep -A1 -Fx -- "$2" "$1" | sed -n 2p; }
same() { [ -n "$1" ] && [ "$1" = "$2" ] && echo same || echo "differ: '$1' vs '$2'"; }
distinct() { [ -n "$1" ] && [ -n "$2" ] && [ "$1" != "$2" ] && echo distinct || echo "not distinct: '$1' '$2'"; }
inside() { [ -n "$1" ] || { echo "no root"; return; }; case $2 in "$1"/?*) echo inside ;; *) echo "outside: '$2'" ;; esac; }
sock_state() { if [ -z "$1" ]; then echo socket=unknown; elif [ -e "$1" ]; then echo socket=left; else echo socket=gone; fi; }
root_state() { if [ -z "$1" ]; then echo root=unset; elif [ -e "$1" ]; then echo root=left; else echo root=gone; fi; }
server_state() { tmux -L "deckci-$1" has-session 2>/dev/null && echo server=running || echo server=gone; }
tree_state() {
    if [ -z "$1" ] || [ ! -e "$1" ]; then echo absent
    elif [ -z "$(ls -A "$1")" ]; then echo empty
    else echo "holds: $(ls -A "$1" | tr '\n' ' ')"; fi
}

newdir; GOOD=$P/out; launch "$GOOD" -- "$PROBES/line.sh" "echo x" 3; pid=$!
await "$pid" 10; GOOD_RC=$RC
check "H-02 a suite leaves neither its tmux socket nor a run root in TMPDIR" \
    "$(sock_state "$(val "$GOOD" sock)") tmpdir=$(tree_state "$P/tmp")" '^socket=gone tmpdir=empty$'
reap "$pid"

newdir; BAD=$P/out; launch "$BAD" -- "$PROBES/line.sh" "echo [x]" 3; pid=$!
await "$pid" 10; BAD_RC=$RC
before=$(val "$BAD" before-t)
check "H-03 a suite whose line never returns ends within 5 s of typing it" \
    "after-line=$(( END - ${before:-0} ))s [$STATE]" '^after-line=[0-5]s \[exit [0-9]+ '
check "H-03 the suite prints FAIL t: no prompt within 3 s: echo [x]" \
    "$(has_line "$BAD" 'FAIL t: no prompt within 3 s: echo [x]') [$STATE]" '^present '
check "H-03 the FAIL line is followed by the prompt pane's last lines" \
    "$(after_line "$BAD" 'FAIL t: no prompt within 3 s: echo [x]') [$STATE]" '^     got: .*echo \[x\]'
check "H-03 the suite still runs its later checks" \
    "$(has_line "$BAD" 'ok   H-03 probe: a later check still runs') [$STATE]" '^present '
check "H-03 the suite exits non-zero, where its valid-line twin exits 0 and prints no FAIL" \
    "bad=$BAD_RC good=$GOOD_RC fails-in-good=$(grep -c '^FAIL' "$GOOD") [$STATE]" '^bad=[1-9][0-9]* good=0 fails-in-good=0 '
reap "$pid"

newdir; TO=$P/out; launch "$TO" -- "$PROBES/line.sh" "echo [x]" 2; pid=$!
await "$pid" 10
check "H-15 a line that never returns: t returns 1 after its 2 s, within 4 s" \
    "$(line "$TO" 't>>') [$STATE]" '^t>> rc=1 elapsed=[234] '
check "H-15 t prints FAIL t: no prompt within 2 s: echo [x]" \
    "$(has_line "$TO" 'FAIL t: no prompt within 2 s: echo [x]') [$STATE]" '^present '
check "H-15 the timed-out t counts one failure" \
    "summary=$(grep -E '^[0-9]+ passed, [0-9]+ failed$' "$TO") rc=$RC [$STATE]" '^summary=1 passed, 1 failed rc=1 '
check "H-15 a line that returns: t returns 0 and prints nothing, where its hung twin returned 1" \
    "returned: $(line "$GOOD" 't>>') printed:'$(between "$GOOD" t)' hung: $(line "$TO" 't>>')" \
    "^returned: t>> rc=0 elapsed=[0-9]+ printed:'' hung: t>> rc=1 "
reap "$pid"

newdir; DEF=$P/out; launch "$DEF" HARNESS_T_TIMEOUT=2 -- "$PROBES/line.sh" "echo [x]" ""; pid=$!
await "$pid" 10
check "H-15 without SECONDS, t's bound is HARNESS_T_TIMEOUT" \
    "$(has_line "$DEF" 'FAIL t: no prompt within 2 s: echo [x]') $(line "$DEF" 't>>') [$STATE]" '^present t>> rc=1 elapsed=[234] '
reap "$pid"

newdir; OUT=$P/out; launch "$OUT" -- "$PROBES/hang-then-next.sh"; pid=$!
await "$pid" 12
check "H-16 after a timed-out t the suite goes on: the next t returns 0 and NEXT-42 shows in stdout" \
    "$(line "$OUT" first-rc) $(line "$OUT" next-rc) $(line "$OUT" next-shown) [$STATE]" '^first-rc=1 next-rc=0 next-shown=0 '
reap "$pid"

newdir; OUT=$P/out; launch "$OUT" -- "$PROBES/late-signal.sh"; pid=$!
await "$pid" 20
check "H-16 a late signal never ends a later call: after the timed-out call, t \"sleep 4\" 10 takes at least 4 s" \
    "$(line "$OUT" first-rc) $(line "$OUT" second-rc) $(line "$OUT" late-shown) [$STATE]" \
    '^first-rc=1 second-rc=0 second-elapsed=([4-9]|1[0-2]) late-shown=0 '
reap "$pid"

newdir; OUT=$P/out; launch "$OUT" -- "$PROBES/dead-server.sh"; pid=$!
await "$pid" 10
check "H-17 with the server gone, t returns 1 within 2 s and prints FAIL t: tmux server is gone: echo x" \
    "$(line "$OUT" 't>>') $(has_line "$OUT" 'FAIL t: tmux server is gone: echo x') [$STATE]" '^t>> rc=1 elapsed=[0-2] present '
check "H-17 the dead-server failure counts in the summary and the exit status" \
    "summary=$(grep -E '^[0-9]+ passed, [0-9]+ failed$' "$OUT") rc=$RC" '^summary=0 passed, 1 failed rc=1$'
reap "$pid"

tree_clean() {
    mkdir -p "$1/tests/sub" "$1/modules/m/tests"
    printf '%s\n' 'f() { emulate -L zsh; for i ( a b ) { print -r -- $i } }' 'sleep 1; ls /tmp/' >"$1/x.zsh"
    printf '%s\n' 'a=( 1 2 ); [[ -n ${a[0]} ]] && echo "$a"' >"$1/deck.bash"
    printf '%s\n' '#!/usr/bin/env bash' 'echo man' >"$1/deck-man"
    printf '%s\n' '#!/usr/bin/env bash' 'a=( 1 2 ); echo "${a[1]}"' >"$1/tool-bash"
    printf '%s\n' '#!/bin/sh' 'if [ -n "$1" ]; then echo "$1"; fi' >"$1/tool-sh"
    printf '%s\n' '#!/usr/bin/env python3' 'def f(x):' '    return x' >"$1/tool-py"
    printf '%s\n' 'echo helper' >"$1/tests/sub/helper.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo suite' 'sleep 1   # sleep: a reason' >"$1/tests/run.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo module' >"$1/modules/m/tests/run.sh"
    printf '%s\n' 'notes' >"$1/README.md"
    printf '%s\n' 'data' >"$1/data.txt"
    chmod +x "$1/deck-man" "$1/tool-bash" "$1/tool-sh" "$1/tool-py" "$1/tests/run.sh" "$1/modules/m/tests/run.sh"
}
fails_for() { grep '^FAIL' "$1" | grep -F -- "$2"; }

newdir; tree_clean "$P/tree"; CLEAN=$P/out; launch "$CLEAN" -- "$SYNTAX" "$P/tree"; pid=$!
await "$pid" 30
check "H-07 a clean tree passes the syntax step" \
    "rc=$RC fails=$(grep -c '^FAIL' "$CLEAN") $(line "$CLEAN" 'ok   syntax')" '^rc=0 fails=0 ok   syntax \(.*\)$'

newdir; tree_clean "$P/tree"; OUT=$P/out
printf '%s\n' 'if [[ -n x ]]; then' >"$P/tree/x.zsh"
printf '%s\n' 'if true; then echo x' >"$P/tree/deck.bash"
printf '%s\n' '#!/usr/bin/env bash' 'if true; then echo x' >"$P/tree/tool-bash"
printf '%s\n' 'if true; then echo x' >"$P/tree/tests/sub/helper.sh"
printf '%s\n' '#!/bin/sh' 'if true; then echo x' >"$P/tree/tool-sh"
printf '%s\n' '#!/usr/bin/env python3' 'def f(:' >"$P/tree/tool-py"
launch "$OUT" -- "$SYNTAX" "$P/tree"; pid=$!
await "$pid" 30
check "H-07 a syntax error in a .zsh file fails as zsh, naming the file" \
    "count=$(fails_for "$OUT" x.zsh | wc -l | tr -d ' ') $(fails_for "$OUT" x.zsh)" '^count=1 FAIL syntax zsh x\.zsh: '
check "H-07 a syntax error in deck.bash fails as bash, naming the file" \
    "count=$(fails_for "$OUT" deck.bash | wc -l | tr -d ' ') $(fails_for "$OUT" deck.bash)" '^count=1 FAIL syntax bash deck\.bash: '
check "H-07 a syntax error in a #!...bash file fails as bash, naming the file" \
    "count=$(fails_for "$OUT" tool-bash | wc -l | tr -d ' ') $(fails_for "$OUT" tool-bash)" '^count=1 FAIL syntax bash tool-bash: '
check "H-07 a syntax error in a tests/**/*.sh file with no #! line fails as bash, naming the file" \
    "count=$(fails_for "$OUT" helper.sh | wc -l | tr -d ' ') $(fails_for "$OUT" helper.sh)" '^count=1 FAIL syntax bash tests/sub/helper\.sh: '
check "H-07 a syntax error in a #!/bin/sh file fails as sh, naming the file" \
    "count=$(fails_for "$OUT" tool-sh | wc -l | tr -d ' ') $(fails_for "$OUT" tool-sh)" '^count=1 FAIL syntax sh tool-sh: '
check "H-07 a syntax error in a #!...python3 file fails as python, naming the file" \
    "count=$(fails_for "$OUT" tool-py | wc -l | tr -d ' ') $(fails_for "$OUT" tool-py)" '^count=1 FAIL syntax python3 tool-py: '
check "H-07 the step's exit status is the number of failing files" \
    "rc=$RC fails=$(grep -c '^FAIL' "$OUT")" '^rc=6 fails=6$'

newdir; tree_clean "$P/tree"; OUT=$P/out
printf '%s\n' '#!/usr/bin/env python3' 'match x:' '    case 1:' '        pass' >"$P/tree/tool-py"
launch "$OUT" -- "$SYNTAX" "$P/tree"; pid=$!
await "$pid" 30
check "H-07 a #!...python3 file is parsed at the 3.8 grammar (match fails)" \
    "rc=$RC $(fails_for "$OUT" tool-py)" '^rc=1 FAIL syntax python3 tool-py: '

newdir; tree_clean "$P/tree"; OUT=$P/out
printf '%s\n' 'hello' >"$P/tree/mystery"
printf '%s\n' '#!/usr/bin/env perl' 'print "x";' >"$P/tree/runner"
chmod +x "$P/tree/mystery" "$P/tree/runner"
launch "$OUT" -- "$SYNTAX" "$P/tree"; pid=$!
await "$pid" 30
check "H-08 an executable file with no known extension or #! line fails as unclassified" \
    "$(fails_for "$OUT" mystery)" '^FAIL syntax unclassified mystery: no known extension or #! line$'
check "H-08 an executable file with an unknown #! line fails as unclassified" \
    "$(fails_for "$OUT" runner)" '^FAIL syntax unclassified runner: no known extension or #! line$'
check "H-08 only the two unclassified executables fail (README.md and data.txt are not executable)" \
    "rc=$RC fails=$(grep -c '^FAIL' "$OUT")" '^rc=2 fails=2$'

if command -v dash >/dev/null 2>&1; then
    check "H-09 with dash installed, the clean tree's summary says dash: checked" \
        "$(line "$CLEAN" 'ok   syntax')" 'dash: checked\)$'
    newdir; tree_clean "$P/tree"; OUT=$P/out
    printf '%s\n' '#!/bin/sh' 'cat <<< x' >"$P/tree/tool-sh"
    launch "$OUT" -- "$SYNTAX" "$P/tree"; pid=$!
    await "$pid" 30
    check "H-09 a bashism (cat <<< x) in a #!/bin/sh file fails when dash is installed" \
        "rc=$RC $(fails_for "$OUT" tool-sh)" '^rc=1 FAIL syntax (sh|dash) tool-sh: '
else echo "skip H-09 bashism case (dash not installed)"; fi

newdir; tree_clean "$P/tree"; OUT=$P/out; mkdir "$P/bin"
oldifs=$IFS; IFS=:
for d in $PATH; do [ -d "$d" ] && ln -s "$d"/* "$P/bin/" 2>/dev/null; done
IFS=$oldifs
rm -f "$P/bin/dash"
launch "$OUT" PATH="$P/bin" -- "$SYNTAX" "$P/tree"; pid=$!
await "$pid" 30
check "H-09 without dash the step prints skip dash (not installed) and the clean tree passes" \
    "rc=$RC $(has_line "$OUT" 'skip dash (not installed)') $(line "$OUT" 'ok   syntax')" '^rc=0 present ok   syntax \(.*dash: skipped\)$'

if [ "$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null)" = 3 ]; then
    newdir; tree_clean "$P/tree"; OUT=$P/out
    printf '%s\n' 'echo x |& cat' >"$P/tree/deck.bash"
    printf '%s\n' '#!/usr/bin/env bash' 'echo x |& cat' >"$P/tree/deck-man"
    launch "$OUT" -- "$SYNTAX" "$P/tree"; pid=$!
    await "$pid" 30
    check "H-09 a bash-4 construct (|&) in deck.bash fails when /bin/bash is 3.2" \
        "count=$(fails_for "$OUT" deck.bash | wc -l | tr -d ' ') $(fails_for "$OUT" deck.bash)" '^count=1 FAIL syntax bash-3\.2 deck\.bash: '
    check "H-09 a bash-4 construct (|&) in deck-man fails when /bin/bash is 3.2" \
        "count=$(fails_for "$OUT" deck-man | wc -l | tr -d ' ') $(fails_for "$OUT" deck-man)" '^count=1 FAIL syntax bash-3\.2 deck-man: '
else echo "skip H-09 bash 3.2 case (/bin/bash is not bash 3)"; fi

newdir; tree_clean "$P/tree"; OUT=$P/out
printf '%s\n' '#!/usr/bin/env bash' 'echo suite' 'cat /tmp/deckci.$$' 'sleep 1' 'sleep 1   # sleep: a reason' >"$P/tree/tests/run.sh"
printf '%s\n' '#!/usr/bin/env bash' 'sleep 2' >"$P/tree/modules/m/tests/run.sh"
launch "$OUT" -- "$SYNTAX" "$P/tree"; pid=$!
await "$pid" 30
core_hyg=$(grep '^FAIL hygiene ' "$OUT" | grep -v 'modules/')
check "H-10 a suite line that names /tmp/ fails hygiene at its line" \
    "$(has_line "$OUT" 'FAIL hygiene tests/run.sh:3: names /tmp/')" '^present$'
check "H-10 a suite line with a bare sleep fails hygiene at its line" \
    "$(has_line "$OUT" 'FAIL hygiene tests/run.sh:4: sleep without # sleep: REASON')" '^present$'
check "H-10 a module suite's bare sleep fails hygiene at its line" \
    "$(has_line "$OUT" 'FAIL hygiene modules/m/tests/run.sh:2: sleep without # sleep: REASON')" '^present$'
check "H-10 a sleep with # sleep: REASON, and /tmp/ or sleep outside the suites, pass; the exit status is the number of FAIL lines" \
    "rc=$RC fails=$(grep -c '^FAIL' "$OUT") line5=$(printf '%s\n' "$core_hyg" | grep -c 'tests/run\.sh:5: ')" '^rc=3 fails=3 line5=0$'

newdir; tree_clean "$P/tree"; OUT=$P/out
printf '%s\n' 'if [[ -n x ]]; then' >"$P/tree/top.zsh"
mkdir -p "$P/tree/nested/.git"
printf '%s\n' 'if [[ -n x ]]; then' >"$P/tree/nested/inner.zsh"
launch "$OUT" -- "$SYNTAX" "$P/tree"; pid=$!
await "$pid" 30
check "H-25 outside git the walk skips a directory holding its own .git, where the same file at the top is reported" \
    "nested=$(fails_for "$OUT" inner.zsh | wc -l | tr -d ' ') top=$(fails_for "$OUT" top.zsh) rc=$RC" \
    '^nested=0 top=FAIL syntax zsh top\.zsh: .* rc=1$'

if command -v git >/dev/null 2>&1; then
    newdir; tree_clean "$P/tree"; OUT=$P/out
    git init -q "$P/tree"
    printf '%s\n' 'if [[ -n x ]]; then' >"$P/tree/untracked.zsh"
    printf '%s\n' 'if [[ -n x ]]; then' >"$P/tree/tracked.zsh"
    git -C "$P/tree" add tracked.zsh
    printf '%s\n' 'if [[ -n x ]]; then' >"$P/tree/ignored.zsh"
    printf '%s\n' 'ignored.zsh' >"$P/tree/.gitignore"
    git init -q "$P/tree/nested"
    printf '%s\n' 'if [[ -n x ]]; then' >"$P/tree/nested/inner.zsh"
    launch "$OUT" -- "$SYNTAX" "$P/tree"; pid=$!
    await "$pid" 30
    check "H-25 in a git tree a broken untracked file is reported" \
        "$(fails_for "$OUT" untracked.zsh)" '^FAIL syntax zsh untracked\.zsh: '
    check "H-25 in a git tree a broken file in the index is reported" \
        "$(fails_for "$OUT" tracked.zsh)" '^FAIL syntax zsh tracked\.zsh: '
    check "H-25 in a git tree a broken file that .gitignore names is not reported, where the same file untracked is" \
        "ignored=$(fails_for "$OUT" ignored.zsh | wc -l | tr -d ' ') untracked=$(fails_for "$OUT" untracked.zsh | wc -l | tr -d ' ')" \
        '^ignored=0 untracked=1$'
    check "H-25 in a git tree a broken file in a nested repository is not reported, where the same file at the top is" \
        "nested=$(fails_for "$OUT" inner.zsh | wc -l | tr -d ' ') untracked=$(fails_for "$OUT" untracked.zsh | wc -l | tr -d ' ') rc=$RC" \
        '^nested=0 untracked=1 rc=2$'
else echo "skip H-25 git tree (git not installed)"; fi

newdir; PI=$P; ISO=$P/out
launch "$ISO" XDG_CONFIG_HOME="$P/xdg/config" XDG_CACHE_HOME="$P/xdg/cache" XDG_DATA_HOME="$P/xdg/data" XDG_STATE_HOME="$P/xdg/state" \
    -- "$PROBES/isolation.sh"; pid=$!
await "$pid" 20
reap "$pid"
newdir; PO=$P; OPEN=$P/out
launch "$OPEN" HARNESS_ISOLATE=0 XDG_CONFIG_HOME="$P/xdg/config" XDG_CACHE_HOME="$P/xdg/cache" XDG_DATA_HOME="$P/xdg/data" XDG_STATE_HOME="$P/xdg/state" \
    -- "$PROBES/isolation.sh"; pid=$!
await "$pid" 20
reap "$pid"
root=$(val "$ISO" root)
check "H-11 HARNESS_ROOT is a new mode-700 directory under TMPDIR" \
    "$(inside "$PI/tmp" "$root") mode=$(val "$ISO" mode)" '^inside mode=drwx------'
for v in HOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME TMPDIR; do
    check "H-11 the suite's $v lies inside HARNESS_ROOT" "$(inside "$root" "$(val "$ISO" "suite $v")")" '^inside$'
done
for v in HOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME TMPDIR; do
    check "H-11 the pane shell's $v lies inside HARNESS_ROOT" "$(inside "$root" "$(val "$ISO" "pane $v")")" '^inside$'
done
want="HOME=$PO/home XDG_CONFIG_HOME=$PO/xdg/config XDG_CACHE_HOME=$PO/xdg/cache XDG_DATA_HOME=$PO/xdg/data XDG_STATE_HOME=$PO/xdg/state TMPDIR=$PO/tmp"
got_suite="HOME=$(val "$OPEN" 'suite HOME')"
got_pane="HOME=$(val "$OPEN" 'pane HOME')"
for v in XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME TMPDIR; do
    got_suite="$got_suite $v=$(val "$OPEN" "suite $v")"
    got_pane="$got_pane $v=$(val "$OPEN" "pane $v")"
done
check "H-11 control: with HARNESS_ISOLATE=0 the caller's values reach the suite and the panes" \
    "suite: $(same "$got_suite" "$want") pane: $(same "$got_pane" "$want")" '^suite: same pane: same$'
check "H-11 control: with HARNESS_ISOLATE=0 the root is still created under TMPDIR" \
    "$(inside "$PO/tmp" "$(val "$OPEN" root)")" '^inside$'
if man -w echo >/dev/null 2>&1; then
    check "H-11 an isolated run leaves the caller's HOME and XDG directories untouched, where the HARNESS_ISOLATE=0 twin writes its cache there" \
        "isolated: home=$(tree_state "$PI/home") xdg=$(tree_state "$PI/xdg") | open: cache=$(tree_state "$PO/xdg/cache")" \
        '^isolated: home=empty xdg=absent \| open: cache=holds: deck $'
else echo "skip H-11 untouched-home case (no man page for echo, so nothing is cached)"; fi

newdir; A=$P/a; B=$P/b
launch "$A" -- "$PROBES/child.sh"; pa=$!
launch "$B" -- "$PROBES/child.sh"; pb=$!
await "$pa" 20; RA=$RC
await "$pb" 20; RB=$RC
check "H-12 two suites started together get different roots and sockets, and both pass" \
    "rc=$RA,$RB roots=$(distinct "$(val "$A" root)" "$(val "$B" root)") sockets=$(distinct "$(val "$A" sock)" "$(val "$B" sock)")" \
    '^rc=0,0 roots=distinct sockets=distinct$'
check "H-02 after two suites neither socket is left, nor a run root in TMPDIR" \
    "$(sock_state "$(val "$A" sock)") $(sock_state "$(val "$B" sock)") tmpdir=$(tree_state "$P/tmp")" \
    '^socket=gone socket=gone tmpdir=empty$'
reap "$pa" "$pb"

newdir; OUT=$P/out; launch "$OUT" -- "$PROBES/stop.sh"; pid=$!
await "$pid" 15
check "H-13 harness_stop kills the server and removes its socket file and the root" \
    "$(line "$OUT" root-before) $(line "$OUT" server-after) $(sock_state "$(val "$OUT" sock)") $(root_state "$(val "$OUT" root)")" \
    '^root-before=dir server-after=gone socket=gone root=gone$'
check "H-13 harness_stop prints the summary and returns the failure count; a second call prints nothing and returns the same count" \
    "first:'$(between "$OUT" stop1)' $(line "$OUT" 'stop1>>') second:'$(between "$OUT" stop2)' $(line "$OUT" 'stop2>>')" \
    "^first:'1 passed, 1 failed' stop1>> rc=1 second:'' stop2>> rc=1$"
reap "$pid"

newdir; OUT=$P/out; launch "$OUT" HARNESS_KEEP=1 -- "$PROBES/stop.sh"; pid=$!
await "$pid" 15
root=$(val "$OUT" root)
check "H-13 with HARNESS_KEEP=1 harness_stop keeps the root, holding files, and prints kept PATH" \
    "$(has_line "$OUT" "kept $root") root=$(tree_state "$root")" '^present root=holds: '
reap "$pid"

newdir; OUT=$P/out; launch "$OUT" -- "$PROBES/early-exit.sh"; pid=$!
await "$pid" 15
check "H-14 a suite that exits part-way is cleaned up, and the EXIT trap it set before sourcing still runs" \
    "$(server_state "$pid") $(sock_state "$(val "$OUT" sock)") $(root_state "$(val "$OUT" root)") caller-trap=$(has_line "$OUT" caller-trap-ran)" \
    '^server=gone socket=gone root=gone caller-trap=present$'
reap "$pid"

newdir; OUT=$P/out; launch "$OUT" -- "$PROBES/early-unset.sh"; pid=$!
await "$pid" 15
check "H-14 a suite stopped by an unset variable under set -u is cleaned up" \
    "$(server_state "$pid") $(sock_state "$(val "$OUT" sock)") $(root_state "$(val "$OUT" root)") reached=$(has_line "$OUT" 'not reached')" \
    '^server=gone socket=gone root=gone reached=absent$'
reap "$pid"

newdir; OUT=$P/out; launch "$OUT" -- "$PROBES/t-out.sh"; pid=$!
await "$pid" 20
check "H-18 t_out prints what the line wrote to stdout" "$(between "$OUT" t_out)" 'TO-OUT-42'
check "H-18 t_out prints what the line wrote to stderr" "$(between "$OUT" t_out)" 'TO-ERR-42'
check "H-18 none of t_out's text reaches a pane, where t's text does" \
    "printed=$(between "$OUT" t_out | grep -cE 'TO-(OUT|ERR)-42') $(line "$OUT" in-panes) $(line "$OUT" control-shown)" \
    '^printed=2 in-panes=0 control-shown=0$'
check "H-18 t_out's status is t's: 0 when the prompt comes back, 1 at the bound" \
    "$(line "$OUT" 't_out>>') $(line "$OUT" 't_out-bad>>')" '^t_out>> rc=0 t_out-bad>> rc=1$'
reap "$pid"

newdir; OUT=$P/out; launch "$OUT" -- "$PROBES/prompt.sh"; pid=$!
await "$pid" 15
check "H-19 HARNESS_PROMPT names the prompt pane after harness_start" \
    "$(same "$(val "$OUT" before-prompt)" "$(val "$OUT" before-stdin)")" '^same$'
check "H-19 HARNESS_PROMPT still names the prompt pane after deck off" \
    "$(same "$(val "$OUT" after-prompt)" "$(val "$OUT" after-panes)")" '^same$'
reap "$pid"

newdir; OUT=$P/out; launch "$OUT" -- "$PROBES/titles.sh"; pid=$!
await "$pid" 20
check "H-20 titles prints the pane titles in pane order on one line" \
    "$(line "$OUT" 'before ')" '^before rc=0 lines=1 text=stdin stdout stderr man$'
check "H-20 wait_title returns 0 once the titles match, printing nothing" \
    "$(line "$OUT" 'match ')" '^match rc=0 elapsed=[0-5] out=$'
check "H-20 titles follows a change of mode" \
    "$(line "$OUT" 'after ')" '^after text=stdin.* stdout stderr files$'
check "H-20 a pattern that never matches: wait_title returns 1 after its 2 s, within 1 s more, printing nothing" \
    "$(line "$OUT" 'never ')" '^never rc=1 elapsed=[23] out=$'
reap "$pid"

newdir; OUT=$P/out; launch "$OUT" -- "$PROBES/wait-last.sh"; pid=$!
await "$pid" 20
check "H-21 wait_last matches the last non-blank line of the pane" \
    "$(line "$OUT" 'last ')" '^last rc=0 elapsed=[0-2] out=$'
check "H-21 text on an earlier line only: wait_last returns 1 after its 2 s" \
    "$(line "$OUT" 'earlier ')" '^earlier rc=1 elapsed=[23] out=$'
reap "$pid"

newdir; OUT=$P/out; launch "$OUT" -- "$PROBES/wait-until.sh"; pid=$!
await "$pid" 20
check "H-22 wait_until re-runs a function until it succeeds: success on the third call gives 0" \
    "$(line "$OUT" 'third ')" '^third rc=0 calls=3 elapsed=[0-2]$'
check "H-22 a command that never succeeds gives 1 after the given seconds" \
    "$(line "$OUT" 'false ')" '^false rc=1 elapsed=[23]$'
check "H-22 the command's arguments are passed: test 1 = 1 gives 0, test 1 = 2 gives 1" \
    "$(line "$OUT" 'args-true ') $(line "$OUT" 'args-false ')" '^args-true rc=0 args-false rc=1$'
check "H-22 the command's output is discarded" \
    "$(line "$OUT" 'quiet ')" '^quiet rc=0 out=$'
reap "$pid"

if man -w ls >/dev/null 2>&1; then
    newdir; OUT=$P/out; launch "$OUT" -- "$PROBES/quiet-tail.sh"; pid=$!
    await "$pid" 40
    check "H-26 control: with the follower on, a t line whose command has a manual page is looked up" \
        "$(line "$OUT" 'control>>') [$STATE]" '^control>> rc=0 log=.*(^|[| ])ls\|'
    check "H-26 the text t adds to a line makes the follower look nothing up: a warm t of an assignment causes no man call" \
        "$(line "$OUT" 'quiet>>') [$STATE]" '^quiet>> rc=0 lookups=0 log= '
    reap "$pid"
else echo "skip H-26 (no man page for ls, so the follower looks nothing up)"; fi

echo "$pass passed, $fail failed"
exit "$fail"
