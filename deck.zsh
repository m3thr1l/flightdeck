# deck.zsh — source this from ~/.zshrc.   Requires: zsh >= 5.3, tmux >= 3.2
#
#   deck        split the current tmux window into stdout / stderr / man panes
#               around this shell, and redirect this shell's fd 1 and fd 2
#   deck off    restore fds, close the extra panes
#   deck mode [NAME]   show or switch what the right-hand pane follows
#   here CMD    run one command un-split, in the prompt pane (works for functions too)
#   deck-tty CMD   same, but zoomed to the full window (external programs)
#   step SCRIPT [ARGS]  run a shell script one command at a time, source on the right
#   deck ssh HOST  log in to HOST with the remote shell's streams in these panes
#   deck NAME ...  a plugin's subcommand: any function _deck_cmd_NAME
#   Alt-Up / Alt-Down   scroll the follower pane;  Alt-h  toggle following
#   Alt-m       cycle follower modes;   Alt-x   run the current line under step
#   Alt-Enter / Ctrl-]   pick a path with fzf for the word under the cursor
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
: ${DECK_STEP:=${${(%):-%x}:A:h}/deck-step}
: ${DECK_SRC:=${${(%):-%x}:A:h}/deck-src}
# ssh connection sharing. The follower asks remote hosts small questions on
# keystrokes (is there a man page, what is in that directory); without a
# shared connection each one would be a full handshake. Interactive `ssh host`
# opens the master, everything else rides on it; BatchMode keeps a keystroke
# from ever hanging on a password prompt. Set DECK_SSH_OPTS=() to opt out.
(( $+DECK_SSH_OPTS )) || DECK_SSH_OPTS=( -o ControlMaster=auto -o ControlPath=~/.ssh/deck-%C -o ControlPersist=10m )
typeset -ga DECK_SSH_OPTS
: ${DECK_REMOTE_DIR:='$HOME/.config/deck'}     # where `deck ssh` puts the helpers on the far side (expanded there)
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
typeset -g  DECK_MODE=man                     # what the right-hand pane follows
typeset -ga DECK_MODES; DECK_MODES=( man )    # registered modes, in Alt-m order

# ---------------------------------------------------------------- layout ----
deck() {
    emulate -L zsh
    case $1 in
        (off)    _deck_off; return ;;
        (mode)   shift; _deck_mode "$@"; return ;;
        (ssh)    shift; _deck_remote "$@"; return ;;
        (attach) _deck_attach; return ;;
        (?*)     # plugins add subcommands by defining _deck_cmd_NAME (see README)
                 if (( $+functions[_deck_cmd_$1] )); then local c=$1; shift; _deck_cmd_$c "$@"; return; fi
                 print -u2 "deck: unknown subcommand: $1"; return 2 ;;
    esac
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
         select-pane -t $DECK_HELP_PANE -T $DECK_MODE \; select-pane -t $DECK_HELP_PANE -d \; \
         select-pane -t $me             -T stdin  \; \
         set-option -w pane-border-status top \; \
         set-option -w pane-border-format ' #{pane_title} '
    # Prompts that set the terminal title (OSC 2) now write it into the stdout
    # pane, and tmux would retitle that pane. Pane option since tmux 3.4.
    for p in $DECK_OUT_PANE $DECK_ERR_PANE $DECK_HELP_PANE; do
        tmux set-option -p -t $p allow-set-title off 2>/dev/null
    done

    # Keep copies of the original fd 1/2 (zsh picks free fd numbers >= 10),
    # then point 1 and 2 at the other panes' ptys. Every child inherits these.
    # ZLE is unaffected: it talks to the terminal through its own private fd.
    exec {DECK_SAVE_OUT}>&1 {DECK_SAVE_ERR}>&2
    exec >$DECK_OUT_TTY 2>$DECK_ERR_TTY
    export DECK_SAVE_OUT DECK_SAVE_ERR       # deck-tty uses them: see there for why not /dev/tty

    _deck_wrap
}

