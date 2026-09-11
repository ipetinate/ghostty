---
title: Git
description: Status and staging in the sidebar, conflicts resolved in the file, split diffs, and branch review against the base.
sidebar:
  label: Git
---

The **Git** pane works on the repository of the terminal that has focus.

## Status and staging

Changed files are listed by state — staged, unstaged, untracked. Stage and
unstage a whole file or a single hunk. Add a path to `.gitignore` from its
context menu. Switch branch from the picker in the pane header.

Every tab row also carries the branch and a dot when the checkout is dirty, so
you see the state without opening the pane. See
[Sidebar and groups](/phantom/docs/sidebar-and-groups/).

## Diffs

Clicking a file opens it as a diff in the editor, split **horizontally or
vertically** — the control is in the corner of the diff. Markdown files can be
read as a rendered preview instead of as a patch.

## Conflicts

A file with conflict markers opens in a resolver in the editor itself, not in a
separate tool: take ours, take theirs, take both, or edit the result by hand,
one conflict at a time. Staging the resolved file is one click in the same
pane.

## Branch review

Branch review lists every commit on the current branch against its base, and
every file those commits touched. Open any of them as a diff. It is for reading
your own branch before you push, without a browser tab.

## What Phantom does not do

Phantom drives `git` and the GitHub CLI; it is not a replacement for either.
Commits, rebases and pushes are yours to run in the terminal — which is one
keystroke away, in the same pane.
