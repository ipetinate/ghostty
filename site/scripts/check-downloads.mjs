// Asks the Releases page whether each download actually exists, so the page
// never offers a link that 404s.
//
// A target goes out as "coming soon" only on a definite 404. Any other
// outcome — a timeout, a network error, a 5xx — leaves it offered: a hiccup
// in CI must not hide a download that works.

import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

const repo = "https://github.com/ipetinate/phantom";
const targets = {
  universal: `${repo}/releases/latest/download/Phantom.dmg`,
  arm: `${repo}/releases/latest/download/Phantom-arm64.dmg`,
};

const out = path.join(import.meta.dirname, "../src/data/downloads.json");

async function exists(url) {
  if (process.env.PHANTOM_SKIP_REGISTRY === "1") return true;
  try {
    const res = await fetch(url, {
      method: "HEAD",
      redirect: "follow",
      signal: AbortSignal.timeout(10000),
    });
    if (res.status === 404) return false;
    return true;
  } catch (error) {
    console.warn(`downloads: ${url} could not be checked (${error.message})`);
    return true;
  }
}

const available = {};
for (const [key, url] of Object.entries(targets)) {
  available[key] = await exists(url);
}

await mkdir(path.dirname(out), { recursive: true });
await writeFile(out, JSON.stringify({ checkedAt: new Date().toISOString(), available }, null, 1));
console.log("downloads:", JSON.stringify(available));
