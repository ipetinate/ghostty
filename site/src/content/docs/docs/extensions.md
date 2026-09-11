---
title: Extensions
description: Install languages, formatters, themes, icon packs and agents from the registry, and know what is verified before anything is unpacked.
sidebar:
  label: Extensions
---

Phantom's languages, formatters, themes, icon packs and agent definitions are
not compiled into the binary. They are extensions, installed from a registry.

## The store

**Settings › Extensions** lists what the registry offers, filtered by kind —
All, Languages, Formatters, Themes, Icons, Agents — and sorted by name, by
recently updated, or by publisher.

Everything the store lists is also browsable on this site, at
[Extensions](/extensions/) — the same index, the same document pages.

The registry is [ipetinate/phantom-extensions](https://github.com/ipetinate/phantom-extensions).
Its index is a single JSON file published as a release asset, so the store is a
plain HTTPS fetch with no service behind it.

## What is checked before an install

Every entry in the index carries, for each asset, a **URL, a sha256 and a byte
count** — all three required. An entry missing any of them is rejected; there
is no "download and hope".

On install Phantom verifies the size and the digest, then unpacks. The archive
reader refuses absolute paths, `..`, symlinks and unsafe characters, so an
archive cannot write outside its own directory. Extensions land in
`~/.config/phantom/extensions/`, one directory each.

An extension also declares a **minimum Phantom version**. Below it, the store
says so instead of installing something that cannot run.

## Reading before installing

Each extension has a document page — `extension.mdx` — rendered in the store
without downloading the code: browsing costs a small document, not the package.

The page is rendered in a web view with a strict content security policy, no
network access and no inline scripts. It is a document, never executed.

## Suggestions

Phantom offers what a file needs instead of waiting to be asked. Two things
raise a suggestion, both drawn as a card in the bottom-right of the pane.

**A file nothing claims.** Open one and, if no installed extension handles that
file type, the card names the extensions in the registry that do, with an
Install button. Once the extension is in, the card comes back only if the
extension still needs a program that is not on your `PATH` — a language server
or a formatter — with the install command the extension itself declared.

**A project that asks for extensions.** A repository can ship its own list at
`.phantom/suggestions.json`, read from the terminal's directory upwards. The
card shows every suggested extension's icon and installs all of them in one
press.

```json
{
  "extensions": ["phantom.rust", "phantom.toml"],
  "message": "The toolchain this repository is built with."
}
```

`extensions` holds registry ids, and anything already installed is left out of
the card. `message` is optional and replaces the list of names in the card.

A dismissed card stays dismissed for the rest of the session.

## Trust

A manifest that declares a **server** or a **formatter** asks to run a program
on your machine. Phantom records a trust decision, keyed to a hash of the
manifest bytes, and asks again when the manifest changes.

The record lives in `UserDefaults`, deliberately not beside the manifest: the
extension directory is writable by whatever put the manifest there, so a trust
decision stored alongside would be one the author could grant themselves.

## Writing one

See [Writing an extension](/docs/extensions-authoring/).
