# history.zsh — `deck history`: recording hooks. Sourced after deck.zsh (the installer does).
#
# The hooks do no real work: they append one line of text per command start and
# end to $MYSTORY_DIR/events, and write an invisible marker into flightdeck's
# stdout and stderr panes. tmux (pipe-pane) copies everything those panes
# receive — markers included — into log files. `mystory ingest`, started in the
# background after each command, cuts the logs at the markers.
#
#   A leading space             -> command is not recorded at all
#   MYSTORY_IGNORE=(pat ...)    -> same, for commands matching a glob pattern
#   MYSTORY_NOOUTPUT=(pat ...)  -> command is recorded, its output is not
#
# With the deck off, commands are still recorded, without output.

zmodload zsh/datetime
# The store: ~/.local/share/deck/history, or an older mystory store if there is one.
if [[ -z $MYSTORY_DIR ]]; then
    MYSTORY_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/deck/history
    [[ -d $MYSTORY_DIR || ! -d ${XDG_DATA_HOME:-$HOME/.local/share}/mystory ]] || MYSTORY_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/mystory
fi
: ${MYSTORY_BIN:=${${(%):-%x}:A:h}/deck-history}
export MYSTORY_DIR
typeset -ga MYSTORY_IGNORE MYSTORY_NOOUTPUT
(( $#MYSTORY_NOOUTPUT )) || MYSTORY_NOOUTPUT=( 'mystory' 'mystory *' )
typeset -g _mystory_uid= _mystory_piped= _mystory_out_log= _mystory_err_log=
typeset -g _mystory_out_tty= _mystory_err_tty=

[[ -d $MYSTORY_DIR/live ]] || ( umask 077; mkdir -p $MYSTORY_DIR/live )

# Attach tmux's pipe-pane to flightdeck's output panes (once per `deck`).
# pipe-pane hands the pane's raw byte stream to a shell command; ours appends
# it to a file. The program writing to the pane cannot tell.
_mystory_attach() {
    emulate -L zsh
    if [[ -z $DECK_OUT_PANE || -z $TMUX ]]; then       # deck off, or a remote deck (no tmux there)
        _mystory_piped= _mystory_out_log= _mystory_err_log=
        return
    fi
    [[ $DECK_OUT_PANE == $_mystory_piped ]] && return
    local base=$MYSTORY_DIR/live/$$-${DECK_OUT_PANE#%}
    tmux pipe-pane -t $DECK_OUT_PANE "umask 077; exec cat >> ${(q)base}.out" \; \
         pipe-pane -t $DECK_ERR_PANE "umask 077; exec cat >> ${(q)base}.err" || return
    _mystory_piped=$DECK_OUT_PANE
    _mystory_out_log=$base.out _mystory_err_log=$base.err
}

# branch@commit without forking git: read .git/HEAD directly.
_mystory_git() {
    emulate -L zsh
    local d=$PWD head ref
    while [[ -n $d ]]; do
        if [[ -f $d/.git/HEAD ]]; then
            head=$(<$d/.git/HEAD)
            if [[ $head == 'ref: '* ]]; then
                ref=${head#ref: }
                REPLY=${ref#refs/heads/}
                [[ -f $d/.git/$ref ]] && REPLY+="@${$(<$d/.git/$ref)[1,12]}"
            else
                REPLY="detached@${head[1,12]}"
            fi
            return
        fi
        d=${d%/*}
    done
    REPLY=
}

_mystory_preexec() {
    emulate -L zsh
    _mystory_uid=
    local cmd=${1:-$3} pat noout=0 US=$'\x1f' RS=$'\x1e'
    [[ -z $cmd || $cmd == [[:space:]]* ]] && return
    for pat in $MYSTORY_IGNORE;   do [[ $cmd == ${~pat} ]] && return;  done
    for pat in $MYSTORY_NOOUTPUT; do [[ $cmd == ${~pat} ]] && noout=1; done

    _mystory_attach
    _mystory_git
    _mystory_uid="${EPOCHREALTIME/./}-$$"
    _mystory_out_tty=$DECK_OUT_TTY _mystory_err_tty=$DECK_ERR_TTY

    # The record exists from this moment, before the command runs: a crash or
    # a killed terminal still leaves evidence that it was started.
    local -a f
    f=( S $_mystory_uid $EPOCHREALTIME $$ $HOST $USER $PWD
        "$_mystory_out_log" "$_mystory_err_log" $noout "$REPLY" "$TMUX_PANE"
        "${cmd//[$US$RS]/}" "${3//[$US$RS]/}" )
    print -rn -- "${(pj:\x1f:)f}$RS" >> $MYSTORY_DIR/events

    if [[ -n $_mystory_out_log ]]; then
        print -n -- "\e]7777;mystory;S;$_mystory_uid\a" > $_mystory_out_tty
        print -n -- "\e]7777;mystory;S;$_mystory_uid\a" > $_mystory_err_tty
    fi
}

_mystory_precmd() {
    local st=$? ps="${pipestatus[*]}"
    emulate -L zsh
    [[ -n $_mystory_uid ]] || return $st
    local US=$'\x1f' RS=$'\x1e'
    if [[ -n $_mystory_out_log ]]; then
        [[ -w $_mystory_out_tty ]] && print -n -- "\e]7777;mystory;E;$_mystory_uid\a" > $_mystory_out_tty
        [[ -w $_mystory_err_tty ]] && print -n -- "\e]7777;mystory;E;$_mystory_uid\a" > $_mystory_err_tty
    fi
    print -rn -- "E$US$_mystory_uid$US$EPOCHREALTIME$US$st$US$ps$RS" >> $MYSTORY_DIR/events
    _mystory_uid=
    $MYSTORY_BIN ingest --wait </dev/null &>/dev/null &!
    return $st           # hand the real exit status on to the next precmd hook
}

autoload -Uz add-zsh-hook
# preexec: AFTER flightdeck's, so its "── time ❯ cmd" stamp falls before our
# start marker and stays out of the record.
add-zsh-hook preexec _mystory_preexec
# precmd: BEFORE flightdeck's, so we see the command's true $? and our end
# marker precedes its "── exit N" line.
precmd_functions=( _mystory_precmd ${precmd_functions:#_mystory_precmd} )

_deck_cmd_history() { command $MYSTORY_BIN "$@" }      # deck history ...
