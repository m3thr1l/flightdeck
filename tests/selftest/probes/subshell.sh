#!/usr/bin/env bash
# subshell.sh MODE — t_out inside $( ), with the follower off.
#   count     a line that never returns, captured with $(t_out …): report
#             what was captured, then stop
#   check     the same line inside check "…" "$(t_out …)" PATTERN, where the
#             pattern names text of the line itself
#   channels  a captured line that ignores Ctrl-C and signals after its
#             bound, then two more captured lines: each must wait for itself
set -u
. "$FLIGHTDECK/tests/harness.sh"
harness_start
t "DECK_FOLLOW=0"
case $1 in
count)
    out=$(t_out "echo [x]; echo MARK-X" 2)
    echo "captured=[$out]"
    ;;
check)
    check "H-27 probe: the capture names the command, which never ran" "$(t_out "echo [x]; echo MARK-X" 2)" 'MARK-X'
    ;;
channels)
    out=$(t_out "( trap '' INT; sleep 3 ); echo LATE-\$((6*7))" 1)
    echo "first captured=[$out]"
    s=$SECONDS
    out=$(t_out "sleep 4; echo TWO-\$((6*7))" 10)
    echo "second rc=$? elapsed=$(( SECONDS - s )) captured=[$out]"
    out=$(t_out "echo THREE-\$((6*7))" 10)
    echo "third rc=$? captured=[$out]"
    ;;
esac
harness_stop
