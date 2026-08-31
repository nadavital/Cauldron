import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { generateHomePageHtml } from "../lib/index.js";

import {
    dataAPIMonitorRequests,
    resolvedMonitoredURL,
    validateAASA,
    validateDataAPI,
    validateHTML,
} from "../tools/monitorHostedSharing.mjs";

const appPaths = [
    "/recipe/*", "/u/*", "/u/*/*", "/invite", "/invite/*", "/profile/*", "/collection/*",
];
const recipeExpected = {
    canonicalURL: "https://cauldronrecipes.com/recipe/recipe-id",
    recipeId: "recipe-id",
    creatorPath: "/u/nadav",
    creatorName: "Nadav",
    creatorHandle: "nadav",
};

const productionHomeHTML = generateHomePageHtml([]);

function recipeHTML(overrides = {}) {
    const structured = {
        "@context": "https://schema.org",
        "@type": "Recipe",
        name: "Cake",
        image: ["https://example.com/cake.jpg"],
        keywords: "Dessert",
        recipeIngredient: ["1 cup flour"],
        recipeInstructions: [{ "@type": "HowToStep", text: "Bake it" }],
        ...overrides,
    };
    return `<title>Cake · Cauldron</title>
        <link rel="canonical" href="${recipeExpected.canonicalURL}">
        <script type="application/ld+json">${JSON.stringify(structured)}</script>
        <a class="creator" href="/u/nadav"><strong>Nadav</strong><small>@nadav</small></a>
        <ul class="tags"><li>Dessert</li></ul>
        <a href="cauldron://import/recipe/recipe-id">Open in Cauldron</a>`;
}

test("AASA validator requires production and development route coverage", () => {
    validateAASA({
        applinks: {
            details: [
                { appID: "C4MRP56MF5.Nadav.Cauldron", paths: appPaths },
                { appID: "C4MRP56MF5.Nadav.Cauldron.dev", paths: appPaths },
            ],
        },
    });
});

test("AASA validator rejects a missing canonical profile path", () => {
    const incompletePaths = appPaths.filter((path) => path !== "/u/*");
    assert.throws(() => validateAASA({
        applinks: { details: [
            { appID: "C4MRP56MF5.Nadav.Cauldron", paths: incompletePaths },
            { appID: "C4MRP56MF5.Nadav.Cauldron.dev", paths: appPaths },
        ] },
    }), /missing \/u\/\*/);
});

test("validators enforce exact profile, recipe, collection, and invite identities", () => {
    validateHTML("home", '<title>Cauldron</title><link rel="canonical" href="https://cauldronrecipes.com/"><meta property="og:image" content="https://cauldronrecipes.com/social-card.png"><link href="/icon-small-light.svg"><link href="/favicon.svg"><link href="/apple-touch-icon.png"><a href="https://apps.apple.com/app/id6754004943">', {
        canonicalURL: "https://cauldronrecipes.com/",
    });
    validateHTML("profile", '<title>Nadav · Cauldron</title><link rel="canonical" href="https://cauldronrecipes.com/u/nadav"><h1>Nadav</h1><p>@nadav</p><a href="cauldron://import/profile/nadav">', {
        canonicalURL: "https://cauldronrecipes.com/u/nadav",
        deepLinkIdentity: "nadav",
        displayName: "Nadav",
        handle: "nadav",
    });
    validateHTML("recipe", recipeHTML(), recipeExpected);
    validateHTML("collection", '<title>Bakery · Cauldron</title><link rel="canonical" href="https://cauldronrecipes.com/collection/id"><h1>Bakery</h1><p>3 recipes</p><a href="/recipe/7DBEAFFD-895F-43B1-9985-463F36EA5D8C">Cake</a><a href="cauldron://import/collection/id">', {
        canonicalURL: "https://cauldronrecipes.com/collection/id",
        collectionId: "id",
        title: "Bakery",
    });
    validateHTML("invite", "<title>Cauldron Invite</title>This invite link is invalid or expired. cauldron://invite");
});

