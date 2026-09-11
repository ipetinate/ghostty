// Pulls the extension registry the app itself reads, and stages what the
// store pages need: a trimmed index, and each extension's document bundle.
//
// The index carries every card field inline — icon included, as a data URI —
// so the listing costs no extra request. Only the detail pages need the
// preview zip, which holds `extension.mdx` and its media.
//
// Output is generated, not authored: both targets are gitignored, and the
// build runs this first. Set PHANTOM_SKIP_REGISTRY=1 to build without it.

import { execFile } from "node:child_process";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";

const run = promisify(execFile);

const INDEX_URL =
  "https://github.com/ipetinate/phantom-extensions/releases/download/index/index.json";
const CONCURRENCY = 8;

const root = path.resolve(import.meta.dirname, "..");
const dataFile = path.join(root, "src/data/extensions.json");
const publicDir = path.join(root, "public/extensions");

if (process.env.PHANTOM_SKIP_REGISTRY === "1") {
  if (!existsSync(dataFile)) {
    await mkdir(path.dirname(dataFile), { recursive: true });
    await writeFile(
      dataFile,
      JSON.stringify({ generatedAt: null, extensions: [] }, null, 1),
    );
  }
  console.log("registry: skipped (PHANTOM_SKIP_REGISTRY=1)");
  process.exit(0);
}

async function getJSON(url) {
  const res = await fetch(url, { redirect: "follow" });
  if (!res.ok) throw new Error(`${res.status} ${res.statusText} for ${url}`);
  return res.json();
}

/** The subset of an index entry the pages read. */
function trim(entry) {
  const card = entry.card ?? {};
  return {
    id: entry.id,
    name: entry.name,
    version: entry.version,
    publisher: entry.publisher,
    description: entry.description ?? card.tagline ?? "",
    homepage: entry.homepage ?? null,
    minimumPhantomVersion: entry.phantom ?? null,
    contributes: entry.contributes ?? [],
    categories: entry.categories ?? [],
    languages: entry.languages ?? [],
    tags: card.tags ?? [],
    license: card.license ?? null,
    created: card.created ?? null,
    updated: card.updated ?? null,
    author: card.author ?? null,
    icon: card.iconData ?? null,
    screenshots: (card.screenshots ?? []).length,
    document: card.document ?? null,
    releases: (entry.versions ?? []).length,
    download: entry.download
      ? { url: entry.download.url, bytes: entry.download.bytes }
      : null,
  };
}

/**
 * Which archive to stage.
 *
 * The preview holds the document and its media, which is all a page needs to
 * render — except an icon theme's. That document draws a browser over the
 * theme's own `icon-theme.json` and the SVGs it names, and those ship only in
 * the installable package. Without them the browser renders and then reports
 * that it cannot read the file. So the two icon themes are staged whole; every
 * other extension stays on the preview, which is a tenth of the weight.
 */
function source(entry) {
  const whole = entry.contributes?.includes("iconThemes");
  return { kind: whole ? "package" : "preview", asset: whole ? entry.download : entry.preview };
}

async function stage(entry) {
  const dir = path.join(publicDir, entry.id);
  const stamp = path.join(dir, ".version");
  const { kind, asset } = source(entry);
  const want = `${entry.version} ${kind}`;
  if (existsSync(stamp)) {
    const seen = await readFile(stamp, "utf8").catch(() => "");
    if (seen.trim() === want) return "cached";
  }
  if (!asset?.url) return "no-archive";

  const res = await fetch(asset.url, { redirect: "follow" });
  if (!res.ok) throw new Error(`${res.status} for ${asset.url}`);
  const bytes = Buffer.from(await res.arrayBuffer());

  const zip = path.join(tmpdir(), `phantom-ext-${entry.id}.zip`);
  await writeFile(zip, bytes);
  await rm(dir, { recursive: true, force: true });
  await mkdir(dir, { recursive: true });
  await run("unzip", ["-o", "-q", zip, "-d", dir]);
  await rm(zip, { force: true });
  await writeFile(stamp, want);
  return kind === "package" ? "fetched-whole" : "fetched";
}

async function pool(items, worker) {
  const results = [];
  let cursor = 0;
  const runners = Array.from({ length: CONCURRENCY }, async () => {
    while (cursor < items.length) {
      const index = cursor++;
      try {
        results.push(await worker(items[index]));
      } catch (error) {
        results.push("failed");
        console.warn(`  ${items[index].id}: ${error.message}`);
      }
    }
  });
  await Promise.all(runners);
  return results;
}

console.log("registry: reading index");
const index = await getJSON(INDEX_URL);
const extensions = (index.extensions ?? []).filter((e) => e.id && e.name);
extensions.sort((a, b) => a.name.localeCompare(b.name));

await mkdir(path.dirname(dataFile), { recursive: true });
await writeFile(
  dataFile,
  JSON.stringify(
    {
      generatedAt: index.generatedAt ?? null,
      repository: index.repository ?? null,
      extensions: extensions.map(trim),
    },
    null,
    1,
  ),
);

console.log(`registry: staging ${extensions.length} documents`);
const outcomes = await pool(extensions, stage);
const tally = outcomes.reduce((acc, k) => ((acc[k] = (acc[k] ?? 0) + 1), acc), {});
console.log("registry:", JSON.stringify(tally));
