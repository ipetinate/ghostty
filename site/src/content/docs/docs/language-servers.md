---
title: Language servers
description: No language is compiled in. Each one arrives as an extension that declares its server, and Phantom runs it over LSP.
sidebar:
  label: Language servers
---

Since 0.17.0 Phantom has **no built-in table of languages**. Every language
exists because an extension declared it: its file names, its grammar, its
formatter and the server that answers questions about it.

Install a language from the store — see [Extensions](/docs/extensions/).

## What the editor gets from a server

- Hover
- Go to definition, and find references
- Rename symbol
- Completion, with per-language and global settings
- Diagnostics
- Code actions, including fix-all where the server offers one
- Format, when the manifest names a formatter

## Both kinds of diagnostics

Some servers **push** diagnostics as you type. Others declare a diagnostic
provider and answer only when asked. Phantom does both: it reads the server's
capability, and for a pull server it asks on open, after a change, and on
refresh. An "unchanged" report moves the result id and writes nothing; a full
report with an empty item list clears the file.

Either way one writer owns the file's diagnostics, so a server that pushes
behaves exactly as it always did.

## Settings a server asks for

A server that reads its configuration through `workspace/configuration` — ESLint
is the well-known one — gets it from a `settings` block the extension's manifest
declares. A section nobody declared is answered as **null**, not as an empty
object: those are different answers, and inventing the second is how a client
makes a server switch off a feature it would have defaulted on.

## When two extensions claim the same file

Phantom resolves in this order: a user contribution you promoted, then a
bundled one you promoted, then user, then bundled. Ties break on the directory
name. The loser stays listed in Settings, marked as conflicted, so the clash is
visible rather than silent.

## Overriding how a server starts

**Settings › Extensions** lets you replace a server's command, its arguments and
its initialization options, per language. Your override wins over the manifest
and is marked as yours.

An agent can do the same through
[`configure_language_server`](/docs/mcp/), which is why changing a
server's startup is its own MCP capability rather than part of `run`.

## When a server is missing

The editor says so at the top of the file, with the install command the
extension declared, and a **Check Again** button. It does not fail silently.