test("home validator requires canonical branding and App Store metadata", () => {
    const expected = { canonicalURL: "https://cauldronrecipes.com/" };
    const complete = '<title>Cauldron</title><link rel="canonical" href="https://cauldronrecipes.com/"><meta property="og:image" content="https://cauldronrecipes.com/social-card.png"><link href="/icon-small-light.svg"><link href="/favicon.svg"><link href="/apple-touch-icon.png"><a href="https://apps.apple.com/app/id6754004943">';
    assert.throws(() => validateHTML("home", complete.replace("social-card.png", "other.png"), expected), /Open Graph/);
    assert.throws(() => validateHTML("home", complete.replace("icon-small-light.svg", "other.svg"), expected), /logo/);
    assert.throws(() => validateHTML("home", complete.replace("id6754004943", "id1"), expected), /App Store/);
});

test("generated production homepage satisfies the hosted contract", () => {
    validateHTML("home", productionHomeHTML, { canonicalURL: "https://cauldronrecipes.com/" });
    assert.match(productionHomeHTML, /application\/ld\+json/);
    assert.match(productionHomeHTML, /prefers-reduced-motion/);
    assert.match(productionHomeHTML, /prefers-color-scheme:dark/);
});

test("production favicon assets include SVG, ICO, and Apple touch formats", () => {
    const asset = (name) => readFileSync(fileURLToPath(new URL(`../../public/${name}`, import.meta.url)));
    assert.match(asset("favicon.svg").toString("utf8"), /<svg/);
    assert.deepEqual([...asset("favicon.ico").subarray(0, 4)], [0, 0, 1, 0]);
    assert.deepEqual([...asset("apple-touch-icon.png").subarray(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10]);
});

test("collection validator rejects an empty or mismatched fixture", () => {
    const expected = {
        canonicalURL: "https://cauldronrecipes.com/collection/id",
        collectionId: "id",
        title: "Bakery",
    };
    const base = '<title>Bakery · Cauldron</title><link rel="canonical" href="https://cauldronrecipes.com/collection/id"><h1>Bakery</h1><a href="cauldron://import/collection/id">';
    assert.throws(() => validateHTML("collection", `${base}<p>0 recipes</p>`, expected), /at least one recipe/);
    assert.throws(() => validateHTML("collection", `${base}<p>1 recipes</p>`, expected), /valid recipe link/);
    assert.throws(
        () => validateHTML("collection", `${base.replace("<h1>Bakery</h1>", "<h1>Dinner</h1>")}<p>1 recipes</p><a href="/recipe/7DBEAFFD-895F-43B1-9985-463F36EA5D8C">`, expected),
        /expected Bakery title/,
    );
});

test("recipe validator rejects empty rich content", () => {
    for (const [override, message] of [
        [{ recipeIngredient: [] }, /nonempty ingredients/],
        [{ recipeInstructions: [] }, /nonempty instructions/],
        [{ image: [] }, /contain a non-placeholder HTTPS image/],
        [{ image: ["https://cauldronrecipes.com/social-card.png"] }, /non-placeholder HTTPS image/],
        [{ keywords: "" }, /tags\/keywords/],
    ]) {
        assert.throws(() => validateHTML("recipe", recipeHTML(override), recipeExpected), message);
    }
});

test("recipe validator rejects mismatched canonical, deep-link, creator, and visible tags", () => {
    assert.throws(
        () => validateHTML("recipe", recipeHTML().replace(recipeExpected.canonicalURL, "https://cauldronrecipes.com/recipe/other"), recipeExpected),
        /canonical URL/,
    );
    assert.throws(
        () => validateHTML("recipe", recipeHTML().replace("cauldron://import/recipe/recipe-id", "cauldron://import/recipe/other"), recipeExpected),
        /deep-link identity/,
    );
    assert.throws(
        () => validateHTML("recipe", recipeHTML().replace('class="creator" href="/u/nadav"', 'class="creator" href="/u/other"'), recipeExpected),
        /creator link/,
    );
    assert.throws(
        () => validateHTML("recipe", recipeHTML().replace('class="tags"', 'class="other"'), recipeExpected),
        /visible tags/,
    );
    assert.throws(
        () => validateHTML("recipe", recipeHTML().replace("<li>Dessert</li>", ""), recipeExpected),
        /visible tags/,
    );
});

test("profile validator rejects a stale identity", () => {
    const html = '<title>Other · Cauldron</title><link rel="canonical" href="https://cauldronrecipes.com/u/nadav"><h1>Other</h1><p>@other</p><a href="cauldron://import/profile/other">';
    assert.throws(() => validateHTML("profile", html, {
        canonicalURL: "https://cauldronrecipes.com/u/nadav",
        deepLinkIdentity: "nadav",
        displayName: "Nadav",
        handle: "nadav",
    }), /deep-link identity/);
});

test("resolved monitor URL rejects slash-backslash cross-origin paths before fetch", () => {
    const baseURL = new URL("https://cauldronrecipes.com");
    assert.throws(() => resolvedMonitoredURL(baseURL, "/\\example.com/path"), /resolves off/);
    assert.equal(resolvedMonitoredURL(baseURL, "/recipe/id").origin, baseURL.origin);
});

test("data API validators enforce app import identities and usable fixture payloads", () => {
    const ownerId = "87BB336E-D474-4664-B06E-EC8E516B1748";
    const recipeId = "7DBEAFFD-895F-43B1-9985-463F36EA5D8C";
    const collectionId = "9B0D2D38-3B17-406A-83EC-3F35B21BDB42";
    validateDataAPI("profile", {
        success: true,
        data: { ownerId, userId: ownerId, username: "nadav", displayName: "Nadav", recipeCount: 3 },
    }, { resourceId: ownerId, handle: "nadav", displayName: "Nadav" });
    validateDataAPI("recipe", {
        success: true,
        data: { ownerId, recipeId, title: "Cake", tags: ["Dessert"] },
    }, { resourceId: recipeId });
    validateDataAPI("collection", {
        success: true,
        data: { ownerId, collectionId, title: "Bakery", recipeIds: [recipeId] },
    }, { resourceId: collectionId, title: "Bakery" });
});

test("data API validators reject stale, empty, and mismatched responses", () => {
    const ownerId = "87BB336E-D474-4664-B06E-EC8E516B1748";
    const recipeId = "7DBEAFFD-895F-43B1-9985-463F36EA5D8C";
    assert.throws(
        () => validateDataAPI("profile", { success: true, data: {
            ownerId, userId: ownerId, username: "other", displayName: "Nadav", recipeCount: 3,
        } }, { resourceId: ownerId, handle: "nadav", displayName: "Nadav" }),
        /wrong username/,
    );
    assert.throws(
        () => validateDataAPI("recipe", { success: true, data: {
            ownerId, recipeId: "00000000-0000-4000-8000-000000000000", title: "Cake", tags: [],
        } }, { resourceId: recipeId }),
        /wrong recipeId/,
    );
    assert.throws(
        () => validateDataAPI("collection", { success: true, data: {
            ownerId, collectionId: "9B0D2D38-3B17-406A-83EC-3F35B21BDB42", title: "Bakery", recipeIds: [],
        } }, { resourceId: "9B0D2D38-3B17-406A-83EC-3F35B21BDB42", title: "Bakery" }),
        /at least one valid recipeId/,
    );
    assert.throws(
        () => validateDataAPI("recipe", { success: true, data: {
            ownerId, recipeId, title: "Cake", tags: [], capability: "must-not-leak",
        } }, { resourceId: recipeId }),
        /exposed private field capability/,
    );
});

test("data API request plan probes every type through Hosting and the direct function origin", () => {
    const hosting = new URL("https://cauldronrecipes.com");
    const direct = new URL("https://us-central1-cauldron-f900a.cloudfunctions.net");
    const checks = ["profile", "recipe", "collection"].map((dataKind) => ({
        path: `/api/data/${dataKind}/fixture`,
        kind: "data",
        dataKind,
        label: `${dataKind} data API`,
        expected: {},
    }));

    const requests = dataAPIMonitorRequests(hosting, direct, checks);

    assert.equal(requests.length, 6);
    assert.deepEqual(new Set(requests.map((request) => request.baseURL.origin)), new Set([hosting.origin, direct.origin]));
    for (const dataKind of ["profile", "recipe", "collection"]) {
        const matching = requests.filter((request) => request.check.dataKind === dataKind);
        assert.equal(matching.length, 2);
        assert.ok(matching.every((request) => request.check.path === `/api/data/${dataKind}/fixture`));
    }
});
