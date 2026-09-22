#!/bin/sh
# Install mystory into ~/.config/mystory and hook it into zsh.
# Safe to re-run. Requires flightdeck for output capture (works without it,
# recording commands only).
set -e
src=$(cd "$(dirname "$0")" && pwd)
dst=${XDG_CONFIG_HOME:-$HOME/.config}/mystory
rc=${ZDOTDIR:-$HOME}/.zshrc

for dep in python3 tmux fzf; do
    command -v "$dep" >/dev/null || echo "warning: $dep not found (pacman -S $dep)" >&2
done

mkdir -p "$dst"
install -m 755 "$src/mystory" "$dst/"
install -m 644 "$src/mystory.zsh" "$dst/"

touch "$rc"
grep -q 'deck\.zsh' "$rc" || echo "warning: flightdeck is not sourced in $rc; output will not be captured" >&2
line="source $dst/mystory.zsh"
grep -qxF "$line" "$rc" || printf '%s\n' "$line" >>"$rc"     # appended = after flightdeck's line

echo "Installed to $dst. Open a new zsh inside tmux, run 'deck', run a few commands, then 'mystory'."
