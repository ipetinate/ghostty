---
title: Build from source
description: Build Phantom with Zig and Xcode, run the checks, and know which build writes where.
sidebar:
  label: Build from source
---

Phantom builds exactly like Ghostty does. Read
[`HACKING.md`](https://github.com/ipetinate/phantom/blob/main/HACKING.md) in the
repository for the full toolchain setup; this page covers what is specific to
the fork.

## Build

```sh
git clone https://github.com/ipetinate/phantom.git
cd phantom
zig build -Doptimize=ReleaseFast
```

The macOS application bundle is produced by an `xcodebuild` step that
`zig build` drives. Skip it when you only need the core:

```sh
zig build -Demit-macos-app=false
```

Run `xcodebuild` from `macos/`, never from the repository root: run at the root
it writes `GhosttyKit.xcframework` into the working directory and the next build
fails with "Multiple commands produce".

## Checks

```sh
zig fmt --check .
swiftlint lint --strict macos/Sources
zig build test -Dtest-filter=<name>
```

`zig build test` without a filter is slow. The full suite, the Swift suite and
the macOS build all run in CI on every pull request.

## A development build writes somewhere else

A build whose bundle identifier is not `com.ipetinate.phantom` is treated as a
variant, and everything it writes carries the variant's name:

| | Release build | Debug build |
|---|---|---|
| Configuration | `~/.config/phantom/` | `~/.config/phantom-debug/` |
| State | `…/com.ipetinate.phantom/` | `…/com.ipetinate.phantom.debug/` |
| MCP socket | `…phantom.sock` | `…phantom.debug.sock` |
| Agent hooks | `phantom-*.sh` | `phantom-debug-*.sh` |

On its first launch a variant copies your `config` and `gui-settings` across —
a copy, never a move, and never over a file that already exists. So a build you
made cannot write over the configuration of the build you use.

## Version

`build.zig.zon` declares the version and `MARKETING_VERSION` in the Xcode
project repeats it. CI fails when the two disagree, because Sparkle compares the
Xcode copy against the appcast to decide whether an update is newer.
