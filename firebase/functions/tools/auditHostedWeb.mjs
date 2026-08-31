// Small, read-only lab audit. These timings are not field Core Web Vitals.
const origin = "https://cauldronrecipes.com";
const routes = ["/", "/u/nadav", "/recipe/7DBEAFFD-895F-43B1-9985-463F36EA5D8C",
    "/collection/9B0D2D38-3B17-406A-83EC-3F35B21BDB42", "/invite",
    "/recipe/00000000-0000-4000-8000-000000000000", "/robots.txt", "/sitemap.xml"];
for (const route of routes) {
    const timings = [];
    let html = "", response;
    for (let sample = 0; sample < (routes.indexOf(route) < 4 ? 3 : 1); sample++) {
        const started = performance.now();
        response = await fetch(`${origin}${route}`, { redirect: "manual", signal: AbortSignal.timeout(30000) });
        const headersAt = performance.now();
        html = await response.text();
        timings.push({ headersMs: Math.round(headersAt - started), totalMs: Math.round(performance.now() - started) });
    }
    const schema = [...html.matchAll(/<script\b[^>]*type="application\/ld\+json"[^>]*>([^]*?)<\/script>/g)]
        .map(match => { try { return JSON.parse(match[1]); } catch { return { invalidJSON: true }; } });
    console.log(JSON.stringify({ route, status: response.status, timings, htmlBytes: Buffer.byteLength(html),
        cache: response.headers.get("cache-control"), encoding: response.headers.get("content-encoding"),
        title: html.match(/<title>([^<]+)<\/title>/)?.[1],
        canonical: html.match(/<link[^>]*rel="canonical"[^>]*href="([^"]+)"/)?.[1],
        description: Boolean(html.match(/<meta[^>]*name="description"[^>]*content="[^"]+"/)),
        h1: (html.match(/<h1\b/g) || []).length,
        noindex: /noindex/.test(response.headers.get("x-robots-tag") || "") || /name="robots" content="noindex/.test(html),
        externalScripts: (html.match(/<script[^>]*src=/g) || []).length,
        externalStylesheets: (html.match(/<link[^>]*rel="stylesheet"/g) || []).length,
        schemas: schema.map(s => ({ type: s["@type"], invalid: s.invalidJSON || false,
            author: Boolean(s.author), stableImage: Array.isArray(s.image) && s.image.every(i => i.startsWith(origin)),
            ingredients: s.recipeIngredient?.length, steps: s.recipeInstructions?.length })),
        sitemapURLs: route === "/sitemap.xml" ? (html.match(/<loc>/g) || []).length : undefined,
    }));
}
