import assert from "node:assert/strict";
import test from "node:test";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createPreviewHandler } from "../tools/previewWebHandler.mjs";

const publicDirectory = fileURLToPath(new URL("../../public", import.meta.url));

async function request(path, method = "GET", overrides = {}) {
    let reads = 0;
    const events = [];
    const result = {};
    const handler = createPreviewHandler({
        publicDirectory: resolve(publicDirectory),
        loadHome: async () => {
            reads++;
            return { validation: { items: [{ ownerId: "one", title: "Real recipe" }] }, observed: [{}] };
        },
        renderHome: (items) => items.map((item) => item.title).join(),
        renderError: () => "Preview unavailable",
        securityHeaders: () => ({ "Content-Security-Policy": "default-src 'self'; upgrade-insecure-requests" }),
        log: (event) => events.push(event),
        ...overrides,
    });
    await handler({ url: path, method }, {
        writeHead(status, headers) { Object.assign(result, { status, headers }); return this; },
        end(body) { result.body = body; },
    });
    return { ...result, reads, events };
}

test("preview renders only the shared loader result and disables HTTPS upgrade on loopback", async () => {
    const result = await request("/");
    assert.equal(result.status, 200);
    assert.equal(result.body, "Real recipe");
    assert.equal(result.reads, 1);
    assert.equal(result.headers["Cache-Control"], "no-store");
    assert.doesNotMatch(result.headers["Content-Security-Policy"], /upgrade-insecure-requests/);
    assert.equal(result.events[0].validated, 1);
});

test("preview rejects writes before loading any production data", async () => {
    for (const method of ["POST", "PUT", "PATCH", "DELETE"]) {
        const result = await request("/", method);
        assert.equal(result.status, 405);
        assert.equal(result.reads, 0);
    }
});

test("detail preview links explicitly use production while preserving paths and query", async () => {
    for (const path of ["/recipe/one?source=web", "/u/nadav", "/collection/one", "/profile/one", "/invite/one"]) {
        const result = await request(path);
        assert.equal(result.status, 302);
        assert.equal(result.headers.Location, `https://cauldronrecipes.com${path}`);
        assert.equal(result.reads, 0);
    }
});

test("preview cannot traverse outside public assets and treats missing files as 404", async () => {
    for (const path of ["/..%2ffunctions/package.json", "/missing.svg", "/%2e%2e%2fpackage.json"]) {
        const result = await request(path);
        assert.equal(result.status, 404);
        assert.equal(result.reads, 0);
    }
    assert.equal((await request("/%invalid")).status, 400);
});

test("HEAD is bodyless on success, redirects, and errors", async () => {
    for (const path of ["/", "/recipe/one", "/missing.svg"]) {
        assert.equal((await request(path, "HEAD")).body, undefined);
    }
});

test("backend failure returns unavailable and does not leak error content", async () => {
    const result = await request("/", "GET", {
        loadHome: async () => { throw new Error("secret-signed-url"); },
    });
    assert.equal(result.status, 503);
    assert.equal(result.body, "Preview unavailable");
    assert.doesNotMatch(JSON.stringify(result), /secret-signed-url/);
});
