// Reads the published release, so the download page describes what a visitor
// can actually get rather than what the repository is currently building.
//
// build.zig.zon declares the version under development — 0.21.0-beta while the
// newest release is still v0.20.0 — and quoting that beside a link to
// releases/latest states a version nobody can download. The API answers with
// the release's own title and its asset list, which settles the version, each
// target's availability and its exact size in one call.
//
// Every field degrades on its own: a target is withheld only when the release
// is known and the asset is absent. If the call fails, the fallback keeps the
// page offering what it offered before, because a hiccup in CI must not hide a
// download that works.

import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

const repo = "ipetinate/phantom";
const fallbackVersion = "0.20.0-beta";
const out = path.join(import.meta.dirname, "../src/data/downloads.json");

/** Which asset backs each target on the download page. */
const assets = {
  universal: "Phantom.dmg",
  arm: "Phantom-arm64.dmg",
};

async function latestRelease() {
  const headers = { accept: "application/vnd.github+json" };
  const token = process.env.GITHUB_TOKEN ?? process.env.GH_TOKEN;
  if (token) headers.authorization = `Bearer ${token}`;
  const res = await fetch(`https://api.github.com/repos/${repo}/releases/latest`, {
    headers,
    signal: AbortSignal.timeout(10000),
  });
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
  return res.json();
}

let release = null;
if (process.env.PHANTOM_SKIP_REGISTRY !== "1") {
  try {
    release = await latestRelease();
  } catch (error) {
    console.warn(`downloads: the release could not be read (${error.message})`);
  }
}

/** The title carries the pre-release suffix; the tag never does. */
const version = (release?.name ?? release?.tag_name ?? fallbackVersion).replace(/^v/, "");

const published = Object.fromEntries(
  (release?.assets ?? []).map((asset) => [asset.name, asset.size]),
);

const targets = Object.fromEntries(
  Object.entries(assets).map(([key, name]) => [
    key,
    release
      ? { available: name in published, bytes: published[name] ?? null }
      : { available: true, bytes: null },
  ]),
);

await mkdir(path.dirname(out), { recursive: true });
await writeFile(
  out,
  JSON.stringify(
    {
      checkedAt: new Date().toISOString(),
      known: release !== null,
      version,
      tag: release?.tag_name ?? null,
      publishedAt: release?.published_at ?? null,
      targets,
    },
    null,
    1,
  ),
);
console.log(`downloads: ${version} ${JSON.stringify(targets)}`);
