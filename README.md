# flightdeck

A tmux + zsh cockpit for the command line. One command, `deck`, rearranges the
current tmux window so that the three standard streams each get their own
pane, and a fourth pane follows along in the man page as you type.

```
+------------------------+------------------+
| stdin  ▸ cmd [pid]     |                  |
+------------------------+                  |
| stdout                 |  man follower    |
|                        |                  |
+------------------------+                  |
| stderr                 |                  |
+------------------------+------------------+
```

You type in the top-left pane. Normal output lands in the middle, errors at
the bottom, and the right-hand pane shows the man page of the command under
your cursor, scrolled to the option you are currently typing.

## Requirements

zsh 5.3 or newer, tmux 3.2 or newer, `man` (man-db), and the usual
`grep`/`sed`/`awk`/`ps`/`pgrep`. On Arch Linux:

```sh
sudo pacman -S --needed tmux zsh man-db man-pages procps-ng
```

## Install

```sh
git clone <this repo> && cd flightdeck && ./install.sh
```

The installer copies the files to `~/.config/deck`, adds one `source` line to
`~/.zshrc` and one `source-file` line to `~/.tmux.conf`. Start a new zsh inside
tmux and run `deck`.

## Use

| Command / key        | Effect |
|----------------------|--------|
| `deck`               | Build the layout around the current pane and split the streams |
| `deck off`           | Restore the streams, close the extra panes |
| `deck mode [NAME]`   | Show or switch what the right-hand pane follows (see below) |
| `here CMD`           | Run one command un-split in the prompt pane (works for functions and builtins) |
| `deck-tty CMD`       | Run one external program un-split *and* zoomed to the full window |
| `deck ssh HOST`      | Log in to HOST with the remote shell's streams in these panes |
| Alt-Up / Alt-Down    | Scroll the follower pane |
| Alt-h                | Toggle following |
| Alt-m                | Cycle follower modes |
| Alt-Enter, Ctrl-]    | Pick a path with fzf for the word under the cursor, in any mode |

On a Mac, Alt is the Option key. Option-h and Option-m work as-is (the
typed characters ˙ and µ are bound too), but Option-Up/Down needs the
terminal to send Option as Meta: Terminal.app → Profiles → Keyboard →
"Use Option as Meta key"; iTerm2 → Profiles → Keys → Left Option key: Esc+.
| Mouse wheel / drag   | Scroll and select inside any pane (copies to the system clipboard) |

Editors, pagers and other full-screen programs are detected and run through
`deck-tty` automatically. Extend the list before sourcing `deck.zsh`:

```zsh
DECK_TTY_CMDS+=(lazygit k9s)
```

## How it works

### Splitting the streams

Every tmux pane is backed by its own pseudo-terminal, a device such as
`/dev/pts/7`. A process normally has file descriptors 0, 1 and 2 all open on
the *same* pty, which is why output and errors interleave. `deck` creates the
extra panes running nothing but `sleep infinity` — a placeholder whose only job
is to keep that pane's pty open — asks tmux for each pane's device path, and
then does the equivalent of

```zsh
exec >/dev/pts/OUT 2>/dev/pts/ERR
```

in your interactive shell. Every child inherits those descriptors.

Ptys are used rather than pipes or FIFOs deliberately. A program writing to a
pipe sees `isatty()` fail: colours vanish and stdio switches to block
buffering. Writing to a real pty, programs behave exactly as they would
interactively, and even size their output to the stdout pane.

This depends on zsh. ZLE, its line editor, talks to the terminal through a
private descriptor, so the prompt stays put when fd 1 and 2 move. bash draws
its prompt through stderr and would follow it into the stderr pane.

Once the streams go to different devices there is no ordering between them, so
each command line is stamped with the time into both output panes, and
non-zero exit codes are reported in the stderr pane.

### Interactive programs: `deck-tty`

Full-screen programs assume all their descriptors are one terminal. `less`,
for example, reads keys from `/dev/tty` (the prompt pane) but switches raw
mode on through fd 2 — the stderr pane. The prompt pane stays line-buffered,
and space, arrows and `q` merely echo.

`deck-tty CMD` gives such programs one terminal again: it zooms the prompt
pane to fill the window, runs `CMD` with stdout and stderr on `/dev/tty`, and
unzooms afterwards. The program remains a child of your shell, so environment,
working directory, job control and pipes (`foo | less`) are unaffected.

While the deck is on, `PAGER`, `VISUAL` and `EDITOR` are wrapped in `deck-tty`
so that programs started *by other programs* (git's pager, the commit editor,
man) are covered, and each name in `DECK_TTY_CMDS` is shadowed by a small
function for the ones you type yourself. `deck off` restores everything.

### Follower modes

The right-hand pane is a slot. `DECK_MODE` names what it currently follows;
`man` is the built-in mode. A mode is a set of zsh functions named
`_deck_mode_NAME_HOOK`:

| Hook      | Called |
|-----------|--------|
| `follow`  | from ZLE after every keystroke; decide what to show from `$LBUFFER`/`$RBUFFER` and paint it if it changed |
| `repaint` | on Alt-Up / Alt-Down; redraw the current thing offset by `$_deck_scroll` |
| `enter`, `leave` | optionally, when the mode is switched to or away from |

`$_deck_last` holds whatever the mode uses to notice "nothing changed", and
both it and `$_deck_scroll` are reset on every switch. Define the functions,
then `DECK_MODES+=( NAME )`; `deck mode NAME` and Alt-m pick it up.

