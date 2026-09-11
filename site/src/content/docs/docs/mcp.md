---
title: The MCP server
description: Phantom exposes itself over MCP — 25 tools, a socket every terminal knows, a handshake that checks the caller, and permissions you grant.
sidebar:
  label: The MCP server
---

Phantom is a Model Context Protocol server. An agent running in one of its
tabs can open a file at a line, read another terminal's output, create a
worktree, or ask which diagnostics a language server reported.

## Connecting

Every terminal Phantom opens exports `PHANTOM_MCP_SOCKET`. The client is the
application's own binary, speaking stdio on one side and the socket on the
other:

```sh
/Applications/Phantom.app/Contents/MacOS/ghostty +mcp-server \
  --socket="$PHANTOM_MCP_SOCKET" --client=<your name>
```

**Settings › MCP** writes that entry into an agent's own configuration file —
JSON for most agents, TOML for Codex — so in practice you click a button.

The socket is `~/.cache/phantom/<bundle id>.sock`. A development build has its
own, because the identifier is part of the name.

### The handshake

The first line after connecting is a hello carrying a version, the caller's
process id, the caller's name, and its tab-state file. Phantom checks that
process id against the socket's peer credentials and refuses a mismatch, an
unreadable peer, or a version it does not know. The tab-state file is what
identifies *which tab* the agent is in.

The protocol version is `2025-06-18`, and the server answers three methods:
`initialize`, `tools/list` and `tools/call`.

## Permissions

No tool grants permission. An agent that could widen its own reach would ask
for everything on its first call and nobody would be consulted again.

**Four capabilities:**

| Capability | Covers |
|---|---|
| `read` | Reading a terminal's scrollback — keys, tokens, production output |
| `run` | Typing into an idle terminal |
| `configure` | Changing how a language server starts |
| `worktree` | Creating, moving, repairing, unlocking, pruning or removing a worktree |

**Three scopes**, narrow to wide: `tab`, `group`, `all`. A grant covers a
request when it reaches at least as far.

You answer a sheet. A grant marked *always* is written down; one given for a
single call is not, and dies with the connection. Only one sheet is on screen
at a time, and a tab that was refused is turned away for sixty seconds without
asking you again — an agent that asks in a loop must not train you to click
Allow.

**Settings › MCP** lists every standing grant and revokes any of them.

## The tools

### Terminals

| Tool | Does |
|---|---|
| `list_terminals` | Every tab: id, title, directory, foreground process, idle, dev-server port, group, worktree, agent state |
| `read_output` | The last lines of a terminal's scrollback — needs `read` |
| `create_terminal` | A new tab, in a directory or a worktree, optionally in a group, optionally running an agent |
| `run_command` | Type one command into an **idle** terminal — needs `run` |
| `focus_terminal` | Bring a tab forward |
| `update_terminal` | Its name, icon and colour |

### Groups

`list_groups`, `create_group`, `update_group`, `move_to_group`,
`list_theme_colors`.

### Editor

| Tool | Does |
|---|---|
| `list_panes` | The cells of this window's editor, and what each holds |
| `open_file` | Open a file, optionally at a line |
| `open_file_in_split` | Open it beside what is already showing, dividing the pane |
| `focus_tab` | Bring an open file forward |
| `close_tab` | Close one |
| `reveal_line` | Put the caret on a line, scroll to it, and leave a mark in the gutter |

### Diagnostics and language servers

`list_diagnostics`, `list_language_servers`, `restart_language_server`,
`configure_language_server` — the last needs `configure`.

### Worktrees

`list_worktrees`, `add_worktree`, `remove_worktree`, `tidy_worktrees` — all
need `worktree`.

## What the editor tools need

The editor tools act on **the window the calling agent's terminal is in**.
They find it through the tab-state file in the handshake, so an agent run
outside a Phantom tab gets a plain refusal rather than acting on a window
nobody chose.
