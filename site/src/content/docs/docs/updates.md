---
title: Updates
description: How Phantom updates itself through Sparkle, what the three settings do, and why the first launch is the only manual step.
sidebar:
  label: Updates
---

Phantom updates in place through [Sparkle](https://sparkle-project.org). The
feed is an appcast published as an asset on the repository's own Releases page,
so the Releases page is the whole of the update infrastructure — there is no
server.

Each release publishes two of them, one per build: the universal application
reads `appcast.xml` and the Apple-silicon-only one reads `appcast-arm64.xml`.
The application decides which by counting the architectures in its own
executable, so an update never moves you from one build to the other.

## The settings

**Settings › General** carries the running version, a **Check Now** button and
two switches. Together they spell one configuration value, `auto-update`:

| Value | Behaviour |
|---|---|
| `off` | Never check. |
| `check` | Check in the background and tell you. |
| `download` | Check, fetch ahead of time, install at the next quit. |

A fresh install is seeded with `download`. The seed only fills a key nobody has
set, so `off` survives a launch once you choose it.

## Installing

An update installs when you quit, not while you are working. Phantom does not
restart itself under you or interrupt a running agent.

## What you have to do once

The first copy you install is ad-hoc signed and not notarized, so Gatekeeper
asks you to open it explicitly — see [Install](/docs/install/). Every
version after that arrives through Sparkle and never asks again.

## A consequence worth knowing

macOS ties a privacy permission to the exact signature of the binary that was
granted it. Because each release is signed ad-hoc rather than with a Developer
ID certificate, **an update clears the permissions you granted Phantom** —
screen recording and accessibility among them. Grant them again after an update
if you use a feature that needs them.

## Older versions

Version 0.14.0 and earlier cannot update themselves. Download the current
`.dmg` and replace the application; your configuration and session are
untouched.
