#!/usr/bin/env bash
# prompt.sh — HARNESS_PROMPT and `pane stdin` after harness_start, then
# HARNESS_PROMPT and the one pane left after `deck off`.
set -u
. "$FLIGHTDECK/tests/harness.sh"
harness_start
echo "before-prompt=$HARNESS_PROMPT"
echo "before-stdin=$(pane stdin)"
t "deck off"
echo "after-prompt=$HARNESS_PROMPT"
echo "after-panes=$(T list-panes -F '#{pane_id}' | tr '\n' ' ' | sed 's/ $//')"
harness_stop
