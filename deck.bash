# deck.bash — the remote side of `deck ssh` when HOST has bash but no zsh.
# Started by deck ssh as:   bash --rcfile deck.bash -i
#
# bash draws its prompt and line editing through stderr, so the shell itself
# cannot live with its fds on the panes. Instead the DEBUG trap points fd 1
# and 2 at the panes just before each command runs, and PROMPT_COMMAND points
# them back at the terminal before the next prompt. Commands inherit the
# redirected fds; the prompt never sees them. Works with bash 3.2 and up.
#
# There is no line editor hook in bash, so the follower shows the man page of
# the command as it starts, not while it is being typed.

# The user's own startup, since --rcfile replaces ~/.bashrc and this is not a
# login shell. A .bash_profile normally sources .bashrc itself.
if [ -r "$HOME/.bash_profile" ]; then . "$HOME/.bash_profile"
else [ -r "$HOME/.profile" ] && . "$HOME/.profile"; [ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc"; fi

_deck_dir=$(eval echo "${DECK_REMOTE_DIR:-\$HOME/.config/deck}")   # the value may hold a literal $HOME
if [ -z "$DECK_REMOTE" ] || [ ! -r "$_deck_dir/tty.$DECK_REMOTE.out" ]; then
    echo "deck: no remote deck session to attach to" >&2
else
    # builtins only from here on: the user's rc may alias cat, date or ls
    read -r DECK_OUT_TTY < "$_deck_dir/tty.$DECK_REMOTE.out"
    read -r DECK_ERR_TTY < "$_deck_dir/tty.$DECK_REMOTE.err"
    read -r DECK_HELP_TTY < "$_deck_dir/tty.$DECK_REMOTE.help"
    exec 8>&1 9>&2                                  # the terminal, kept for the prompt
    export DECK_ACTIVE=1
    export PAGER="$_deck_dir/deck-tty ${PAGER:-less}"
    export VISUAL="$_deck_dir/deck-tty ${VISUAL:-${EDITOR:-vim}}" EDITOR="$_deck_dir/deck-tty ${VISUAL:-${EDITOR:-vim}}"
    for _c in vim nvim vi nano emacs less more most top htop btop watch ssh fzf tig lazygit mc ranger nnn vifm gdb ipython psql mysql; do
        command -v "$_c" >/dev/null 2>&1 && eval "$_c() { command '$_deck_dir/deck-tty' $_c \"\$@\"; }"
    done
    _deck_stamped= _deck_last=
    _deck_debug() {
        case $BASH_COMMAND in _deck_precmd*) return ;; esac
        exec >"$DECK_OUT_TTY" 2>"$DECK_ERR_TTY"
        [ -n "$_deck_stamped" ] && return
        _deck_stamped=1
        local t c w; t=$(command date +%H:%M:%S); c=$BASH_COMMAND
        printf '\033[38;5;244m── %s ❯ %s\033[0m\n' "$t" "$c" >"$DECK_OUT_TTY"
        printf '\033[38;5;244m── %s ❯ %s\033[0m\n' "$t" "$c" >"$DECK_ERR_TTY"
        printf '\033]2;stdin ▸ %s\007' "${c:0:32}" >&8
        w=${c%% *}; w=${w##*/}
        case $w in sudo|command|time|nice|nohup|env) w=${c#* }; w=${w%% *}; w=${w##*/} ;; esac
        if [ "$w" != "$_deck_last" ]; then
            _deck_last=$w
            "$_deck_dir/deck-man" "$DECK_HELP_TTY" "$w" 0 >/dev/null 2>&1
        fi
    }
    _deck_precmd() {
        local st=$?
        exec >&8 2>&9
        [ -n "$_deck_stamped" ] && [ "$st" -ne 0 ] && printf '\033[31m── exit %s\033[0m\n' "$st" >"$DECK_ERR_TTY"
        _deck_stamped=
        printf '\033]2;stdin\007'
    }
    PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_deck_precmd"   # ours last: it must restore the fds
    printf '\033]2;man\007' >"$DECK_HELP_TTY"
    trap _deck_debug DEBUG        # last: from here on every command is the user's
fi
