---
title: Worktrees
description: Create or adopt a git worktree from the sidebar, run a setup command in it, and let the editor follow when a terminal switches.
sidebar:
  label: Worktrees
---

A git worktree is a second checkout of the same repository, on another branch,
in another directory. Phantom manages them from the sidebar so running two
branches at once does not mean two clones.

## The pane

The **Worktrees** pane shows one section per repository in the workspace, each
listing the main checkout and every worktree of it. Sections are keyed by the
repository's common root, so every worktree of a repository shares one list no
matter which of them a terminal is open in.

## Creating and adopting

- **Create** makes a branch and a checkout under the managed root.
- **Adopt** takes a worktree you made yourself with `git worktree add` and
  brings it under Phantom's management.

The managed root defaults to `~/.phantom/worktrees`, laid out as
`<repo>/<branch>`. Change it in **Settings › Worktrees**.

## Setup, per repository

A fresh checkout is rarely ready to run: it has no `node_modules`, no `.env`,
no build output. Per repository you can declare:

- **A command** to run in the new worktree — `pnpm install`, `make deps`.
- **Files to copy** from the main checkout — gitignored paths, an `.env`, a
  prebuilt artifact.

Both run when a worktree is created, so the checkout is usable when it appears.

## Switching a terminal

Switch a terminal's worktree from its row, its group header, or the toolbar.
The terminal changes directory, and **the open editor tabs follow it**: the
same file, in the other checkout.

A file with no counterpart on the other side — one that exists only on this
branch — opens read-only and says why, rather than pretending it moved.

## Locks, prune and removal

The pane reports a locked worktree and its reason, repairs a worktree whose
administrative files moved, and prunes the ones whose directory is gone.
Removing a worktree is a real deletion of a working directory, and forced it
deletes one with uncommitted work in it — which is why an agent needs its own
`worktree` capability to do it. See [The MCP server](/docs/mcp/).
