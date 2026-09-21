# cisco.zsh — flightdeck for network devices. Source from ~/.zshrc AFTER deck.zsh.
#
#   net HOST [SSH-ARGS]   ssh to a switch/router with the session split into
#                         the deck's panes (see deck-net), follower in cisco mode
#   deck mode cisco       the follower mode on its own: shows the device's
#                         answers to `?` (painted by deck-net during a session)
#
# Devices are never multiplexed: a switch usually allows one session per user
# and no extra channels, and a lingering ControlMaster would lock you out.

: ${DECK_NET:=${${(%):-%x}:A:h}/deck-net}
typeset -ga DECK_NET_HOSTS                      # glob patterns of hosts `ssh` should treat as devices
(( $#DECK_NET_HOSTS )) || DECK_NET_HOSTS=( '*-sw*' '*-rtr*' '*-switch*' '*-router*' )

_deck_mode_cisco_follow()  { : }               # nothing to follow at the shell prompt
_deck_mode_cisco_repaint() { : }               # deck-net paints the pane itself
_deck_mode_cisco_enter() {
    [[ -n $DECK_HELP_TTY ]] && printf '\e[H\e[2J\e[2m cisco: the answer to ? appears here during `net HOST`\e[0m' >$DECK_HELP_TTY
}
DECK_MODES+=( cisco )

net() {                                         # net HOST [SSH-ARGS...]
    emulate -L zsh
    (( $# )) || { print -u2 "usage: net HOST [SSH-ARGS...]"; return 2 }
    local prev=$DECK_MODE rc
    [[ -n $DECK_HELP_PANE ]] && _deck_mode cisco
    # One terminal (the prompt pane) through the shell's saved fds, as deck-tty
    # does; deck-net opens the other panes itself from DECK_*_TTY.
    if [[ -n $DECK_SAVE_OUT ]]; then
        DECK_OUT_TTY=$DECK_OUT_TTY DECK_ERR_TTY=$DECK_ERR_TTY DECK_HELP_TTY=$DECK_HELP_TTY \
            command $DECK_NET "$@" >&$DECK_SAVE_OUT 2>&$DECK_SAVE_ERR
    else command $DECK_NET "$@"; fi
    rc=$?
    [[ -n $DECK_HELP_PANE ]] && _deck_mode $prev
    return $rc
}

# `ssh some-switch` typed under the deck: route it through net instead of the
# multiplexed, zoomed session deck gives Unix hosts.
_deck_net_ssh() {
    local a h
    for a in "$@"; do [[ $a == -* ]] || { h=${a#*@}; break }; done
    local pat; for pat in $DECK_NET_HOSTS; do
        [[ $h == ${~pat} ]] && { net "$@"; return }
    done
    command ssh "$@"
}
