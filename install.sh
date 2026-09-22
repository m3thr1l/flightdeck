#!/bin/sh
# Install flightdeck into ~/.config/deck and hook it into zsh and tmux.
#
#   ./install.sh                    the core only
#   ./install.sh --modules a,b      the core plus modules/a and modules/b
#   ./install.sh --all              the core plus every module
#   ./install.sh --list             what modules there are
#
# Safe to re-run: files are overwritten, rc lines are added only once.
set -e
src=$(cd "$(dirname "$0")" && pwd)
dst=${XDG_CONFIG_HOME:-$HOME/.config}/deck
rc=${ZDOTDIR:-$HOME}/.zshrc

modules=
case ${1:-} in
    --modules) modules=$(printf '%s' "$2" | tr ',' ' ') ;;
    --all)     modules=$(ls "$src/modules") ;;
    --list)    for m in "$src"/modules/*/; do m=${m%/}; m=${m##*/}; printf '%-8s %s\n' "$m" "$(sed -n '3p' "$src/modules/$m/README.md" 2>/dev/null | cut -c1-70)"; done; exit 0 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
esac

add_line() {   # add_line FILE LINE
    touch "$1"
    grep -qxF "$2" "$1" || printf '%s\n' "$2" >>"$1"
}

mkdir -p "$dst"
install -m 644 "$src/deck.zsh" "$src/deck.tmux.conf" "$dst/"
install -m 755 "$src/deck-man" "$src/deck-tty" "$src/deck-src" "$dst/"
add_line "$rc"              "source $dst/deck.zsh"
add_line "$HOME/.tmux.conf" "source-file $dst/deck.tmux.conf"

for m in $modules; do
    [ -d "$src/modules/$m" ] || { echo "install: no such module: $m (see --list)" >&2; exit 1; }
    mkdir -p "$dst/modules/$m"
    for f in "$src/modules/$m"/*; do
        case $f in */README.md|*/tests) continue ;; esac
        if [ -x "$f" ]; then install -m 755 "$f" "$dst/modules/$m/"; else install -m 644 "$f" "$dst/modules/$m/"; fi
    done
    add_line "$rc" "source $dst/modules/$m/$m.zsh"      # after the core's line
done

[ -n "$TMUX" ] && tmux source-file "$HOME/.tmux.conf" 2>/dev/null || true
echo "Installed to $dst${modules:+ with modules: $(echo $modules)}. Open a new zsh inside tmux and run: deck"
