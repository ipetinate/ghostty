import data from "../data/extensions.json";

export type Extension = {
  id: string;
  name: string;
  version: string;
  publisher: string;
  description: string;
  homepage: string | null;
  minimumPhantomVersion: string | null;
  contributes: string[];
  categories: string[];
  languages: string[];
  tags: string[];
  license: string | null;
  created: string | null;
  updated: string | null;
  author: { name?: string; url?: string } | null;
  icon: string | null;
  screenshots: number;
  document: string | null;
  releases: number;
  download: { url: string; bytes: number } | null;
};

export const registry = data as {
  generatedAt: string | null;
  repository: string | null;
  extensions: Extension[];
};

export const extensions = registry.extensions;

/**
 * Every extension sits in exactly one category, so a chip and the sublist it
 * names always report the same number. An entry that contributes a theme is a
 * theme however much else it carries; below that, the most specific thing it
 * adds wins.
 */
export function groupOf(extension: Extension): GroupKey {
  const has = (k: string) => extension.contributes.includes(k);
  if (has("themes")) return "themes";
  if (has("iconThemes")) return "icons";
  if (has("agents")) return "agents";
  if (has("formatters") && !has("languages") && !has("servers")) {
    return "formatters";
  }
  return "languages";
}

/** The categories, themes last. */
export const groupOrder = [
  "agents",
  "formatters",
  "icons",
  "languages",
  "themes",
] as const;

export type GroupKey = (typeof groupOrder)[number];
export type KindKey = "all" | GroupKey;

export const kinds: { key: KindKey }[] = [
  { key: "all" },
  ...groupOrder.map((key) => ({ key })),
];

export function kindsOf(extension: Extension): KindKey[] {
  return [groupOf(extension)];
}

export function countOf(key: KindKey): number {
  if (key === "all") return extensions.length;
  return extensions.filter((e) => groupOf(e) === key).length;
}

export function formatBytes(bytes: number | null | undefined): string {
  if (!bytes) return "—";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export function formatDate(value: string | null, locale: string): string {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat(locale, {
    year: "numeric",
    month: "short",
    day: "numeric",
    timeZone: "UTC",
  }).format(date);
}

/** What an entry contributes, as the detail page lists it. */
export const contributeOrder = [
  "languages",
  "servers",
  "formatters",
  "grammars",
  "themes",
  "iconThemes",
  "agents",
  "views",
];

/**
 * The groups, each with its members. Sorted by the reader's own label so the
 * order reads alphabetically in whichever language the page is in — except
 * themes, which stay last because they outnumber everything else three to one.
 */
export function groupedExtensions(
  label: (key: GroupKey) => string,
  locale: string,
): { key: GroupKey; label: string; items: Extension[] }[] {
  const buckets = new Map<GroupKey, Extension[]>();
  for (const extension of extensions) {
    const key = groupOf(extension);
    const bucket = buckets.get(key) ?? [];
    bucket.push(extension);
    buckets.set(key, bucket);
  }
  return groupOrder
    .filter((key) => (buckets.get(key)?.length ?? 0) > 0)
    .map((key) => ({ key, label: label(key), items: buckets.get(key)! }))
    .sort((a, b) => {
      if (a.key === "themes") return 1;
      if (b.key === "themes") return -1;
      return a.label.localeCompare(b.label, locale);
    });
}
