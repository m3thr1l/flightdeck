#!/bin/sh
# Install flightdeck-step into ~/.config/deck-step and hook it into zsh.
# Safe to re-run. Requires flightdeck (deck.zsh sourced first); python3 for Python scripts.
set -e
src=$(cd "$(dirname "$0")" && pwd)
dst=${XDG_CONFIG_HOME:-$HOME/.config}/deck-step
rc=${ZDOTDIR:-$HOME}/.zshrc

mkdir -p "$dst"
install -m 755 "$src/deck-step" "$src/deck-step-py" "$dst/"
install -m 644 "$src/step.zsh" "$dst/"

touch "$rc"
grep -q 'deck\.zsh' "$rc" || echo "warning: flightdeck is not sourced in $rc" >&2
line="source $dst/step.zsh"
grep -qxF "$line" "$rc" || printf '%s\n' "$line" >>"$rc"     # appended = after flightdeck's line
echo "Installed to $dst. Open a new zsh inside tmux, run 'deck', then 'deck step SCRIPT'."
