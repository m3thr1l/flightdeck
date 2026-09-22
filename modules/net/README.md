# flightdeck-net

[flightdeck](../..) for network tools: nmap, arp, tcpdump and
friends. The idea is that the thing under your cursor is a host, the way
the man follower treats it as a command and the files mode as a path.

```
+------------------------+-------------------------------+
| stdin ▸ nmap -sV 10.0.0.1                              |
+------------------------+  host  10.0.0.1               |
| stdout                 |  10.0.0.1  router.lan         |
|                        |    mac   00:11:22:33:44:55    |
+------------------------+    seen  3h ago by nmap       |
| stderr                 |    22/tcp open ssh OpenSSH 8.9|
+------------------------+-------------------------------+
```

Three pieces:

- **A host inventory.** SQLite under `~/.local/share/deck-net`. Every run of
  a tool in `DECK_NET_TOOLS` (nmap, arp, arp-scan by default) feeds it: while
  the tool runs the stdout pane is copied through tmux pipe-pane, and when it
  ends the copy is parsed in the background. `deck hosts` lists and searches
  it, `deck hosts show HOST` prints a card, `deck hosts ingest FILE` parses
  saved output.
- **An address-aware follower.** `deck mode net`: when the cursor is on an
  IPv4 address, a CIDR, a MAC, or a dotted name the inventory knows, the pane
  shows that host's card (or the known hosts in the subnet). Otherwise it is
  the man follower.
- **Live summaries** while a tool runs: not built yet, see below.

**Status: day one.** Parsers for nmap (normal and greppable output) and
`arp -a` on macOS and Linux. Nothing here runs on a command's critical
path: the hooks only start and stop pipe-pane.

## Requirements

flightdeck with `deck NAME` subcommand dispatch, zsh, tmux, Python 3.8+
(standard library only).

## Install

From the flightdeck checkout:

```sh
./install.sh --modules net
```
deck hosts ingest tests/nmap.txt
deck hosts ingest tests/arp.txt
deck hosts list
deck mode net
```

then type `ssh 10.0.0.1` and watch the pane.

## Roadmap

- **Live summaries.** A summariser reading the pipe-pane copy every second
  while tcpdump or a long nmap runs: packets per protocol, top talkers, new
  hosts this run; hosts done and ports found so far.
- **More parsers.** tcpdump (who talked to whom), dig and the resolver, DHCP
  leases, mtr, `ip neigh`; `deck net` device `show` output from
  flightdeck-cisco.
- **Filter syntax help.** Cursor inside a tcpdump or tshark expression → the
  matching section of pcap-filter(7).
- **MAC vendor lookup** from a local OUI table when the tool did not print one.
- **Address-awareness in the man mode itself**, once flightdeck offers a
  follower hook, so no mode switch is needed.

## License

MIT
