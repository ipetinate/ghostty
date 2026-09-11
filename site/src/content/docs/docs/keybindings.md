---
title: Keybindings
description: The three layers of shortcuts — Ghostty's own, Phantom's remappable commands, and the fixed pane keys.
sidebar:
  label: Keybindings
---

Phantom has three separate sets of shortcuts. Knowing which set a key belongs
to tells you where to change it.

## 1. Phantom's own commands — remappable

Seventeen commands, in **Settings › Keyboard Shortcuts**. Each one can be
rebound, and the settings pane refuses a binding that collides with another.

### File explorer

| Command | Default |
|---|---|
| New file | ⇧⌘N |
| New folder | ⇧⌘M |
| Search workspace | ⌥⌘F |

### Editor

| Command | Default |
|---|---|
| Save | ⌘S |
| Save all | ⇧⌘S |
| Close tab | ⌘W |
| Find in file | ⌘F |
| Format document | ⇧⌘F |
| Trigger suggestions | ⌃Space |
| Quick fix | ⌃. |
| Go to definition | ⌃⌘J |
| Find references | ⌃⌘G |
| Rename symbol | ⌃⌘R |
| Move line up | ⌥↑ |
| Move line down | ⌥↓ |
| Attach line to agent | ⌘K |
| Attach line to agent (picker) | ⇧⌘K |

## 2. Pane keys — fixed

These are not remappable.

| Key | Action |
|---|---|
| ⌥⌘\\ | Switch between the terminal and the editor |
| ⌥⌘1 … ⌥⌘9 | Select the nth open file |
| ⌥⌘← ⌥⌘→ ⌥⌘↑ ⌥⌘↓ | Divide the pane in that direction |

Collapsing the sidebar has no shortcut; it is the button in the title bar.

## 3. Ghostty's terminal actions

Everything the terminal itself does — new window, splits, scrollback, find,
copy and paste, font size — comes from Ghostty and is configured with `keybind`
lines in the configuration file. **Settings › Keyboard Shortcuts** lists about
75 of them, in seven groups, and writes the `keybind` lines for you.

Phantom changes two things in that layer:

- `alt+backspace` deletes the word to the left, whatever `macos-option-as-alt`
  is set to.
- Undo and redo (⌘Z, ⇧⌘Z, ⇧⌘T) never type a literal character into the
  terminal when there is nothing to undo.

The syntax and the full action list are in
[Ghostty's documentation](https://ghostty.org/docs/config/keybind).
