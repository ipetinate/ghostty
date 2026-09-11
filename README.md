<!-- LOGO -->
<h1>
  <p align="center">
      <img src="https://github.com/user-attachments/assets/756ed832-98c8-4c3a-8e66-4e6b9749f27e" alt="Phantom" width="140" />
      <br>Phantom
    </h1>

  <p align="center">
    A Ghostty-powered terminal built around coding agents: tabs grouped by
    project, git/PR/dev-server status on every row, and a Claude Code
    session one click away — on top of the terminal
    <a href="https://ghostty.org">Ghostty</a> already got right.
    <br />
    <a href="https://phantom.nertec.com.br/">Website</a>
    ·
    <a href="https://phantom.nertec.com.br/docs/install/">Documentation</a>
    ·
    <a href="#install">Install</a>
    ·
    <a href="#features">Features</a>
    ·
    <a href="#built-on-ghostty">Built on Ghostty</a>
  </p>
</p>

<img width="1710" height="1073" alt="Screenshot 2026-08-23 at 15 51 26" src="https://github.com/user-attachments/assets/4b199a7b-6ce8-4abe-8d3d-c28cccd96ad2" />



> Phantom is a personal fork of [Ghostty](https://github.com/ghostty-org/ghostty)
> by [Mitchell Hashimoto](https://github.com/mitchellh) and its contributors.
> Everything that makes a terminal a terminal — the renderer, the VT
> emulation, `libghostty` — is theirs, untouched. This fork adds a sidebar, a
> settings app, and the agent-aware workflow around it.

## Why

Ghostty is, as far as I'm concerned, the best terminal available today —
fast, native, standards-compliant, built by people who clearly sweat the
details. I didn't want a *different* terminal. I wanted the same one, with a
workflow built for how I actually use it now: several coding agents running
in parallel, across several projects, and needing to know at a glance which
one needs me, which repo has an open PR, and which dev server is already
running — without alt-tabbing through a dozen indistinguishable tabs.

Phantom doesn't touch the engine. It's the app around it: a sidebar.

## Install

Take **Phantom.dmg** from the
[latest release](https://github.com/ipetinate/phantom/releases/latest) and drag
Phantom to `/Applications`. It needs macOS 13 Ventura or later, and runs on
Apple silicon and Intel.

The app is ad-hoc signed and **not notarized**, so the first launch has one
extra step: right-click Phantom and choose **Open** — or run
`xattr -cr /Applications/Phantom.app` — instead of double-clicking, otherwise
Gatekeeper refuses it as coming from an unidentified developer.

Every later version arrives in place through **Phantom > Check for Updates**.

## Features

- **Grouped tabs** — group terminals manually, or point a group at a project
  folder and it claims every tab opened underneath it automatically.
- **Agent awareness** — a tab shows when its Claude Code session is working,
  waiting on you, or done, right from the sidebar; hooks install with one
  click in Settings.
- **One-click Claude sessions** — start a new terminal already running
  `claude`, in the right working directory, from the sidebar or a group
  header.
- **Git and PR at a glance** — branch name, an uncommitted-changes dot, and
  the open pull request for the current branch, all clickable, on every tab
  row.
- **Dev server detection** — a tab running `next dev` / `vite` / whatever
  gets a clickable `:3000`-style tag the moment the port opens — framework
  agnostic, no config.
- **Project PR list** — a group's header pops up every open PR across every
  repo in that project (workspace folders included), sorted, without a
  browser tab.
- **An editor in the same pane** — open a file beside the terminal that
  produced it: grammars, a minimap, workspace search, format on save, splits
  in any direction, and viewers for Markdown, images, PDF, SVG and CSV.
- **Language servers from a store** — no language is compiled in. Each one
  arrives as an extension that declares its server, its formatter and its
  grammar; hover, definition, references, rename, completion and diagnostics
  follow.
- **Git where the file is** — status and staging in the sidebar, conflicts
  resolved in the file itself, split diffs, and a branch review of every
  commit and file against the base.
- **Worktrees, both directions** — create or adopt a git worktree from the
  sidebar, run a setup command in it, and let the open editor tabs follow when
  a terminal switches.
- **An MCP server** — 25 tools across terminals, groups, the editor,
  diagnostics, language servers and worktrees, each capability granted by you
  and scoped to a tab, a group or everything.
- **An extension store** — languages, formatters, themes, icon packs and
  agents, every download checked against a sha256 before it is unpacked. Since
  0.19.0 an extension can also draw a sidebar panel or an editor of its own.
- **Themes, done properly** — the full curated catalog, an inline theme
  creator with a live preview, and Phantom's own chrome (Settings, About,
  the theme browser) follows whatever theme is active instead of the
  system's light/dark setting.
- **A real font picker** — search across every font macOS has installed,
  with a live preview, and separate fields for the terminal and for
  Phantom's own interface.
- **Native Settings, no config-file spelunking** — every style knob (font,
  cursor, effect, dividers) is a GUI control that writes to a config file
  Ghostty already understands.

The full list, with the release each piece landed in, is in
[`FEATURES.md`](FEATURES.md). Everything above is documented at
<https://phantom.nertec.com.br/docs/install/>.

## Built on Ghostty

[Ghostty](https://ghostty.org) is the entire reason this is fast and
correct: the multi-threaded core, the Metal renderer, the
standards-compliant VT emulation, `libghostty` — none of that is Phantom's.
It's [Mitchell Hashimoto](https://github.com/mitchellh)'s and the Ghostty
contributors', and this fork tracks it so it can keep merging upstream.

If you want the terminal engine itself — performance details, supported
sequences, the roadmap, platform notes — that's all in
[Ghostty's own documentation](https://ghostty.org/docs) and
[`HACKING.md`](HACKING.md), unchanged from upstream.

## Building

Phantom builds exactly like Ghostty does — see [`HACKING.md`](HACKING.md)
for the full setup. Short version, from the repo root:

```shell-session
zig build -Doptimize=ReleaseFast
```

The documentation site lives in [`site/`](site) and is built with Astro and
Starlight; `yarn build` there produces the pages GitHub Pages serves.

## License

MIT, same as Ghostty — see [LICENSE](LICENSE).
