# flightdeck-step

Run a script one line at a time inside [flightdeck](../..), with its
source on the right and everything it does, including what it tries to hide,
in the output panes.

```
+------------------------+------------------+
| stdin ▸ deck step x.sh |  x.sh:7  [n]ext  |
+------------------------+                  |
| ── x.sh:7 ❯ x=$(hostname)                 |
|    x = mybox           |>  7 x=$(hostname)|
+------------------------+   8 echo "$x"    |
| ── x.sh:7 ❯ x=$(hostname)                 |
+------------------------+------------------+
```

`deck step SCRIPT [ARGS]`, or Alt-x on a typed command line, runs a shell
script (sh, bash, zsh) or a Python script. Before every line the runner stamps
`── file:line ❯ source` into both output panes, paints the source around that
line in the follower pane with a marker, and waits for a key: `n`, Enter or
space for the next line, `c` to run on without stopping, `q` to abort
(exit 130).

## Requirements

flightdeck with `deck NAME` subcommand dispatch, zsh, bash; python3 for
Python scripts.

## Install

From the flightdeck checkout:

```sh
./install.sh --modules step
```
## What you see

**Shell scripts** run under a `DEBUG` trap in a fresh bash or zsh chosen from
the shebang. Line numbers inside functions are absolute in both shells.
Output the script sends to `/dev/null` goes to the panes instead (a copy of
the script is run in which `>/dev/null` and `2>/dev/null` point at the
script's real stdout and stderr; same basename, same line numbers, `$0`
untouched), commands inside `$(...)` are stepped too, and after an
assignment that captures a command the value it received is printed under
the stamp.

**Python scripts** run as `__main__` under `sys.settrace`. Only lines of the
script itself stop, not the modules it imports. After an assignment the
names it bound are printed with their values from the frame. Output the
script writes through `sys.stdout` or to a file it opened itself is not
intercepted.

`deck mode script` on its own shows the source of any script named on the
command line as you type, so you can read it before running it.

## Try it

```sh
deck
deck step tests/t.sh
deck step tests/t.py
```

## License

MIT
