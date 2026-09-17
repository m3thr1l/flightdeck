#!/bin/sh
# Install flightdeck into ~/.config/deck and hook it into zsh and tmux.
# Safe to re-run: files are overwritten, rc lines are added only once.
set -e
src=$(cd "$(dirname "$0")" && pwd)
dst=${XDG_CONFIG_HOME:-$HOME/.config}/deck

mkdir -p "$dst"
install -m 644 "$src/deck.zsh" "$src/deck.tmux.conf" "$dst/"
install -m 755 "$src/deck-man" "$src/deck-tty" "$dst/"

add_line() {   # add_line FILE LINE
    touch "$1"
    grep -qxF "$2" "$1" || printf '%s\n' "$2" >>"$1"
}
add_line "${ZDOTDIR:-$HOME}/.zshrc" "source $dst/deck.zsh"
add_line "$HOME/.tmux.conf"         "source-file $dst/deck.tmux.conf"

[ -n "$TMUX" ] && tmux source-file "$HOME/.tmux.conf" 2>/dev/null || true
echo "Installed to $dst. Open a new zsh inside tmux and run: deck"
