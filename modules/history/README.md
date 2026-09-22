# deck history

Shell history you can search, sort and trust: every command is recorded with
its start and end time, exit status, working directory and — when run inside
flightdeck — its stdout and stderr, stored separately.
Records are hash-chained so that edits and deletions are detectable, and the
last *N* (you choose) are kept for review, rerunning, examination and audit.

```
deck history                   the most recent records
deck history nmcli             every time nmcli was run
deck history 10.0.0.5          every command that mentioned that address
deck history -o HomeNet        ...or whose output did
```

## Requirements

zsh, tmux 3.2+, Python 3.8+ (standard library only), fzf, and flightdeck for
output capture. On Arch Linux: `sudo pacman -S --needed python tmux fzf`.

## Install

From the flightdeck checkout:

```sh
./install.sh --modules history
```

## Searching

Every argument is a search term, and all terms must match. A term matches
anywhere in the command line as typed — the program name or any argument — so
names, hostnames and addresses work without special syntax. Matching is
case-insensitive unless the term contains a capital letter.

A term that is a complete IPv4 address only matches that whole address:
`10.0.0.5` does not match `10.0.0.50`. `-w` applies the same whole-word rule to
any term. `-o` also searches captured output; hits are tagged `[out]` or
`[err]`.

Results are always newest first. There is no relevance ranking: the list is a
statement of what happened, in order.

| Flag | Meaning |
|------|---------|
| `-n 200` | how many records to show (default: `deck history config list`) |
| `-o`, `--output` | also search stdout and stderr |
| `-w`, `--word` | whole-word matching |
| `--failed` | non-zero exit status only |
| `--here` | run from the current directory only |
| `--since X` | `today`, `yesterday`, `90m`, `6h`, `3d`, `2w`, `2026-09-17` |
| `--host H` | one host only |
| `--pinned` | pinned records only |
| `--plain` | print the list instead of opening the review window |

When stdout is a pipe or a file the list is printed as plain text
automatically, so `deck history nmcli | wc -l` works.

## The review window

In tmux, `deck history` opens a separate window laid out like the deck: the list at
the top left, the selected record's stdout and stderr below it, and its
details — including whether it passes verification — on the right. Moving
through the list repaints the other three panes. Scroll them with the mouse.
Typing narrows the list (exact substring match, order preserved).

| Key | Action |
|-----|--------|
| Enter | close, and place the command on your prompt to edit — it is not executed |
| Ctrl-R | close, and rerun the command |
| Ctrl-D | diff this run's output against the previous run of the same command |
| Ctrl-P | pin / unpin (pinned records are never pruned) |
| Ctrl-Y | copy stdout to the clipboard |
| Ctrl-O / Ctrl-E | open full stdout / stderr in `less` |
| Esc | close |

## Other commands

```
deck history show N [--raw]     one record in full (--raw replays original colours)
deck history diff N [M]         diff N against M, or against the previous run of the same command
deck history pin N | unpin N
deck history redact N [--cmd]   destroy N's stored output (and, with --cmd, its command line)
deck history verify             check every record and the chain; exit status 1 on any problem
deck history config [KEY NUM]   keep (records retained), list (default list length),
                           cap_mb (per-stream size cap), paint_kb (review replay limit)
```

## Keeping things out

A command typed with a leading space is not recorded at all. So is anything
matching a glob pattern in `MYSTORY_IGNORE`. Commands matching
`MYSTORY_NOOUTPUT` are recorded without their output (by default: `mystory`
itself, so that lists of history do not end up inside the history). Set both
arrays in `~/.zshrc` before the `source` line:

```zsh
MYSTORY_IGNORE=( 'pass *' '*--show-secrets*' )
MYSTORY_NOOUTPUT=( 'mystory' 'mystory *' 'gpg *' )
```

Keyboard input is never recorded. The data directory,
`~/.local/share/deck/history` (or an existing `~/.local/share/mystory`), is created mode 0700.

## How it works

### Capture

flightdeck points the shell's stdout and stderr at two tmux panes. tmux's
`pipe-pane` hands a copy of every byte a pane receives to a command; the module's
is `cat >> logfile`. The programs you run cannot tell: they are still writing
to a real terminal, so colours and buffering are unchanged.

Before and after each command the zsh hooks write an invisible marker — an OSC
escape sequence carrying the record's id — into both panes. tmux does not draw
it, but it lands in the logs. Because the marker travels in the same stream as
the output, its position is exact; byte offsets taken from outside would not
be, since tmux writes the logs slightly behind real time.

The hooks themselves only append a line of text to an events file: one when
the command starts, one when it ends. No process is started on the command's
critical path. After each command a background `mystory ingest` reads new
events, cuts the logs at the markers, and stores each record.

A record therefore exists from the moment the command starts. If the shell
dies, the record remains, marked `lost`, with whatever output had arrived.

### Storage

One SQLite database holds the details of each record; output lives in plain
files, `records/N/{out,err}.{raw,txt}`. `raw` is the exact byte stream, which
replays with colours; `txt` has escape sequences removed, terminal line endings
normalised and redrawn lines (progress bars) collapsed to their final state,
and is what searches and diffs read. Each stream is capped at `cap_mb`,
keeping the beginning and the end.

Search is a scan. The retention cap bounds the table, so a scan of the command
column takes about a millisecond, and a full-text index would split
`10.0.0.5` into `10`, `0`, `0`, `5`.

### Integrity

Each record stores a hash of its details, a hash of each output stream, and a
record hash computed over those plus the previous record's hash. `mystory
verify` recomputes all of it and reports changed details, changed or missing
output, broken links and records deleted outside mystory. Pruned records leave
their position and hash behind, so the chain stays verifiable from the first
record ever made. A redacted record keeps its hashes and its place; its content
is gone and it says so.

This makes tampering *detectable*, not impossible: whoever owns the files can
recompute the whole chain. Guarding against someone with access to the account
requires copying the latest hash somewhere they cannot rewrite; the single
value to copy is `chain_head` in the `state` table.

## Known limits

Full-screen programs run through flightdeck's `deck-tty` draw in the prompt
pane and are recorded with empty output. Output printed by a background job
after its command has ended lands in the next record. The command's own pid is
not recorded, only the shell's. With the deck off, commands are recorded
without output. Only commands run from a zsh with the hooks loaded are seen.

## License

MIT
