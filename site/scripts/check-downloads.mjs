// Reads the published releases, so the download page describes what a visitor
// can actually get rather than what the repository is currently building.
//
// build.zig.zon declares the version under development, and quoting that beside
// a link to releases/latest states a version nobody can download. The API
// answers with each release's own title and asset list, which settles the
// version, each target's availability, its exact size, and how many times the
// installers were fetched.
//
// Only .dmg assets are counted. appcast.xml sits in the same releases and is
// fetched by every installed copy on each update check, so counting it would
// report update polls as downloads — on v0.20.0 that alone was 9 against 8 real
// installer downloads.
//
// Every field degrades on its own: a target is withheld only when the release
// is known and the asset is absent. If the call fails, the fallback keeps the
// page offering what it offered before, because a hiccup in CI must not hide a
// download that works.

import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

const repo = "ipetinate/phantom";
const fallbackVersion = "0.20.0-beta";
const countFrom = [0, 21, 0];
const out = path.join(import.meta.dirname, "../src/data/downloads.json");

/** Which asset backs each target on the download page. */
const assets = {
  universal: "Phantom.dmg",
  arm: "Phantom-arm64.dmg",
};

const parseVersion = (tag) =>
  String(tag ?? "")
    .replace(/^v/, "")
    .split("-")[0]
    .split(".")
    .map((part) => Number.parseInt(part, 10) || 0);

const atLeast = (tag, floor) => {
  const version = parseVersion(tag);
  for (let i = 0; i < floor.length; i += 1) {
    const part = version[i] ?? 0;
    if (part !== floor[i]) return part > floor[i];
  }
  return true;
};

async function allReleases() {
  const headers = { accept: "application/vnd.github+json" };
  const token = process.env.GITHUB_TOKEN ?? process.env.GH_TOKEN;
  if (token) headers.authorization = `Bearer ${token}`;
  const res = await fetch(`https://api.github.com/repos/${repo}/releases?per_page=100`, {
    headers,
    signal: AbortSignal.timeout(10000),
  });
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
  const body = await res.json();
  if (!Array.isArray(body)) throw new Error("unexpected payload");
  return body.filter((release) => !release.draft);
}

let releases = null;
if (process.env.PHANTOM_SKIP_REGISTRY !== "1") {
  try {
    releases = await allReleases();
  } catch (error) {
    console.warn(`downloads: the releases could not be read (${error.message})`);
  }
}

const release = releases?.find((entry) => !entry.prerelease) ?? releases?.[0] ?? null;

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

const counted = (releases ?? []).filter((entry) => atLeast(entry.tag_name, countFrom));
const total = counted.reduce(
  (sum, entry) =>
    sum +
    entry.assets
      .filter((asset) => asset.name.endsWith(".dmg"))
      .reduce((inner, asset) => inner + (asset.download_count ?? 0), 0),
  0,
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
      counter: {
        known: releases !== null,
        total,
        since: countFrom.join("."),
        releases: counted.length,
      },
    },
    null,
    1,
  ),
);
console.log(
  `downloads: ${version} ${JSON.stringify(targets)} counter=${total} over ${counted.length} release(s) since ${countFrom.join(".")}`,
);
