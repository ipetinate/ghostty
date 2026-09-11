---
title: First run
description: What Phantom sets up on a fresh install, and the five steps of the welcome tour.
sidebar:
  label: First run
---

On a fresh install Phantom writes a small set of defaults, then shows a welcome
tour. Nothing here is permanent: every value is a normal setting you can change
later.

## The defaults a fresh install gets

Phantom applies these **only** where you have not set the key yourself.

| Key | Value | Why |
|---|---|---|
| `sidebar` | `true` | The sidebar is the point of the fork; it replaces the native tab bar. |
| `window-save-state` | `always` | Session restore is expected behaviour with grouped tabs. |
| `background-opacity` | `0.70` | The factory look is translucent. |
| `background-blur` | `80` | Together with the opacity, this is the material. |
| `theme` | `Dracula by Phantom` | Written to `~/.config/phantom/themes/` as a real file. |
| `auto-update` | `download` | Check in the background, install at the next quit. |

## The welcome tour

Five steps, in order:

1. **Hero** — what Phantom is, and the version you installed.
2. **Basics** — the sidebar, its panes, and how a terminal becomes a tab.
3. **Tab placement** — where the tab bar sits, and how groups claim tabs.
4. **Theme** — pick a theme and an icon pack.
5. **Agents** — the six supported coding agents, and the one-click hook install.

Turn off **Show at startup** in the bottom-left to stop it appearing again. You
can always reopen it from the Help menu.

## Next

- Point a group at a project folder — [Sidebar and groups](/phantom/docs/sidebar-and-groups/)
- Install a language — [Extensions](/phantom/docs/extensions/)
- Let an agent drive the window — [The MCP server](/phantom/docs/mcp/)
