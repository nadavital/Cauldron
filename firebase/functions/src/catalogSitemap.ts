export const SITEMAP_PAGE_SIZE = 24;
export const SITEMAP_MAX_RECIPES = 10_000;
export const SITEMAP_MAX_AGE_MS = 24 * 60 * 60_000;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/** Index metadata only; never a cached authorization or recipe content source. */
export function sitemapRecipePages(ids: string[]): string[][] {
    const unique = [...new Set(ids.filter((id) => uuid.test(id)))].sort();
    if (unique.length > SITEMAP_MAX_RECIPES) throw new Error("Sitemap capacity exceeded; do not truncate discovery");
    const pages: string[][] = [];
    for (let index = 0; index < unique.length; index += SITEMAP_PAGE_SIZE) pages.push(unique.slice(index, index + SITEMAP_PAGE_SIZE));
    return pages.length ? pages : [[]];
}

export function sitemapPageNumber(path: string): number | null {
    const match = /^\/sitemaps\/recipes-(0|[1-9]\d{0,2})\.xml$/.exec(path);
    return match ? Number(match[1]) : null;
}

export function catalogManifestCandidates(ids: unknown, refreshedAtMillis: unknown, after: string | null, now = Date.now()): string[] | null {
    if (!Array.isArray(ids) || typeof refreshedAtMillis !== "number" || !Number.isFinite(refreshedAtMillis) ||
        refreshedAtMillis > now || now - refreshedAtMillis > SITEMAP_MAX_AGE_MS) return null;
    return sitemapRecipePages(ids.filter((id): id is string => typeof id === "string")).flat()
        .filter(id => !after || id > after);
}

export function generateCatalogSitemapIndex(pageCount: number, origin: string): string {
    if (!Number.isInteger(pageCount) || pageCount < 1 || pageCount > Math.ceil(SITEMAP_MAX_RECIPES / SITEMAP_PAGE_SIZE)) {
        throw new Error("Invalid sitemap page count");
    }
    return `<?xml version="1.0" encoding="UTF-8"?>\n<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${Array.from({length: pageCount}, (_, page) => `<sitemap><loc>${origin}/sitemaps/recipes-${page}.xml</loc></sitemap>`).join("")}</sitemapindex>`;
}
