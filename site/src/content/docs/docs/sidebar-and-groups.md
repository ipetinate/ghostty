---
title: Sidebar and groups
description: How the sidebar replaces the tab bar, how a group claims a project folder, and what each tab row reports.
sidebar:
  label: Sidebar and groups
---

With `sidebar = true` Phantom hides the native macOS tab bar and puts every
terminal in a list down the side of the window. The list is the fork.

## The five panes

A rail at the top of the sidebar selects one pane at a time:

| Pane | What it holds |
|---|---|
| **Terminals** | Every open terminal, grouped |
| **Files** | A file explorer for the workspace |
| **Git** | Status, staging and branch review — see [Git](/phantom/docs/git/) |
| **Worktrees** | One section per repository — see [Worktrees](/phantom/docs/worktrees/) |
| **Extensions** | What is installed — see [Extensions](/phantom/docs/extensions/) |

The sidebar collapses with the button in the title bar. Its width is
`sidebar-width`, in points.

## Groups

A group is a section in the Terminals pane. There are two kinds.

**A manual group** holds the tabs you put in it, and nothing else.

**A project group** names a folder, and claims every terminal whose working
directory is that folder or anything under it. You never assign a tab: open a
terminal in the project and it is already in the right section.

A project group still works with no tabs in it, because it knows its root —
that is what lets its header offer *New Terminal in Worktree* before its first
terminal exists.

A group carries a name, an optional second line, an icon (an SF Symbol or a
single emoji), and a colour that tints the whole section.

### Moving a tab

Dragging a tab into another section assigns it explicitly, and an explicit
assignment beats a project rule. Dragging it out marks it ungrouped, which also
beats the rule — a tab you removed from a group does not silently come back.

## What a tab row reports

Every row states where its terminal stands. Each field can be turned off in
Settings.

- **The directory**, shortened.
- **The branch**, with a dot when the checkout has uncommitted changes.
- **The open pull request** for that branch, clickable, when there is one.
- **A dev-server port**, as a clickable `:3000` tag, the moment the process in
  that tab binds a port. Detection reads the process and its listening sockets,
  not a configuration file, so it works for any framework with no setup.
- **The agent's state** — see [Agents](/phantom/docs/agents/).
- **The worktree**, when the tab is in one.

## The project's pull requests

A project group's header opens a list of every open pull request across every
repository under its root — a workspace folder holding several repositories
included, not just the one a tab happens to be open in. It needs the GitHub CLI
(`gh`) authenticated.
