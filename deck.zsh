# deck.zsh — source this from ~/.zshrc.   Requires: zsh >= 5.3, tmux >= 3.2
#
#   deck        split the current tmux window into stdout / stderr / man panes
#               around this shell, and redirect this shell's fd 1 and fd 2
#   deck off    restore fds, close the extra panes
#   here CMD    run one command un-split, in the prompt pane (works for functions too)
#   deck-tty CMD   same, but zoomed to the full window (external programs)
#   Alt-Up / Alt-Down   scroll the man pane;  Alt-h  toggle following
#
#   +------------------+---------------+
#   | zsh (stdin)      |               |
#   +------------------+               |
#   | stdout           |  man follower |
#   |                  |               |
#   +------------------+               |
#   | stderr           |               |
#   +------------------+---------------+
#
# Interactive programs (editors, pagers, top...) are run "combined" through
# deck-tty: prompt pane zoomed to the whole window, all fds on one terminal.
# Add your own:   DECK_TTY_CMDS+=(lazygit k9s)   before sourcing this file.

: ${DECK_MAN:=${${(%):-%x}:A:h}/deck-man}     # helpers live next to this file
: ${DECK_TTY:=${${(%):-%x}:A:h}/deck-tty}
typeset -ga DECK_TTY_CMDS
DECK_TTY_CMDS+=( vim nvim vi nano emacs less more most top htop btop watch
                 ssh fzf tig lazygit mc ranger nnn vifm gdb ipython psql mysql )
typeset -gA _deck_saved_env
typeset -g  DECK_OUT_PANE DECK_ERR_PANE DECK_HELP_PANE
typeset -g  DECK_OUT_TTY  DECK_ERR_TTY  DECK_HELP_TTY
typeset -g  DECK_SAVE_OUT DECK_SAVE_ERR
typeset -gi DECK_FOLLOW=1 _deck_scroll=0
typeset -g  _deck_last=''
typeset -gA _deck_pages                       # "cmd sub" -> man page name ('' = none)

