# net.zsh — flightdeck for network tools. Source from ~/.zshrc AFTER deck.zsh.
#
#   deck mode net         follower: the card of the host under the cursor (address,
#                         CIDR, MAC or a known name), the man page otherwise
#   deck hosts [ARGS]     the inventory: list [QUERY] | show HOST | ingest [FILE]
#
# Runs of the tools in DECK_NET_TOOLS feed the inventory by themselves: while
# one runs, the stdout pane is copied to a file through tmux pipe-pane (the
# mystory technique), and when it ends the file is parsed in the background.

: ${DECK_HOSTS:=${${(%):-%x}:A:h}/deck-hosts}
: ${DECK_NET_DIR:=${XDG_DATA_HOME:-$HOME/.local/share}/deck-net}
export DECK_NET_DIR
typeset -ga DECK_NET_TOOLS
(( $#DECK_NET_TOOLS )) || DECK_NET_TOOLS=( nmap arp arp-scan )
typeset -g _deck_net_live=''

_deck_cmd_hosts() { command $DECK_HOSTS "$@" }

# The word under the cursor, if it names a host: IPv4, CIDR, MAC, or a word
# with a dot in it that the inventory knows.
_deck_net_word() {
    emulate -L zsh; setopt extendedglob
    local cur=${LBUFFER##*[[:space:]]}${RBUFFER%%[[:space:]]*}
    cur=${cur#*@}; cur=${cur%%[,;:]}
    [[ -n $cur && $cur != -* ]] || return 1
    [[ $cur == ([0-9](#c1,3).)(#c3)[0-9](#c1,3)(/[0-9](#c1,2)|) ]] && { print -r -- $cur; return 0 }
    [[ $cur == ([0-9a-fA-F](#c1,2):)(#c5)[0-9a-fA-F](#c1,2) ]] && { print -r -- $cur; return 0 }
    [[ $cur == *.[a-zA-Z]* && $LBUFFER == *[[:space:]]* ]] && { print -r -- $cur; return 0 }
    return 1
}
_deck_mode_net_follow() {
    emulate -L zsh
    local w; w=$(_deck_net_word) || { _deck_mode_man_follow; return }
    [[ "N:$w" != $_deck_last ]] || return 0
    local rc
    if [[ $w == */* ]]; then command $DECK_HOSTS subnet $w $DECK_HELP_TTY 2>/dev/null; rc=$?
    else command $DECK_HOSTS card $w $DECK_HELP_TTY 2>/dev/null; rc=$?; fi
    if (( rc == 0 )); then _deck_last="N:$w" _deck_scroll=0
    else _deck_mode_man_follow; fi           # not in the inventory: the man page is still useful
}
_deck_mode_net_repaint() {
    if [[ $_deck_last == N:* ]]; then _deck_mode_net_follow
    else _deck_mode_man_repaint; fi
}
DECK_MODES+=( net )

# ---- automatic ingest ---------------------------------------------------
_deck_net_preexec() {
    [[ -n $DECK_OUT_PANE && -n $TMUX ]] || return 0
    local -a w; w=( ${(z)1} )
    while [[ $w[1] == (sudo|doas|command|nocorrect|noglob|time) || $w[1] == *=* ]]; do shift w; done
    [[ $w[1] == -* ]] && return 0
    (( $DECK_NET_TOOLS[(Ie)${w[1]:t}] )) || return 0
    mkdir -p $DECK_NET_DIR/live 2>/dev/null
    _deck_net_live=$DECK_NET_DIR/live/$$-$EPOCHSECONDS.out
    tmux pipe-pane -t $DECK_OUT_PANE "umask 077; exec cat >> ${(q)_deck_net_live}" 2>/dev/null || _deck_net_live=''
}
_deck_net_precmd() {
    local st=$?
    [[ -n $_deck_net_live ]] || return $st
    tmux pipe-pane -t $DECK_OUT_PANE 2>/dev/null       # no command = stop
    local f=$_deck_net_live; _deck_net_live=''
    ( sleep 0.3; command $DECK_HOSTS ingest auto $f; rm -f $f ) </dev/null &>/dev/null &!
    return $st
}
zmodload zsh/datetime
autoload -Uz add-zsh-hook
add-zsh-hook preexec _deck_net_preexec
precmd_functions=( _deck_net_precmd ${precmd_functions:#_deck_net_precmd} )
