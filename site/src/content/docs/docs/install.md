---
title: Install Phantom
description: Download the DMG, get past Gatekeeper on first launch, and know what the app writes to disk.
sidebar:
  label: Install
---

Phantom ships as two `.dmg` files on the repository's Releases page: a universal
one and an Apple-silicon-only one. There is no Homebrew cask and no installer
script.

## Requirements

| | |
|---|---|
| Operating system | macOS 13 Ventura or later |
| Architecture | Apple silicon and Intel (universal), or Apple silicon alone |
| Disk | About 100 MB for the universal application, about half that for the Apple silicon one |

## Download

Take **Phantom.dmg** from the [latest release](https://github.com/ipetinate/phantom/releases/latest),
open it, and drag Phantom to `/Applications`.

On an Apple silicon Mac you can take **Phantom-arm64.dmg** instead. It is the
same application with the Intel half removed — about half the download, and
nothing else different, since the universal build already runs natively on
Apple silicon. Each build follows its own update feed, so whichever one you
install is the one **Check for Updates** keeps you on.

## First launch

The application is ad-hoc signed and **not notarized**. Double-clicking it the
first time makes Gatekeeper refuse it as coming from an unidentified developer.

Do one of these instead:

- Right-click Phantom in Finder and choose **Open**, then confirm.
- Or clear the quarantine attribute from a terminal:

  ```sh
  xattr -cr /Applications/Phantom.app
  ```

You only do this once. Every later version arrives through
[Sparkle](/phantom/docs/updates/) and never asks again.

## What Phantom writes

| Path | Holds |
|---|---|
| `~/.config/phantom/config` | The configuration file you edit by hand |
| `~/.config/phantom/gui-settings` | Everything the Settings window writes |
| `~/.config/phantom/themes/` | Themes you import or create |
| `~/.config/phantom/icon-themes/` | File icon themes |
| `~/.config/phantom/extensions/` | Installed extensions |
| `~/Library/Application Support/com.ipetinate.phantom/` | Session, sidebar groups, undo history |
| `~/.cache/phantom/` | The MCP socket and per-tab state files |

Phantom keeps its own configuration directory rather than sharing Ghostty's, so
both can be installed on one machine without colliding. See
[Configuration](/phantom/docs/configuration/).

## Uninstall

Delete `/Applications/Phantom.app` and, if you want the state gone too, the four
directories above.
