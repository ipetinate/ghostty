const root = import.meta.env.BASE_URL.replace(/\/+$/, "");

export function url(path: string): string {
  const clean = path.replace(/^\/+/, "");
  return clean.length === 0 ? `${root}/` : `${root}/${clean}`;
}

export const repo = "https://github.com/ipetinate/phantom";
export const registry = "https://github.com/ipetinate/phantom-extensions";
export const dmg = `${repo}/releases/latest/download/Phantom.dmg`;
export const dmgArm64 = `${repo}/releases/latest/download/Phantom-arm64.dmg`;
export const releases = `${repo}/releases`;
export const ghostty = "https://ghostty.org";

/* The version a visitor can download comes from the release itself —
   see scripts/check-downloads.mjs and src/data/downloads.json. */
export const minMacOS = "13";
export const mcpToolCount = 25;
export const agentCount = 6;