# Interactive programs get one terminal, not three (see deck-tty).
_deck_wrap() {
    emulate -L zsh
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
        if [[ $c == ssh ]]; then functions[$c]="command ${(q)DECK_TTY} ssh \$DECK_SSH_OPTS \"\$@\""
        else functions[$c]="command ${(q)DECK_TTY} $c \"\$@\""; fi
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
    if [[ -n $TMUX ]]; then
        for p in $DECK_OUT_PANE $DECK_ERR_PANE $DECK_HELP_PANE; do
            tmux kill-pane -t $p 2>/dev/null
        done
        tmux set-option -wu pane-border-status 2>/dev/null
    fi
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
    if [[ -n $TMUX ]]; then tmux select-pane -t $TMUX_PANE -T ${t//\#/##}  # -T is format-expanded: escape #
    else printf '\e]2;%s\a' $t >/dev/tty 2>/dev/null; fi   # remote: tmux reads the title from the stream
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

# ------------------------------------------------------------- follower ----
# The right-hand pane is a slot. What it shows is decided by $DECK_MODE, and
# a mode is a set of functions named _deck_mode_<NAME>_<hook>:
#
#   follow    called from ZLE after every keystroke; work out what to show
#             from $LBUFFER/$RBUFFER and paint it if it changed
#   repaint   redraw the current thing at $_deck_scroll (Alt-Up/Down)
#   enter     (optional) mode became current
#   leave     (optional) mode is being left
#
# Shared state: $_deck_last is whatever the mode uses to detect "unchanged",
# $_deck_scroll a line offset for manual scrolling. Both are reset on switch.
# Register with   DECK_MODES+=( NAME )   after defining the functions.

_deck_mode_call() {                           # _deck_mode_call HOOK [ARGS]
    local f=_deck_mode_${DECK_MODE}_$1; shift
    (( $+functions[$f] )) && $f "$@"
    return 0
}

_deck_mode() {                                # deck mode [NAME]
    emulate -L zsh
    if [[ -z $1 ]]; then print "deck: mode $DECK_MODE (available: $DECK_MODES)"; return 0; fi
    (( $DECK_MODES[(Ie)$1] )) || { print -u2 "deck: no such mode: $1 (available: $DECK_MODES)"; return 1 }
    [[ $1 == $DECK_MODE ]] && return 0
    _deck_mode_call leave
    DECK_MODE=$1 _deck_last='' _deck_scroll=0
    if [[ -n $DECK_HELP_PANE ]]; then
        if [[ -n $TMUX ]]; then tmux select-pane -t $DECK_HELP_PANE -T $DECK_MODE
        else printf '\e]2;%s\a' $DECK_MODE >$DECK_HELP_TTY; fi
        printf '\e[H\e[2J' >$DECK_HELP_TTY   # old mode's picture would be misleading
    fi
    _deck_mode_call enter
}

# Runs before every redraw of the command line, i.e. after every keystroke
# and cursor movement. Gate, then hand over to the mode.
_deck_follow() {
    emulate -L zsh
    (( DECK_FOLLOW )) && [[ -n $DECK_HELP_TTY ]] || return 0
    _deck_mode_call follow
}
add-zle-hook-widget line-pre-redraw _deck_follow

_deck_repaint()     { [[ -n $DECK_HELP_TTY ]] && _deck_mode_call repaint; return 0 }
_deck_scroll_up()   { (( _deck_scroll -= 10 )); _deck_repaint }
_deck_scroll_down() { (( _deck_scroll += 10 )); _deck_repaint }
_deck_toggle()      { (( DECK_FOLLOW = ! DECK_FOLLOW )); zle -M "deck follow: ${${DECK_FOLLOW/1/on}/0/off}" }
_deck_next_mode() {
    local -i i=$DECK_MODES[(Ie)$DECK_MODE]
    _deck_mode $DECK_MODES[$(( i % $#DECK_MODES + 1 ))]
    zle -M "deck mode: $DECK_MODE"            # line-pre-redraw then repaints
}
zle -N _deck_scroll_up; zle -N _deck_scroll_down; zle -N _deck_toggle; zle -N _deck_next_mode
bindkey '^[[1;3A' _deck_scroll_up              # Alt-Up
bindkey '^[[1;3B' _deck_scroll_down            # Alt-Down
bindkey '^[h'     _deck_toggle                 # Alt-h (replaces run-help binding)
bindkey '^[m'     _deck_next_mode              # Alt-m
# macOS: unless the terminal treats Option as Meta, Option-h and Option-m
# arrive as the typed characters ˙ and µ. Accept those too. (Option-arrows
# have no such fallback: set Option as Meta / Esc+ in the terminal profile.)
bindkey $'\xcb\x99' _deck_toggle              # ˙  Option-h
bindkey $'\xc2\xb5' _deck_next_mode           # µ  Option-m

# ------------------------------------------------------------ mode: man ----
# Man page of the command under the cursor, scrolled to the option being
# typed. When the cursor is on a path instead (has a /, starts with ~ or
# host:, or names something in the current directory), the directory listing
# from files mode is shown in its place, and the man page comes back as soon
# as the cursor is on an option again. $_deck_last is tagged M: or F: so the
# two pictures never pass for each other.
_deck_mode_man_follow() {
    emulate -L zsh
    if _deck_path_here; then
        _deck_files_cur || return 0
        local state="F:$_deck_files_host|$_deck_files_dir|$_deck_files_prefix"
        [[ $state != $_deck_last ]] || return 0
        _deck_last=$state _deck_scroll=0
        _deck_mode_files_repaint
        return 0
    fi
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

    local state="M:$page|$opts"
    if [[ $state != $_deck_last ]]; then
        _deck_last=$state
        _deck_scroll=0
        $DECK_MAN $DECK_HELP_TTY $page 0 $opts 2>/dev/null
    fi
    return 0
}
_deck_mode_man_repaint() {
    [[ $_deck_last == F:* ]] && { _deck_mode_files_repaint; return }
    local -a f; f=( ${(s:|:)${_deck_last#M:}} )
    [[ -n $f[1] ]] && $DECK_MAN $DECK_HELP_TTY $f[1] $_deck_scroll ${=f[2]} 2>/dev/null
}
# Is the word under the cursor a path?  A word that is an argument (not the
# command) and has a /, starts with ~ or HOST:, or is the start of a name in
# the current directory.
_deck_path_here() {
    emulate -L zsh; setopt extendedglob
    local cur=${LBUFFER##*[[:space:]]}${RBUFFER%%[[:space:]]*}
    [[ -n $cur && $cur != -* ]] || return 1
    [[ $cur == (*/*|\~*|[A-Za-z0-9_.@-]##:*) ]] && return 0
    [[ $LBUFFER == *[[:space:]]* ]] || return 1        # still the command word
    local -a m; m=( ${~cur}*(N) )
    (( $#m ))
}

# _deck_ssh HOST CMD...   a quiet, non-interactive question over the shared
# connection; fails fast (exit 255) when there is none and auth would prompt.
_deck_ssh() { command ssh $DECK_SSH_OPTS -o BatchMode=yes -o ConnectTimeout=2 -- "$@" }

# --------------------------------------------------------- mode: script ----
# Shows the source of the shell script named on the command line, and while
# `step` runs it, the line about to execute (deck-step paints that itself).
_deck_script_file() {                         # first word on the line that is a readable script
    local -a w; w=( ${(z)LBUFFER}${RBUFFER%%[[:space:]]*} )
    local x f
    for x in $w; do
        f=${x/#\~/$HOME}
        [[ -f $f && -r $f ]] || continue
        [[ $f == *.(sh|bash|zsh) || "$(head -c2 -- $f 2>/dev/null)" == '#!' ]] && { print -r -- $f; return 0 }
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

step() {                                      # step SCRIPT [ARGS...]
    emulate -L zsh
    (( $# )) || { print -u2 "usage: step SCRIPT [ARGS...]"; return 2 }
    local prev=$DECK_MODE rc
    [[ -n $DECK_HELP_PANE ]] && _deck_mode script
    DECK_HELP_TTY=$DECK_HELP_TTY DECK_SRC=$DECK_SRC $DECK_STEP "$@"; rc=$?
    [[ -n $DECK_HELP_PANE ]] && _deck_mode $prev
    return $rc
}
_deck_step_line() {                           # Alt-x: run this command line under step
    [[ -n ${BUFFER//[[:space:]]/} ]] || return 0
    [[ $BUFFER == step\ * ]] || BUFFER="step $BUFFER"
    zle accept-line
}
zle -N _deck_step_line
bindkey '^[x' _deck_step_line                  # Alt-x (replaces execute-named-cmd)
bindkey $'\xe2\x89\x88' _deck_step_line        # ≈  Option-x

# ---------------------------------------------------------- mode: files ----
# Directory listing for the path under the cursor, local or HOST:path (over
# the shared ssh connection), with the first entry matching what has been
# typed so far marked. Alt-Enter opens fzf over that tree and inserts the pick.
typeset -gA _deck_ls                          # "host|dir" -> listing file (remote only)
typeset -g  _deck_files_dir _deck_files_host _deck_files_prefix

_deck_files_cur() {                           # sets _deck_files_{host,dir,prefix} from the cursor word
    emulate -L zsh; setopt extendedglob
    local cur=${LBUFFER##*[[:space:]]}${RBUFFER%%[[:space:]]*} path
    _deck_files_host='' _deck_files_dir='' _deck_files_prefix=''
    local -a w; w=( ${(z)LBUFFER} )
    (( $#w > 1 || ${#cur} )) || return 1      # nothing typed yet
    [[ -n $cur && $#w == 1 && $LBUFFER != *[[:space:]] && $cur != (*/*|\~*|*:*) ]] && return 1  # still the command word
    if [[ $cur == [A-Za-z0-9_.@-]##:* ]]; then _deck_files_host=${cur%%:*}; path=${cur#*:}
    else path=$cur; fi
    case $path in
        (*/) _deck_files_dir=$path ;;
        (*/*) _deck_files_dir=${path%/*}/ _deck_files_prefix=${path##*/} ;;
        (*)   _deck_files_dir='' _deck_files_prefix=$path ;;
    esac
    return 0
}
_deck_files_list() {                          # print the listing file for host|dir (cached when remote)
    local host=$1 dir=$2 key="$1|$2" f
    local cachedir=${XDG_CACHE_HOME:-$HOME/.cache}/deck
    mkdir -p $cachedir
    if [[ -z $host ]]; then
        f=$cachedir/ls.local
        local d=${${dir/#\~/$HOME}:-.}
        [[ -d $d ]] || return 1
        command ls -Ap -- $d >$f 2>/dev/null || return 1
    else
        f=$_deck_ls[$key]
        if [[ -z $f ]]; then
            f=$cachedir/ls.${key//[^A-Za-z0-9_.-]/_}
            # keep a leading ~ unquoted so the remote shell expands it
            local q; if [[ $dir == \~* ]]; then q="~${(q)dir#\~}"; else q=${(q)dir:-.}; fi
            _deck_ssh $host "ls -Ap -- $q" >$f 2>/dev/null || { rm -f $f; return 1 }
            _deck_ls[$key]=$f
        fi
    fi
    print -r -- $f
}
_deck_mode_files_follow() {
    emulate -L zsh
    _deck_files_cur || return 0
    local state="$_deck_files_host|$_deck_files_dir|$_deck_files_prefix"
    [[ $state != $_deck_last ]] || return 0
    _deck_last=$state _deck_scroll=0
    _deck_mode_files_repaint
}
_deck_mode_files_repaint() {
    local f; f=$(_deck_files_list "$_deck_files_host" "$_deck_files_dir") || return 0
    local -i n=0 line=0
    if [[ -n $_deck_files_prefix ]]; then
        n=$(grep -c -- "^${_deck_files_prefix}" $f 2>/dev/null)
        line=$(grep -n -m1 -- "^${_deck_files_prefix}" $f 2>/dev/null | cut -d: -f1)
    fi
    local where=${_deck_files_host:+$_deck_files_host:}${_deck_files_dir:-./}
    $DECK_SRC $DECK_HELP_TTY $f ${line:-0} $_deck_scroll \
        "$where${_deck_files_prefix:+  $_deck_files_prefix*  ($n)}" 2>/dev/null
}
_deck_mode_files_enter() { _deck_ls=() }     # fresh remote listings each time the mode is entered
DECK_MODES+=( files )

_deck_files_pick() {                          # Alt-Enter: fzf over the tree under the cursor, insert the pick
    emulate -L zsh
    (( $+commands[fzf] )) || { zle -M "deck: fzf not installed"; return 1 }
    _deck_files_cur || { _deck_files_dir='' }
    local host=$_deck_files_host dir=$_deck_files_dir pick
    # Paths come out relative to DIR (find from inside it), so the pick is DIR + path.
    # fzf draws on /dev/tty by itself and its stdout is the answer, so it must
    # not go through deck-tty; zoom the prompt pane here instead, the same way.
    local -a fzf; fzf=( command fzf --query="$_deck_files_prefix" --height=100% --exit-0 )
    local unzoom=
    [[ -n $TMUX_PANE && $(tmux display-message -p -t $TMUX_PANE '#{window_zoomed_flag}') == 0 ]] && \
        tmux resize-pane -Z -t $TMUX_PANE && unzoom=1
    if [[ -z $host ]]; then
        pick=$(cd ${${dir/#\~/$HOME}:-.} 2>/dev/null && command find . -mindepth 1 -maxdepth 4 2>/dev/null | sed 's|^\./||' | $fzf)
    else
        local q; if [[ $dir == \~* ]]; then q="~${(q)dir#\~}"; else q=${(q)dir:-.}; fi
        pick=$(_deck_ssh $host "cd $q && find . -mindepth 1 -maxdepth 3 2>/dev/null | head -20000" | sed 's|^\./||' | $fzf)
    fi
    [[ -n $unzoom && $(tmux display-message -p -t $TMUX_PANE '#{window_zoomed_flag}') == 1 ]] && tmux resize-pane -Z -t $TMUX_PANE
    zle reset-prompt
    [[ -n $pick ]] || return 0
    # replace the word under the cursor with the pick
    local lw=${LBUFFER##*[[:space:]]} rw=${RBUFFER%%[[:space:]]*}
    pick=$dir$pick
    local q=${(q)pick}; [[ $pick == \~* ]] && q=${q#\\}   # keep a leading ~ expandable
    LBUFFER="${LBUFFER[1,$#LBUFFER-$#lw]}${host:+$host:}$q"
    RBUFFER=${RBUFFER[$#rw+1,-1]}
}
zle -N _deck_files_pick
bindkey '^[^M' _deck_files_pick               # Alt-Enter (any mode)
bindkey '^]'   _deck_files_pick               # Ctrl-]   (any mode; no Option needed on a Mac)

# ------------------------------------------------------------ remote deck ----
# `deck ssh HOST` logs in with the remote shell's stdout, stderr and follower
# on THESE panes. The placeholder trick crosses the wire: for each pane a
# held `ssh -tt` session gives the remote side a real pty (so isatty() holds
# and colours survive) whose output is this pane's tty. The remote zsh then
# does the same fd redirection the local one does (`deck attach`), with the
# helpers copied to ~/.config/deck over there. Needs zsh and man on HOST.
_deck_remote() {                              # deck ssh HOST [SSH-ARGS...]
    emulate -L zsh
    [[ -n $DECK_OUT_TTY ]] || { print -u2 "deck ssh: turn the deck on first"; return 1 }
    [[ -n $1 ]] || { print -u2 "usage: deck ssh HOST [SSH-ARGS...]"; return 2 }
    local host=$1; shift
    local dir=${DECK_MAN:h} id=$$.$RANDOM rdir=$DECK_REMOTE_DIR

    # Shared connection first: this is the one place that may ask for a password.
    if ! command ssh $DECK_SSH_OPTS "$@" -O check $host 2>/dev/null; then
        print -u2 "deck ssh: opening a shared connection to $host"
        command ssh $DECK_SSH_OPTS "$@" -fN $host >&$DECK_SAVE_OUT 2>&$DECK_SAVE_ERR
        local rc=$? err; local -i i
        for (( i = 0; i < 30; i++ )); do        # the backgrounded master sets up its socket after ssh -f returns
            err=$(command ssh $DECK_SSH_OPTS "$@" -O check $host 2>&1) && break
            sleep 0.1
        done
        (( i < 30 )) || { print -u2 "deck ssh: no shared connection to $host (ssh -fN exited $rc; check: $err)"; return 1 }
    fi
    local out
    if ! out=$(_deck_ssh $host 'command -v zsh' 2>&1); then
        if [[ $out == *zsh* || -z $out ]]; then print -u2 "deck ssh: $host has no zsh"
        else print -u2 "deck ssh: cannot use the shared connection to $host: $out"; fi
        return 1
    fi

    # Helpers, plus a ZDOTDIR that runs the user's own startup files and then attaches.
    tar -C $dir -cf - deck.zsh deck-man deck-src deck-step deck-tty | _deck_ssh $host "
        d=$rdir; mkdir -p \$d/zdot && tar -xf - -C \$d && cd \$d/zdot &&
        printf '%s\n' \"ZDOTDIR=\\\$HOME; [[ -r \\\$HOME/.zshenv ]] && source \\\$HOME/.zshenv; ZDOTDIR=\$d/zdot\" >.zshenv &&
        printf '%s\n' \"ZDOTDIR=\\\$HOME; [[ -r \\\$HOME/.zprofile ]] && source \\\$HOME/.zprofile; ZDOTDIR=\$d/zdot\" >.zprofile &&
        printf '%s\n' \"unset ZDOTDIR; [[ -r \\\$HOME/.zshrc ]] && source \\\$HOME/.zshrc; source \$d/deck.zsh; deck attach\" >.zshrc
    " || { print -u2 "deck ssh: could not install helpers on $host"; return 1 }

    # One held pty per pane.
    local -a pids; local s tty
    for s in out err help; do
        case $s in (out) tty=$DECK_OUT_TTY ;; (err) tty=$DECK_ERR_TTY ;; (help) tty=$DECK_HELP_TTY ;; esac
        command ssh $DECK_SSH_OPTS -tt $host "stty -echo; tty >$rdir/tty.$id.$s; exec tail -f /dev/null" \
            </dev/null >$tty 2>/dev/null &!
        pids+=( $! )
    done
    local -i i; local ttys=''
    for (( i = 0; i < 50; i++ )); do
        ttys=$(_deck_ssh $host "cat $rdir/tty.$id.out $rdir/tty.$id.err $rdir/tty.$id.help" 2>/dev/null)
        [[ $ttys == *$'\n'*$'\n'* ]] && break
        sleep 0.1
    done
    if [[ $ttys != *$'\n'*$'\n'* ]]; then
        print -u2 "deck ssh: remote ptys did not come up"; kill $pids 2>/dev/null; return 1
    fi
    # The held sessions have no local tty, so tell the remote ptys how big they are.
    local -a rt; rt=( ${(f)ttys} ); local sz
    sz=$(stty size <$DECK_OUT_TTY);  _deck_ssh $host "stty rows ${sz% *} cols ${sz#* } <$rt[1]" 2>/dev/null
    sz=$(stty size <$DECK_ERR_TTY);  _deck_ssh $host "stty rows ${sz% *} cols ${sz#* } <$rt[2]" 2>/dev/null
    sz=$(stty size <$DECK_HELP_TTY); _deck_ssh $host "stty rows ${sz% *} cols ${sz#* } <$rt[3]" 2>/dev/null

    # The session itself: one terminal (the prompt pane), no zoom. The saved
    # fds, not a fresh open of /dev/tty: with ssh's stdout on a newly opened
    # /dev/tty the remote shell is hung up within a second (macOS, observed).
    command ssh $DECK_SSH_OPTS "$@" -t $host "env ZDOTDIR=$rdir/zdot DECK_REMOTE_DIR=$rdir DECK_REMOTE=$id zsh -il" \
        >&$DECK_SAVE_OUT 2>&$DECK_SAVE_ERR
    local rc=$?
    kill $pids 2>/dev/null
    _deck_ssh $host "rm -f $rdir/tty.$id.*" 2>/dev/null
    _deck_title
    return $rc
}

# Remote side, run by the pushed .zshrc: point this shell at the held ptys.
_deck_attach() {
    emulate -L zsh
    [[ -n $DECK_REMOTE ]] || { print -u2 "deck attach: not a remote deck session (DECK_REMOTE unset)"; return 1 }
    [[ -z $DECK_OUT_PANE ]] || return 0
    local d=${(e)DECK_REMOTE_DIR} s v          # set by `deck ssh` on the local side
    for s v in out DECK_OUT_TTY err DECK_ERR_TTY help DECK_HELP_TTY; do
        [[ -r $d/tty.$DECK_REMOTE.$s ]] || { print -u2 "deck attach: missing $d/tty.$DECK_REMOTE.$s"; return 1 }
        typeset -g $v="$(<$d/tty.$DECK_REMOTE.$s)"
        [[ -w ${(P)v} ]] || { print -u2 "deck attach: cannot write ${(P)v}"; return 1 }
    done
    DECK_OUT_PANE=remote DECK_ERR_PANE=remote DECK_HELP_PANE=remote
    exec {DECK_SAVE_OUT}>&1 {DECK_SAVE_ERR}>&2
    exec >$DECK_OUT_TTY 2>$DECK_ERR_TTY
    export DECK_SAVE_OUT DECK_SAVE_ERR
    _deck_wrap
    printf '\e]2;%s\a' $DECK_MODE >$DECK_HELP_TTY
}
