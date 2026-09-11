---
title: Configuration
description: Two files, where they live, the keys Phantom adds, and the defaults it changes.
sidebar:
  label: Configuration
---

Phantom reads Ghostty's configuration format — `key = value`, one per line —
from its own directory.

## Where

| | |
|---|---|
| Directory | `$XDG_CONFIG_HOME/phantom/`, default `~/.config/phantom/` |
| Yours | `config` — hand-edited, never rewritten |
| The app's | `gui-settings` — everything the Settings window writes |

`config` is yours. Phantom appends exactly one line to it, a `config-file`
directive that pulls in `gui-settings`, and nothing else. Values in
`gui-settings` are read after yours, so the Settings window wins on a key you
both set — move a value into `config` and delete it from the settings pane to
keep it.

A build whose bundle identifier is not `com.ipetinate.phantom` uses a directory
of its own. See [Build from source](/docs/build-from-source/).

## The keys Phantom adds

| Key | Type | Default | Meaning |
|---|---|---|---|
| `sidebar` | bool | `false`, seeded `true` | Show the sidebar and hide the native tab bar. macOS only. |
| `sidebar-width` | integer | `480` | Sidebar width, in points. |

## The defaults Phantom changes

| Key | Ghostty | Phantom |
|---|---|---|
| `background-opacity` | `1.0` | `0.85`, seeded `0.70` |
| `background-blur` | off | radius `50`, seeded `80` |

"Seeded" is the value a fresh install writes into `gui-settings`; the other is
the compiled default that applies when nobody wrote the key.

## Everything else

About 211 options — font, cursor, scrollback, shell integration, keybinds,
window behaviour, colours — come from Ghostty unchanged. They are documented in
[Ghostty's own reference](https://ghostty.org/docs/config/reference), and the
same text is in `man 5 ghostty`.

Only put keys Ghostty knows in `gui-settings`. An unrecognised key there raises
a configuration error on launch.

## Errors

A bad value does not fail silently: Phantom reports the file, the line and the
key, and carries on with the previous value.
