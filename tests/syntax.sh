#!/usr/bin/env bash
# syntax.sh [ROOT] — check every shell and Python file under ROOT (default: the
# repository) in its own dialect, and the test suites for hygiene.
#
# Which files: inside a git work tree whose top is ROOT, the tracked and the
# untracked files that .gitignore does not name; otherwise every file under
# ROOT except .git. Either way, anything below a directory that holds its own
# .git (a nested repository or worktree) is left to that repository.
#
# How a file is read: *.zsh is zsh, *.bash is bash, *.py is Python; otherwise
# the #! line decides (bash, sh/dash, zsh, python3); a *.sh without a #! line is
# bash under tests/ and sh elsewhere. An executable file that none of these
# classify fails the step.
#
# Checkers: zsh -n; bash -n, and /bin/bash -n too when that is bash 3.x (the
# remote hosts and macOS); sh -n, and dash -n too when dash is installed;
# Python parsed with ast at the 3.8 grammar.
#
# Hygiene: tests/run.sh and modules/*/tests/run.sh must not name /tmp/ and must
# not call sleep without "# sleep: REASON" on the same line; the CI workflow
# must declare timeout-minutes.
#
# Output: one line per problem,
#   FAIL syntax DIALECT FILE: first error line
#   FAIL syntax unclassified FILE: no known extension or #! line
#   FAIL hygiene FILE:LINE: names /tmp/
#   FAIL hygiene FILE:LINE: sleep without # sleep: REASON
#   FAIL hygiene .github/workflows/ci.yml: no timeout-minutes
# FILE is relative to ROOT. Without a problem, one "ok   syntax (...)" line.
# Exit status: the number of FAIL lines, at most 125.
#
# Runs under bash 3.2 and later: no associative arrays, no mapfile.

set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P) || exit 1
ROOT=$(cd "${1:-$here}" 2>/dev/null && pwd -P) || { echo "syntax.sh: no such directory: ${1:-}" >&2; exit 2; }
cd "$ROOT" || exit 2

fails=0
# One counter per dialect; plain variables because bash 3.2 has no
# associative arrays.
n_zsh=0 n_bash=0 n_bash32=0 n_sh=0 n_dash=0 n_python3=0

have_dash=0; command -v dash >/dev/null 2>&1 && have_dash=1
[ "$have_dash" = 1 ] || echo "skip dash (not installed)"
have_bash32=0
if [ -x /bin/bash ] && [ "$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null)" = 3 ]; then have_bash32=1
else echo "skip bash-3.2 (/bin/bash is not 3.x)"; fi

# A name or message from a file may hold control characters; one line, printable.
clean() { LC_ALL=C tr -c '[:print:]' '?'; }

fail() {
    fails=$(( fails + 1 ))
    printf 'FAIL %s\n' "$(printf '%s' "$1" | clean)"
}

# run_check DIALECT FILE CMD...: run the checker, and on rejection report the
# first line it printed. Returns 1 so the caller stops at the first rejection.
run_check() {
    local dialect=$1 file=$2 msg; shift 2
    if msg=$("$@" 2>&1); then return 0; fi
    msg=$(printf '%s\n' "$msg" | sed -n '1p')
    fail "syntax $dialect $file: ${msg:-rejected}"
    return 1
}

PYCHECK='
import ast, sys
try:
    with open(sys.argv[1], "rb") as f:
        ast.parse(f.read(), sys.argv[1], feature_version=(3, 8))
except SyntaxError as e:
    print("%s (line %s)" % (e.msg, e.lineno)); sys.exit(1)
except (ValueError, OSError) as e:
    print(e); sys.exit(1)
'

# shebang_dialect LINE: the dialect a #! line names, or nothing.
shebang_dialect() {
    local interp
    set -f   # the words come from a file; a * in them is not a pattern
    set -- ${1#\#!}
    set +f
    interp=${1:-}; interp=${interp##*/}
    if [ "$interp" = env ]; then
        shift
        while [ $# -gt 0 ]; do case $1 in -*|*=*) shift ;; *) break ;; esac; done
        interp=${1:-}; interp=${interp##*/}
    fi
    case $interp in
        bash) echo bash ;;
        sh|dash) echo sh ;;
        zsh) echo zsh ;;
        python3|python3.*|python) echo python3 ;;
    esac
}

