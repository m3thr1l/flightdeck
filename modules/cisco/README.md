# flightdeck-cisco

[flightdeck](../..) for network devices. A switch or router gives you
one byte stream and no man pages, so the deck's tricks do not apply directly.
This plugin recreates them by watching the stream:

```
+------------------------+------------------+
| stdin ▸ sw1 (config)#  |                  |
+------------------------+   the device's   |
| stdout: command output |   answer to ?    |
|                        |                  |
+------------------------+                  |
| stderr: % errors, ^    |                  |
+------------------------+------------------+
```

`net HOST` runs `ssh HOST` under a pty. The prompt and the line you type stay
in the prompt pane; command output goes to the stdout pane; lines the device
flags as errors (`% ...`, the `^` marker line) go to the stderr pane; the
answer to `?` goes to the follower pane. Each command is stamped into the
output panes the way the deck stamps shell commands, the prompt pane's title
follows the device mode, and `terminal length 0` is sent once so nothing
paginates.

**Status: skeleton.** The wrapper works against the fake device in `tests/`
and has not seen real hardware. Prompt detection is written for IOS, IOS-XE
and NX-OS style prompts (`name>`, `name#`, `name(config-if)#`).

## Requirements

flightdeck, zsh, tmux, Python 3.8+ (standard library only).

## Install

From the flightdeck checkout:

```sh
./install.sh --modules cisco
```
## Use

| Command            | Effect |
|--------------------|--------|
| `net HOST [args]`  | ssh to a device with the split above; follower in `cisco` mode |
| `deck mode cisco`  | the follower mode on its own |
| `?` in a session   | the device's help lands in the follower pane, not in the stream |

Devices are never multiplexed: most allow one session per user and no extra
channels, and a lingering shared connection would lock you out. `net` runs
plain `ssh` regardless of the deck's `DECK_SSH_OPTS`.

## Try it without a switch

```sh
deck
net --exec tests/fake-ios
```

Then `show version`, `show ip ?`, `enable`, `conf t`, `interface Gi0/1`,
`no such command`, `end`, `exit`.

## How it works

`deck-net` forks `ssh` on a pty, puts this terminal in raw mode and relays
keys. Device output is split into lines. While the device is at a prompt
("line" state) bytes are the echo of what you type and go to this terminal.
After you press Enter ("output" state) each complete line is classified:
error pattern → stderr pane, otherwise → stdout pane, or → follower pane when
the last key you sent was `?`. An unterminated tail that matches the prompt
pattern means the device is back at the line; that ends output state, sets
the pane title from the prompt's host and mode, and shows the tail here.

## Roadmap

- **Prompt detection on real devices.** IOS, IOS-XE, NX-OS, JunOS, Arista
  EOS each differ. Collect prompts, `--more--` handling, and login banners.
- **Route `ssh switch` automatically.** `DECK_NET_HOSTS` patterns exist and
  `_deck_net_ssh` matches them, but flightdeck's `ssh` shadow needs a hook
  before this can be wired in.
- **Live CLI help in the follower** as you type, not only on `?`: ask the
  device `... ?` on a second channel where the platform allows it, cached per
  platform and version.
- **Config diff on `end`**: snapshot `show running-config` on entering config
  mode, diff in the follower on leaving it, remind if not written.
- **Guard rails**: pre-flight warnings in the stderr pane for `reload`,
  `write erase`, or shutting the interface you came in on.
- **Structured show output** via TextFSM / ntc-templates in the stdout pane.
- **Fan-out**: one command to several devices, one stamped block per host.
- **mystory markers**, so sessions are recorded per command like shell
  commands are.

## License

MIT