Plugins add subcommands the same way: a function `_deck_cmd_NAME` is run by
`deck NAME ...`, so nothing on `$PATH` gets shadowed.

### Plugins

Two things ride on the mode and subcommand hooks and live in their own
repositories: [flightdeck-step](../flightdeck-step) (`deck step SCRIPT`, run a
shell or Python script one line at a time with its source on the right) and
[flightdeck-cisco](../flightdeck-cisco) (`deck net HOST`, the stream split for
network devices). `deck-src`, the painter that puts a file with a marked line
on the follower pane, stays here because `files` mode uses it too.

### Mode: `files`

The man follower is path-aware: when the cursor is on an argument that looks
like a path (has a `/`, starts with `~` or `host:`, or is the start of a name
in the current directory) the pane shows that directory's listing instead,
local or `host:path` over the shared ssh connection, with the first entry
matching what has been typed marked. Move the cursor back to an option and
the man page returns. Alt-Enter or Ctrl-] runs fzf over the tree under the
cursor's word (zoomed) and replaces the word with the pick; this works in
every mode. `deck mode files` keeps the listing up regardless of what is
under the cursor. Remote listings are cached until `files` mode is entered.

### ssh

`deck` shares ssh connections: `DECK_SSH_OPTS` (ControlMaster, a socket under
`~/.ssh`, ControlPersist 10 minutes) is added to the `ssh` you type while the
deck is on, so that later remote questions from the follower ride on the same
connection without a handshake and never prompt. Set `DECK_SSH_OPTS=()` before
sourcing to opt out.

`deck ssh HOST` extends the placeholder trick over the wire: three held
`ssh -tt` sessions give the remote side real ptys whose output is this
window's panes, the helpers are copied to `DECK_REMOTE_DIR` (`~/.config/deck`
on HOST), and a login zsh there runs your own startup files and then
`deck attach`, which redirects its streams the way the local shell does. With
zsh on HOST that is the same code as locally. With only bash, `deck.bash`
does the split differently, since bash draws its prompt and line editing
through stderr: a DEBUG trap points fd 1 and 2 at the panes just before each
command and PROMPT_COMMAND points them back before the prompt, so commands
are split and the prompt never is. Works with bash 3.2. Without a line editor
hook the follower shows the man page of each command as it starts. A host
with neither gets a plain session. `DECK_REMOTE_SHELL=zsh|bash|none`
overrides the choice. The first connection may ask for a password; that opens
the shared connection everything else rides on. Pane titles are set through
OSC 2 escapes since there is no tmux on that side, editors run unzoomed, and
the remote pty sizes are set once, at login.

Programs given the prompt pane as their terminal (`deck-tty`, the remote
session) get the shell's saved copies of its original stdout and stderr,
never a fresh open of `/dev/tty`. Same device, but observed on macOS: with
ssh's stdout on a newly opened `/dev/tty`, the remote shell is hung up within
a second of starting.

### The man follower

ZLE runs a `line-pre-redraw` hook after every keystroke and cursor movement.
The hook splits the text left of the cursor the way the shell parser would,
narrows it to the simple command the cursor is in (after the last `|`, `&&` or
`;`), skips `sudo`/`env`/`VAR=x` prefixes, resolves aliases, and picks a man
page — trying `git-commit` before `git` for `git commit`. It then takes the
option under the cursor; for bundled flags such as `-la` it tries the whole
word first and the last letter second.

Only when the (page, option) pair changes does it call `deck-man`. There is no
pager in the help pane. `deck-man` renders the page once at the pane's width
with formatting preserved, caches a display copy and a plain copy with
identical line numbers in `~/.cache/deck`, greps the plain copy for the
option's definition line, and writes one screenful of the display copy
straight onto the help pane's pty in a single write.

### Pane title

zsh's `preexec` hook fires before the command is forked, so no pid exists yet.
The title is set immediately without one; a detached subshell then looks
150 ms later at the terminal's foreground process group (`tpgid` in `ps`),
whose id is the pid of the job's first process. If that is still the shell
itself the command was a builtin or has already finished. When the foreground
leader is `deck-tty`, its child's pid is shown instead.

### Mouse and clipboard

`deck.tmux.conf` turns tmux mouse support on, since tmux — not the terminal
emulator — owns each pane's scrollback. Copying emits an OSC 52 escape
sequence, which the terminal emulator you are sitting at turns into a
clipboard write; because it travels inside the terminal stream it works over
ssh. Releasing a drag copies without leaving copy mode, so the view does not
snap back to the bottom of a log.

## Known limits

Plugins that assume the deck runs under tmux should check `$TMUX` before
calling it: over `deck ssh` the remote shell has `DECK_OUT_PANE=remote` and no
tmux server. Remote listings and man pages are as of the remote host; the
follower's local cache of remote directory listings is cleared whenever
`files` mode is entered.

`sudo vim` is not caught by the shadow functions; use `deck-tty sudo vim` or
`sudoedit`. `sudo -u USER cmd` confuses the follower, which takes `USER` for
the command. Programs without a man page, and shell builtins, leave the help
pane unchanged. The option search is textual and can land on the wrong line in
unusually formatted pages. Delete `~/.cache/deck` after man pages are updated.
Terminal emulators without OSC 52 support need Shift-drag (Option-drag on
macOS terminals) for native selection; zoom the pane first with prefix + `z`.

## License

MIT
