#!/bin/sh
# Install flightdeck-net into ~/.config/deck-net and hook it into zsh.
# Safe to re-run. Requires flightdeck (deck.zsh sourced first) and python3.
set -e
src=$(cd "$(dirname "$0")" && pwd)
dst=${XDG_CONFIG_HOME:-$HOME/.config}/deck-net
rc=${ZDOTDIR:-$HOME}/.zshrc

command -v python3 >/dev/null || echo "warning: python3 not found" >&2
mkdir -p "$dst"
install -m 755 "$src/deck-hosts" "$dst/"
install -m 644 "$src/net.zsh" "$dst/"

touch "$rc"
grep -q 'deck\.zsh' "$rc" || echo "warning: flightdeck is not sourced in $rc" >&2
line="source $dst/net.zsh"
grep -qxF "$line" "$rc" || printf '%s\n' "$line" >>"$rc"     # appended = after flightdeck's line
echo "Installed to $dst. Open a new zsh inside tmux, run 'deck', then 'deck mode net' and an nmap scan."
