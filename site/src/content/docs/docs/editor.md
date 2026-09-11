---
title: The editor
description: Open a file beside the terminal that produced it — grammars, minimap, workspace search, splits, format on save, and the viewers.
sidebar:
  label: The editor
---

Phantom's editor lives in the same pane as the terminal. A file is a tab beside
`build` or `dev`, not a separate application.

## Opening a file

- Click it in the **Files** pane.
- Click a path in the **Git** pane.
- Press ⌘K on a terminal line that names a file, or ⇧⌘K to pick from the lines
  it found.
- Ask an agent, through [`open_file`](/docs/mcp/).

Where a file lands — the same cell, or a new one — follows the destination
setting in Settings.

## What the editor does

- **Syntax grammars** — TextMate grammars, matched with Oniguruma, contributed
  by extensions rather than compiled in.
- **A minimap** down the right edge.
- **Workspace search** (⌥⌘F) across the folder, and in-file find (⌘F).
- **Format on save**, through a formatter an extension declared — Prettier for
  the web languages, and one per language for the rest.
- **Move a line or a selection** with ⌥↑ and ⌥↓.
- **Undo across launches** — the history survives closing the file, and closing
  the app.
- **Hot exit** — an unsaved file is kept, not lost, and comes back as it was.

## Splitting

⌥⌘← ⌥⌘→ ⌥⌘↑ ⌥⌘↓ divide the pane in that direction and put the current file in
the new cell. ⌥⌘1 through ⌥⌘9 select the nth open file. ⌥⌘\\ switches between
the terminal and the editor.

The grid remembers itself: a window restored from a previous session comes back
with the same cells and the same files in them.

## More than text

| Kind | What opens |
|---|---|
| Markdown | A preview with scroll sync, beside the source |
| Image, PDF, SVG | A viewer, at the right size |
| CSV | A table |
| A file with conflict markers | A conflict resolver, in place |
| A file an extension claims | That extension's own editor — see [Writing an extension](/docs/extensions-authoring/) |

## Diffs

A changed file opens as a diff, split horizontally or vertically, from the Git
pane. See [Git](/docs/git/).
