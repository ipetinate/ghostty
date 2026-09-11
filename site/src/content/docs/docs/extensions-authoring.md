---
title: Writing an extension
description: The extension.json manifest, what it may contribute, the views an extension can draw, and the rules a page cannot get around.
sidebar:
  label: Writing an extension
---

An extension is a directory with an `extension.json` at its root. Nothing is
compiled; the manifest is read at launch and re-read when it changes.

## The manifest

```json
{
  "schemaVersion": 1,
  "id": "solid",
  "name": "Solid",
  "version": "1.2.0",
  "publisher": "phantom",
  "contributes": { }
}
```

The file is capped at 512 KB, and its raw bytes are hashed for the trust
record. An unknown `schemaVersion` keeps the half Phantom understands — the
language definitions — and discards the server and formatter half, reporting
that the extension needs a newer app rather than failing whole.

Unknown keys inside `contributes` are counted and reported in Settings, never
rejected: an extension written for a later Phantom still installs.

## What it may contribute

| Key | What it adds |
|---|---|
| `languages` | File names, suffixes, comment syntax, an icon, a server |
| `servers` | A companion language server for a language somebody else declared |
| `formatters` | A formatter, used by format-on-save |
| `grammars` | A TextMate grammar |
| `themes` | Terminal themes |
| `iconThemes` | A file icon pack, both light and dark halves |
| `agents` | A coding agent definition |
| `views` | A panel or an editor the extension draws itself |

Each key has a declared maximum count.

### A language

```json
{
  "languageId": "solid",
  "extensions": [".tsx"],
  "fileNames": [],
  "lineComment": "//",
  "blockComment": ["/*", "*/"],
  "icon": "solid",
  "server": {
    "command": "typescript-language-server",
    "args": ["--stdio"],
    "installHint": "npm i -g typescript-language-server",
    "initializationOptions": { },
    "settings": { }
  }
}
```

`settings` is what a server reads back through `workspace/configuration`. A
dotted section walks into the object; a section you did not declare is answered
as null. See [Language servers](/phantom/docs/language-servers/).

## Views: an extension that draws

Since 0.19.0 an extension can render a real page inside Phantom. `contributes.views[]`
declares each one, and `surface` says which kind:

- **`sidebar`** — a panel the sidebar rail selects. It declares a placement.
- **`editor`** — an editor bound to `filenamePatterns`, opened for a matching
  file. It declares no placement, and a `sidebar` entry declaring a pattern is
  refused the same way, so the two shapes stay symmetric.

`filenamePatterns` refuses a path separator: an editor claims a **name**, never
a location. `priority: "option"` keeps the text editor the default, because a
third party should not decide how you open a file that is, after all, text.

An editor view is identified by the file it shows, so closing it, reopening it,
the unsaved mark, ⌘W and session restore are the editor's existing behaviour,
not something the extension reimplements.

### What the page can reach

The page is a bundled ES module plus an optional stylesheet, under
`default-src 'none'`. It touches nothing directly. It asks, and the app answers
**only the methods the manifest declared** — the string the author writes is
the string the app compares, with no table in between.

Every path is relative. An absolute path, a `~`, a backslash or a `..` is
refused **before** resolving, and the result is contained twice: on the path,
and again after resolving symlinks.

Three refusals are worth naming, because they are one rule — an installed
extension must not be able to run code you did not ask for:

- **No path segment may begin with a dot.** That closes `.git/hooks/pre-commit`,
  `.github/workflows` and `.envrc`. It is syntactic on purpose: the set of
  dangerous dotfiles is not closed, so a list of names would need an entry per
  tool and still be wrong in between.
- **`workspace.replace` cannot reach the extension's own directory**, whose
  `extension.json` is what grants these methods.
- **`state.write` refuses a key beginning with `$`**, which is where the chosen
  workspace lives.

`workspace.create` and `workspace.replace` are separate declarations, disjoint
rather than nested: one adds a file and refuses an existing path, the other
writes over one and refuses an absent path. An extension that only adds files
cannot overwrite your work, and its `permissions` list says which it asked for.

## Publishing

Push to [ipetinate/phantom-extensions](https://github.com/ipetinate/phantom-extensions).
Its workflow builds the package, computes the digest and publishes the index on
every push to `main`. The download URL follows
`releases/download/<publisher>.<id>-v<version>/<publisher>.<id>-<version>.zip`.

Ship a 128 px icon and an `extension.mdx` — that page is what the store shows
before anybody downloads the code.
