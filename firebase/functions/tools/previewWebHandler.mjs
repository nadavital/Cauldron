import { readFile } from "node:fs/promises";
import { extname, resolve, sep } from "node:path";

const mime = { ".svg": "image/svg+xml", ".png": "image/png", ".ico": "image/x-icon", ".json": "application/json" };

// Deliberately accepts only read/render operations. Do not pass HTTP production
// handlers here: those may repair snapshots or update request-rate counters.
export function createPreviewHandler({ publicDirectory, loadHome, renderHome, renderError, securityHeaders, log = () => {} }) {
    return async (request, response) => {
        const head = request.method === "HEAD";
        const headers = { ...securityHeaders(), "Cache-Control": "no-store" };
        headers["Content-Security-Policy"] = headers["Content-Security-Policy"]
            ?.replace(/;?\s*upgrade-insecure-requests\s*;?/, ";");
        try {
            if (request.method !== "GET" && !head) {
                response.writeHead(405, { ...headers, Allow: "GET, HEAD" }).end();
                return;
            }
            const url = new URL(request.url ?? "/", "http://127.0.0.1:8766");
            if (url.pathname === "/") {
                const started = Date.now();
                const { validation, observed } = await loadHome();
                const html = renderHome(validation.items);
                log({ preview: "home", indexed: observed.length, validated: validation.items.length,
                    creators: new Set(validation.items.map((item) => item.ownerId)).size, elapsedMs: Date.now() - started });
                response.writeHead(200, { ...headers, "Content-Type": "text/html; charset=utf-8" });
                response.end(head ? undefined : html);
                return;
            }
            if (/^\/(recipe|recipes|u|profile|collection|invite|sitemaps)(\/|$)/.test(url.pathname) || url.pathname === "/sitemap.xml") {
                response.writeHead(302, { ...headers, Location: `https://cauldronrecipes.com${url.pathname}${url.search}` }).end();
                return;
            }
            const path = resolve(publicDirectory, `.${decodeURIComponent(url.pathname)}`);
            if (!path.startsWith(publicDirectory + sep)) {
                response.writeHead(404, headers).end();
                return;
            }
            const bytes = await readFile(path);
            response.writeHead(200, { ...headers, "Content-Type": mime[extname(path)] ?? "application/octet-stream" });
            response.end(head ? undefined : bytes);
        } catch (error) {
            const status = error instanceof URIError ? 400 :
                ["ENOENT", "ENOTDIR", "EISDIR"].includes(error?.code) ? 404 : 503;
            // Never log backend error bodies: they may include signed asset URLs.
            log({ preview: "request-failed", status });
            response.writeHead(status, { ...headers, "Content-Type": "text/html; charset=utf-8" });
            response.end(head ? undefined : renderError("Preview unavailable", "Check the local preview terminal and try again."));
        }
    };
}