# classify FILE: sets DIALECT to zsh, bash, sh, python3, unclassified or none.
classify() {
    local f=$1 first=""
    case $f in
        *.zsh) DIALECT=zsh; return ;;
        *.bash) DIALECT=bash; return ;;
        *.py) DIALECT=python3; return ;;
    esac
    IFS= read -r -n 256 first <"$f" 2>/dev/null
    case $first in
        '#!'*) DIALECT=$(shebang_dialect "$first") ;;
        *) DIALECT= ;;
    esac
    [ -n "$DIALECT" ] && return
    case $f in
        tests/*|*/tests/*) case $f in *.sh) DIALECT=bash; return ;; esac ;;
        *.sh) DIALECT=sh; return ;;
    esac
    if [ -x "$f" ]; then DIALECT=unclassified; else DIALECT=none; fi
}

check_file() {
    local f=$1
    classify "$f"
    case $DIALECT in
        none) return ;;
        unclassified) fail "syntax unclassified $f: no known extension or #! line"; return ;;
        zsh)
            if command -v zsh >/dev/null 2>&1; then run_check zsh "$f" zsh -n "./$f"
            else fail "syntax zsh $f: zsh is not installed"; fi
            n_zsh=$(( n_zsh + 1 )) ;;
        bash)
            n_bash=$(( n_bash + 1 ))
            run_check bash "$f" bash -n "./$f" || return
            if [ "$have_bash32" = 1 ]; then
                n_bash32=$(( n_bash32 + 1 ))
                run_check bash-3.2 "$f" /bin/bash -n "./$f"
            fi ;;
        sh)
            n_sh=$(( n_sh + 1 ))
            run_check sh "$f" sh -n "./$f" || return
            if [ "$have_dash" = 1 ]; then
                n_dash=$(( n_dash + 1 ))
                run_check dash "$f" dash -n "./$f"
            fi ;;
        python3)
            n_python3=$(( n_python3 + 1 ))
            run_check python3 "$f" python3 -I -c "$PYCHECK" "./$f" ;;
    esac
}

# is_suite FILE: the core suite or a module's.
is_suite() { case $1 in tests/run.sh|modules/*/tests/run.sh) return 0 ;; esac; return 1; }

hygiene() {
    local f=$1 n kind found
    # The awk script reads each line once and names the defect. A line that
    # only holds a comment is not a call.
    found=$(awk '
        /^[ \t]*#/ { next }
        index($0, "/tmp/") { print NR " tmp" }
        /(^|[^A-Za-z0-9_.-])sleep([ \t]|$)/ && !/#[ \t]*sleep:[ \t]*[^ \t]/ { print NR " sleep" }
    ' "$f")
    [ -n "$found" ] || return 0
    # A here-string, not a pipe: fail() must update the counter in this shell.
    while read -r n kind; do
        case $kind in
            tmp) fail "hygiene $f:$n: names /tmp/" ;;
            sleep) fail "hygiene $f:$n: sleep without # sleep: REASON" ;;
        esac
    done <<<"$found"
}

# in_nested_repo FILE: true when a directory above FILE, below ROOT, holds a
# .git entry. The last answer is kept: files arrive grouped by directory.
last_dir= last_nested=1
in_nested_repo() {
    local dir=${1%/*} p
    [ "$dir" = "$1" ] && return 1
    if [ "$dir" = "$last_dir" ]; then return "$last_nested"; fi
    last_dir=$dir last_nested=1
    p=$dir
    while [ -n "$p" ]; do
        if [ -e "$p/.git" ]; then last_nested=0; break; fi
        case $p in */*) p=${p%/*} ;; *) break ;; esac
    done
    return "$last_nested"
}

# The file list, NUL-separated so that names with spaces or newlines survive.
use_git=0
if command -v git >/dev/null 2>&1; then
    top=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null) && top=$(cd "$top" 2>/dev/null && pwd -P) \
        && [ "$top" = "$ROOT" ] && use_git=1
fi
list_files() {
    if [ "$use_git" = 1 ]; then git -C "$ROOT" ls-files -z --cached --others --exclude-standard
    else find . -name .git -prune -o -type f -print0; fi
}

while IFS= read -r -d '' f; do
    f=${f#./}
    case $f in */) continue ;; esac
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    in_nested_repo "$f" && continue
    check_file "$f"
    if is_suite "$f"; then hygiene "$f"; fi
done < <(list_files)

if [ -f .github/workflows/ci.yml ] && ! grep -Eq '^[[:space:]]*timeout-minutes:[[:space:]]*[0-9]+' .github/workflows/ci.yml; then
    fail "hygiene .github/workflows/ci.yml: no timeout-minutes"
fi

if [ "$fails" -eq 0 ]; then
    dash_state=skipped; [ "$have_dash" = 1 ] && dash_state=checked
    echo "ok   syntax (zsh $n_zsh, bash $n_bash, bash-3.2 $n_bash32, sh $n_sh, dash $n_dash, python3 $n_python3; dash: $dash_state)"
fi
[ "$fails" -gt 125 ] && fails=125
exit "$fails"
