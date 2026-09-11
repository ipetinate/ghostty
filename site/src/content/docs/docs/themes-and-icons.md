---
title: Themes and icons
description: The theme catalogue, the inline creator, file icon packs, framework-aware icons, and the alternate app icons.
sidebar:
  label: Themes and icons
---

## Terminal themes

Phantom ships the full Ghostty catalogue plus its own, and the app's own chrome
— Settings, About, the theme browser — follows the active theme instead of the
system light or dark setting. Choosing a dark theme does not leave you with a
white settings window.

A fresh install starts on **Dracula by Phantom**, written to
`~/.config/phantom/themes/` as a real file rather than referenced by name.

### Creating one

The theme creator is inline, with a live preview: edit the background, the
foreground, the cursor, the selection and the sixteen palette entries, and see
a terminal repaint as you go. What you make is written to your themes
directory and can be shared as a plain file.

### Materials and opacity

The window is translucent over an `NSVisualEffectView`. Two materials —
**Soft** and **Deep** — and an opacity slider. A fresh install starts on Deep at
0.45.

## File icons

Icon packs come from extensions. Any SVG-based VS Code icon theme works: put
the extension's folder in `~/.config/phantom/icon-themes/`, one directory per
theme, each with its own `icon-theme.json`.

A pack declares both halves — the light one and the dark one — and Phantom uses
the one that matches the active theme.

### Icons that read the project

A suffix does not always say which framework wrote the file. React, Solid,
Preact and Qwik all write `.tsx`; `user.service.ts` is Angular in one project
and NestJS in another.

Phantom reads the nearest `package.json` walking up from the file and picks the
icon from the project's dependencies. A `.tsx` in a project that depends on
`solid-js` wears Solid's icon.

## The application icon

Nine alternate application icons ship with the app, including five Ghostty
tributes. Pick one in **Settings › Appearance**; the Dock, the switcher and the
Finder follow immediately.

## Fonts

A font picker searches every font installed on the machine, with a live
preview, and keeps two separate choices: one for the terminal, one for
Phantom's own interface.
