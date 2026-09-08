# Extension viewer — the document page for extensions

Vendored from [ipetinate/phantom-extensions](https://github.com/ipetinate/phantom-extensions),
package `packages/phantom-mdx`, **0.3.1** (see `VERSION`). This is the page
the Extensions store loads in a `WKWebView` to draw an extension's
`extension.mdx` or `extension.md`: the store passes the document's text and
its folder, the page parses it, checks it against the kit's component list and
renders it, and nothing in the document is ever executed.

## Attribution

> phantom-mdx, copyright (c) 2026 Isac Petinate, licensed under the MIT
> License. See `LICENSE` for the full terms.

The kit's `LICENSE` ships here, beside the files it covers, because the whole
folder is copied into `Phantom.app/Contents/Resources/extension-viewer/`.

## What was copied

- `viewer.html` — `dist/viewer/viewer.html`, byte for byte
- `viewer.js` — `dist/viewer/viewer.js`, byte for byte
- `viewer.css` — `dist/viewer/viewer.css`, byte for byte
- `LICENSE` — the package's MIT text
- `VERSION` — the package version, written by the update script

Digests (`shasum -a 256`) of this copy:

```
7d07fe593c092e696fb3a90630f3f78adebc77665c262fbd1b079efe105f5e13  viewer.html
90e0c6e6660fc653929770285910fbffce6113c54325282115a5165750450804  viewer.js
7081b8fd673c4747eda8ab816032f4e216154371929b12a1ad7a2b19fe862277  viewer.css
```

The page has no network references, no inline scripts and no inline styles,
and declares a Content Security Policy that allows only its own script and
stylesheet, `file:` and `data:` images, `file:` media, and `file:` requests.

That last one is the icon browser: an icon pack names between eight and 1,252
icons in its own `icon-theme.json`, and no page can carry that list by hand, so
the component reads the file out of the staged directory it was given. `file:`
is the whole of the concession — `connect-src` names no host, so nothing off
this machine is reachable — and it is one request per browser, never one per
icon.

## How the app uses it

`ExtensionViewerBundle` finds `viewer.html` in the bundle and copies the three
files into `~/Library/Caches/<bundle id>/extensions/viewer/<version>/` once per
version, because a `WKWebView` may only read files under one directory and the
extensions it draws live in that cache too. `ExtensionDocumentView` loads the
copy, calls `window.phantomViewer.render({ source, baseURL, theme, cover })`
and `setTheme(theme)`, and listens on `webkit.messageHandlers.phantom` for
`ready`, `rendered`, `failed` and `open` — see `ExtensionViewerMessage` for what
each message may carry.

## Updating

Run `dist/macos/update_extension_viewer.sh` from a clean checkout:

- `dist/macos/update_extension_viewer.sh --from <registry>/packages/phantom-mdx/dist/viewer`
  copies a local build and reads the version from the package's `package.json`.
- `dist/macos/update_extension_viewer.sh <version> <sha256>` downloads
  `phantom-mdx-viewer-<version>.zip` from the registry's `viewer` release and
  checks its digest first.

Both rewrite `VERSION` and print the new digests; paste them above. Then run
`ExtensionViewerBundleTests`, and open an extension in the app: the contract in
`ExtensionViewerMessage` is what a new viewer has to keep.
