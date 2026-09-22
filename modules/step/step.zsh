# step.zsh — run scripts one line at a time inside flightdeck. Source from
# ~/.zshrc AFTER deck.zsh.
#
#   deck step SCRIPT [ARGS]   sh/bash/zsh or Python script, stepped, source on the right
#   deck mode script          the follower mode on its own: shows the script named
#                             on the command line
#   Alt-x                     run the typed command line under deck step

: ${DECK_STEP:=${${(%):-%x}:A:h}/deck-step}

_deck_script_file() {                         # first word on the line that is a readable script
    local -a w; w=( ${(z)LBUFFER}${RBUFFER%%[[:space:]]*} )
    local x f
    for x in $w; do
        f=${x/#\~/$HOME}
        [[ -f $f && -r $f ]] || continue
        [[ $f == *.(sh|bash|zsh|py) || "$(head -c2 -- $f 2>/dev/null)" == '#!' ]] && { print -r -- $f; return 0 }
    done
    return 1
}
_deck_mode_script_follow() {
    emulate -L zsh
    local f; f=$(_deck_script_file) || return 0
    [[ $f != $_deck_last ]] || return 0
    _deck_last=$f _deck_scroll=0
    $DECK_SRC $DECK_HELP_TTY $f 0 0 2>/dev/null
}
_deck_mode_script_repaint() {
    [[ -n $_deck_last ]] && $DECK_SRC $DECK_HELP_TTY $_deck_last 0 $_deck_scroll 2>/dev/null
}
DECK_MODES+=( script )

_deck_cmd_step() {                            # deck step SCRIPT [ARGS...]
    emulate -L zsh
    (( $# )) || { print -u2 "usage: deck step SCRIPT [ARGS...]"; return 2 }
    local prev=$DECK_MODE rc
    [[ -n $DECK_HELP_PANE ]] && _deck_mode script
    DECK_HELP_TTY=$DECK_HELP_TTY DECK_SRC=$DECK_SRC $DECK_STEP "$@"; rc=$?
    [[ -n $DECK_HELP_PANE ]] && _deck_mode $prev
    return $rc
}
_deck_step_line() {                           # Alt-x: run this command line under deck step
    [[ -n ${BUFFER//[[:space:]]/} ]] || return 0
    [[ $BUFFER == deck\ step\ * ]] || BUFFER="deck step $BUFFER"
    zle accept-line
}
zle -N _deck_step_line
bindkey '^[x' _deck_step_line                  # Alt-x (replaces execute-named-cmd)
bindkey $'\xe2\x89\x88' _deck_step_line        # ≈  Option-x