# ---------------------------------------------------------------- layout ----
deck() {
    emulate -L zsh
    [[ $1 == off ]] && { _deck_off; return }
    [[ -n $TMUX ]]          || { print -u2 "deck: not inside tmux"; return 1 }
    [[ -z $DECK_OUT_PANE ]] || { print -u2 "deck: already on (deck off to undo)"; return 1 }

    # The extra panes run nothing but a sleeping placeholder. Its only job is
    # to keep the pane's pty open so that we have a terminal device to write to.
    local hold='stty -echo 2>/dev/null; exec tail -f /dev/null' info
    local me=$TMUX_PANE

    info=$(tmux split-window -h -d -l 42% -t $me -P -F '#{pane_id} #{pane_tty}' $hold) || return
    DECK_HELP_PANE=${info%% *} DECK_HELP_TTY=${info#* }
    info=$(tmux split-window -v -d -l 80% -t $me -P -F '#{pane_id} #{pane_tty}' $hold) || return
    DECK_OUT_PANE=${info%% *}  DECK_OUT_TTY=${info#* }
    info=$(tmux split-window -v -d -l 30% -t $DECK_OUT_PANE -P -F '#{pane_id} #{pane_tty}' $hold) || return
    DECK_ERR_PANE=${info%% *}  DECK_ERR_TTY=${info#* }

    # Refuse to redirect at a pane that has already died (macOS recycles pty
    # paths instantly, so a stale device may belong to someone else).
    local p
    for p in $DECK_HELP_PANE $DECK_OUT_PANE $DECK_ERR_PANE; do
        tmux display-message -p -t $p "" >/dev/null 2>&1 || { print -u2 "deck: pane $p died at once"; _deck_off; return 1 }
    done

    tmux select-pane -t $DECK_OUT_PANE  -T stdout \; select-pane -t $DECK_OUT_PANE  -d \; \
         select-pane -t $DECK_ERR_PANE  -T stderr \; select-pane -t $DECK_ERR_PANE  -d \; \
         select-pane -t $DECK_HELP_PANE -T man    \; select-pane -t $DECK_HELP_PANE -d \; \
         select-pane -t $me             -T stdin  \; \
         set-option -w pane-border-status top \; \
         set-option -w pane-border-format ' #{pane_title} '

    # Keep copies of the original fd 1/2 (zsh picks free fd numbers >= 10),
    # then point 1 and 2 at the other panes' ptys. Every child inherits these.
    # ZLE is unaffected: it talks to the terminal through its own private fd.
    exec {DECK_SAVE_OUT}>&1 {DECK_SAVE_ERR}>&2
    exec >$DECK_OUT_TTY 2>$DECK_ERR_TTY

    # Interactive programs get one terminal, not three (see deck-tty).
    # 1. Programs *other programs* launch: git -> pager, git commit -> editor.
    #    Those are found through the environment, so wrap the variables.
    export DECK_ACTIVE=1
    local v
    for v in PAGER MANPAGER GIT_PAGER VISUAL EDITOR; do
        if [[ -v $v ]]; then _deck_saved_env[$v]=${(P)v}; else _deck_saved_env[$v]=__unset__; fi
    done
    export PAGER="$DECK_TTY ${PAGER:-less}"
    [[ -n $MANPAGER  ]] && export MANPAGER="$DECK_TTY $MANPAGER"
    [[ -n $GIT_PAGER ]] && export GIT_PAGER="$DECK_TTY $GIT_PAGER"
    export VISUAL="$DECK_TTY ${VISUAL:-${EDITOR:-vim}}"
    export EDITOR=$VISUAL
    # 2. Programs *you* type: shadow each name with a function. Assigning to
    #    $functions (rather than writing `vim() {...}`) sidesteps alias
    #    expansion of the name; aliases still work, since `alias vim=nvim`
    #    expands first and then hits the nvim function.
    local c
    for c in $DECK_TTY_CMDS; do
        (( $+commands[$c] && ! $+functions[$c] )) || continue
        functions[$c]="command ${(q)DECK_TTY} $c \"\$@\""
        _deck_shadowed+=( $c )
    done
}
typeset -ga _deck_shadowed

_deck_off() {
    emulate -L zsh
    [[ -n $DECK_OUT_PANE ]] || return 0
    exec >&$DECK_SAVE_OUT 2>&$DECK_SAVE_ERR
    exec {DECK_SAVE_OUT}>&- {DECK_SAVE_ERR}>&-
    local v c
    for v in ${(k)_deck_saved_env}; do
        if [[ $_deck_saved_env[$v] == __unset__ ]]; then unset $v
        else export $v=$_deck_saved_env[$v]; fi
    done
    _deck_saved_env=()
    for c in $_deck_shadowed; do unfunction $c 2>/dev/null; done
    _deck_shadowed=()
    unset DECK_ACTIVE
    local p
    for p in $DECK_OUT_PANE $DECK_ERR_PANE $DECK_HELP_PANE; do
        tmux kill-pane -t $p 2>/dev/null
    done
    tmux set-option -wu pane-border-status 2>/dev/null
    DECK_OUT_PANE= DECK_ERR_PANE= DECK_HELP_PANE=
    DECK_OUT_TTY=  DECK_ERR_TTY=  DECK_HELP_TTY=
    _deck_last=
}

# Manual escape hatch: run anything (functions and builtins included) with the
# original fds, i.e. un-split in the prompt pane, without zooming.
here() {
    if [[ -n $DECK_SAVE_OUT ]]; then "$@" >&$DECK_SAVE_OUT 2>&$DECK_SAVE_ERR
    else "$@"; fi
}

# Prompt-pane title: "stdin" at the prompt, "stdin ▸ <command> [pid]" while a
# command runs. $1 = command line, $2 = pid (optional).
_deck_title() {
    emulate -L zsh; setopt extendedglob
    local t=stdin c
    if [[ -n $1 ]]; then
        c=${1//[[:space:]]##/ }                     # newlines/tabs -> single spaces
        (( $#c > 32 )) && c="${c[1,31]}…"
        t="stdin ▸ $c${2:+ [$2]}"
    fi
    tmux select-pane -t $TMUX_PANE -T ${t//\#/##}  # -T is format-expanded: escape #
}

# Stamp each command into both output panes so you can tell which output
# belongs to which command (ordering *between* the two streams is lost once
# they go to different devices — the stamp is the only correlation left).
_deck_preexec() {
    [[ -n $DECK_OUT_TTY ]] || return
    # The pid does not exist yet — preexec runs before the fork. So: title now
    # without it, and let a detached subshell look a moment later. The kernel
    # records the terminal's foreground process group (tpgid); its id is the
    # pid of the job's first process. If that is still the shell itself, the
    # command was a builtin or has already finished: leave the title alone.
    _deck_title "$1"
    (
        sleep 0.15
        local pg=${$(ps -o tpgid= -p $$)// /}
        [[ -n $pg && $pg != $$ && $pg != -1 ]] || exit 0
        # Wrapped by deck-tty? Show the real program, not the wrapper.
        [[ $(ps -o command= -p $pg) == *deck-tty* ]] && pg=${$(pgrep -n -P $pg):-$pg}
        _deck_title "$1" $pg
    ) &!
    print -P  -- "%F{244}── %* ❯ ${1//\%/%%}%f"  >$DECK_OUT_TTY
    print -P  -- "%F{244}── %* ❯ ${1//\%/%%}%f"  >$DECK_ERR_TTY
}
# Report non-zero exit status in the stderr pane.
_deck_precmd() {
    local st=$?
    [[ -n $DECK_OUT_TTY ]] && _deck_title
    [[ -n $DECK_ERR_TTY ]] && (( st )) && print -P -- "%F{red}── exit $st%f" >$DECK_ERR_TTY
    return 0
}
_deck_exit() { (( ZSH_SUBSHELL == 0 )) && _deck_off }   # zsh runs zshexit in subshells too

autoload -Uz add-zsh-hook add-zle-hook-widget
add-zsh-hook preexec _deck_preexec
add-zsh-hook precmd  _deck_precmd
add-zsh-hook zshexit _deck_exit

# ------------------------------------------------------- flight follower ----
# Runs before every redraw of the command line, i.e. after every keystroke
# and cursor movement. Work out (man page, option under cursor); if that pair
# changed since last time, repaint the help pane.
_deck_follow() {
    emulate -L zsh
    (( DECK_FOLLOW )) && [[ -n $DECK_HELP_TTY ]] || return 0

    local -a w
    w=( ${(z)LBUFFER} )                        # split like the shell parser would
    local cur=''
    if [[ -n $LBUFFER && $LBUFFER != *[[:space:]] ]]; then
        cur=$w[-1]; w[-1]=()
        cur+=${RBUFFER%%[[:space:]]*}          # rest of the word right of the cursor
    fi

    # Narrow to the simple command the cursor is in: `a | b --x` -> `b --x`
    local -i i start=1
    for (( i = $#w; i >= 1; i-- )); do
        case $w[i] in
            ('|'|'||'|'&&'|';'|'|&'|'&'|'('|'{'|'$('|do|then|else|'!') start=$(( i + 1 )); break ;;
        esac
    done
    w=( ${w[start,-1]} )

    # Skip wrappers and VAR=value prefixes
    local -i wrapped=0
    while (( $#w )); do
        case $w[1] in
            (sudo|doas|command|builtin|exec|noglob|nocorrect|time|nice|nohup|env|here) wrapped=1; shift w ;;
            (*=*) shift w ;;
            (-*)  (( wrapped )) && shift w || break ;;
            (*)   break ;;
        esac
    done
    (( $#w )) || return 0                      # command word not finished yet

    local cmd=${w[1]:t} sub=''
    [[ -n ${aliases[$cmd]} ]] && cmd=${${${(z)aliases[$cmd]}[1]}:t}
    [[ $cmd =~ '^[A-Za-z0-9_.+-]+$' ]] || return 0
    [[ -n $w[2] && $w[2] != -* ]] && sub=$w[2] # git commit -> try git-commit(1)

    local key="$cmd $sub" page
    if (( ! ${+_deck_pages[$key]} )); then
        if   [[ -n $sub && $sub =~ '^[A-Za-z0-9_.+-]+$' ]] && man -w -- $cmd-$sub &>/dev/null; then page=$cmd-$sub
        elif man -w -- $cmd &>/dev/null; then page=$cmd
        else page=''; fi
        _deck_pages[$key]=$page
    fi
    page=$_deck_pages[$key]
    [[ -n $page ]] || return 0

    # Candidate spellings of the option under the cursor
    local -a opts
    case $cur in
        (--?*) opts=( ${cur%%=*} ) ;;
        (-?*)  opts=( ${cur%%=*} )                           # find -name, java -cp
               local lw=${LBUFFER##*[[:space:]]}             # bundled: -la| -> -a
               (( $#lw > 2 )) && opts+=( -$lw[-1] ) ;;
    esac

    local state="$page|$opts"
    if [[ $state != $_deck_last ]]; then
        _deck_last=$state
        _deck_scroll=0
        $DECK_MAN $DECK_HELP_TTY $page 0 $opts 2>/dev/null
    fi
    return 0
}
add-zle-hook-widget line-pre-redraw _deck_follow

_deck_repaint() {
    local -a f; f=( ${(s:|:)_deck_last} )
    [[ -n $f[1] && -n $DECK_HELP_TTY ]] && $DECK_MAN $DECK_HELP_TTY $f[1] $_deck_scroll ${=f[2]} 2>/dev/null
}
_deck_scroll_up()   { (( _deck_scroll -= 10 )); _deck_repaint }
_deck_scroll_down() { (( _deck_scroll += 10 )); _deck_repaint }
_deck_toggle()      { (( DECK_FOLLOW = ! DECK_FOLLOW )); zle -M "man follow: ${${DECK_FOLLOW/1/on}/0/off}" }
zle -N _deck_scroll_up; zle -N _deck_scroll_down; zle -N _deck_toggle
bindkey '^[[1;3A' _deck_scroll_up              # Alt-Up
bindkey '^[[1;3B' _deck_scroll_down            # Alt-Down
bindkey '^[h'     _deck_toggle                 # Alt-h (replaces run-help binding)
