import process from "node:process";
import { pathToFileURL } from "node:url";

const DEFAULT_BASE_URL = "https://cauldron-f900a.web.app";
const DEFAULT_ALIAS_BASE_URL = "https://cauldron-f900a.firebaseapp.com";
const DEFAULT_FUNCTION_BASE_URL = "https://us-central1-cauldron-f900a.cloudfunctions.net";
const DEFAULT_PROFILE_PATH = "/u/nadav";
const DEFAULT_LEGACY_PROFILE_PATH = "/profile/87BB336E-D474-4664-B06E-EC8E516B1748";
const DEFAULT_RECIPE_PATH = "/recipe/7DBEAFFD-895F-43B1-9985-463F36EA5D8C";
const DEFAULT_CANONICAL_RECIPE_PATH = "/u/nadav/7DBEAFFD-895F-43B1-9985-463F36EA5D8C";
const DEFAULT_COLLECTION_PATH = "/collection/9B0D2D38-3B17-406A-83EC-3F35B21BDB42";
const INVALID_INVITE_PATH = "/invite/CODEX-MONITOR-INVALID";
const REQUIRED_AASA_PATHS = [
    "/recipe/*", "/u/*", "/u/*/*", "/invite", "/invite/*", "/profile/*", "/collection/*",
];

export function validateAASA(payload) {
    const details = payload?.applinks?.details;
    if (!Array.isArray(details)) throw new Error("AASA is missing applinks.details");
    for (const appID of ["C4MRP56MF5.Nadav.Cauldron", "C4MRP56MF5.Nadav.Cauldron.dev"]) {
        const entry = details.find((candidate) => candidate?.appID === appID);
        if (!entry || !Array.isArray(entry.paths)) {
            throw new Error(`AASA is missing the ${appID} application entry`);
        }
        for (const path of REQUIRED_AASA_PATHS) {
            if (!entry.paths.includes(path)) throw new Error(`AASA entry ${appID} is missing ${path}`);
        }
    }
}

function requireText(html, text, message) {
    if (!html.includes(text)) throw new Error(message);
}

function canonicalURL(html) {
    const tag = html.match(/<link\b[^>]*\brel=["']canonical["'][^>]*>/i)?.[0];
    const href = tag?.match(/\bhref=["']([^"']+)["']/i)?.[1];
    if (!href) throw new Error("response is missing a canonical URL");
    return href;
}

function recipeStructuredData(html) {
    const scripts = [...html.matchAll(/<script\b[^>]*\btype=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)];
    for (const script of scripts) {
        let value;
        try {
            value = JSON.parse(script[1]);
        } catch {
            continue;
        }
        const recipe = (Array.isArray(value) ? value : [value])
            .find((candidate) => candidate?.["@type"] === "Recipe");
        if (recipe) return recipe;
    }
    throw new Error("recipe response is missing valid Recipe JSON-LD");
}

function nonemptyStrings(value) {
    return Array.isArray(value) && value.length > 0 && value.every((item) => (
        typeof item === "string" && item.trim().length > 0
    ));
}

export function validateHTML(kind, html, expected = {}) {
    requireText(html, "Cauldron", `${kind} response does not contain Cauldron branding`);
    switch (kind) {
    case "home":
        if (!/<title>[^<]*Cauldron/i.test(html)) throw new Error("home response is missing its Cauldron title");
        break;
    case "profile":
        if (canonicalURL(html) !== expected.canonicalURL) {
            throw new Error(`profile canonical URL does not match ${expected.canonicalURL}`);
        }
        requireText(html, `href="cauldron://import/profile/${expected.deepLinkIdentity}"`, "profile response has the wrong app deep-link identity");
        requireText(html, `<h1>${expected.displayName}</h1>`, "profile response has the wrong display name");
        requireText(html, `@${expected.handle}`, "profile response has the wrong handle");
        break;
    case "recipe": {
        if (canonicalURL(html) !== expected.canonicalURL) {
            throw new Error(`recipe canonical URL does not match ${expected.canonicalURL}`);
        }
        requireText(html, `href="cauldron://import/recipe/${expected.recipeId}"`, "recipe response has the wrong app deep-link identity");
        requireText(html, `class="creator" href="${expected.creatorPath}"`, "recipe response is missing its canonical creator link");
        requireText(html, `<strong>${expected.creatorName}</strong>`, "recipe response has the wrong creator name");
        requireText(html, `@${expected.creatorHandle}`, "recipe response has the wrong creator handle");
        const visibleTags = html.match(/<ul\b[^>]*\bclass=["']tags["'][^>]*>([\s\S]*?)<\/ul>/i)?.[1];
        if (!visibleTags || !/<li\b/i.test(visibleTags)) {
            throw new Error("recipe response is missing visible tags");
        }

        const recipe = recipeStructuredData(html);
        if (!nonemptyStrings(recipe.recipeIngredient)) {
            throw new Error("recipe JSON-LD must contain nonempty ingredients");
        }
        if (!Array.isArray(recipe.recipeInstructions) || recipe.recipeInstructions.length === 0 ||
            !recipe.recipeInstructions.every((step) => typeof step?.text === "string" && step.text.trim())) {
            throw new Error("recipe JSON-LD must contain nonempty instructions");
        }
        const images = Array.isArray(recipe.image) ? recipe.image : [recipe.image];
        if (!images.some((image) => {
            if (typeof image !== "string" || !image.trim() || /\/social-card\.(?:png|svg)(?:$|\?)/i.test(image)) return false;
            try {
                return new URL(image).protocol === "https:";
            } catch {
                return false;
            }
        })) {
            throw new Error("recipe JSON-LD must contain a non-placeholder HTTPS image");
        }
        const keywords = Array.isArray(recipe.keywords) ? recipe.keywords : [recipe.keywords];
        if (!keywords.some((keyword) => typeof keyword === "string" && keyword.trim())) {
            throw new Error("recipe JSON-LD must contain tags/keywords");
        }
        break;
    }
    case "collection":
        if (canonicalURL(html) !== expected.canonicalURL) {
            throw new Error(`collection canonical URL does not match ${expected.canonicalURL}`);
        }
        requireText(html, `href="cauldron://import/collection/${expected.collectionId}"`, "collection response has the wrong app deep-link identity");
        requireText(html, `<h1>${expected.title}</h1>`, `collection response is missing the expected ${expected.title} title`);
        {
            const recipeCount = html.match(/\b(\d+)\s+recipes\b/i);
            if (!recipeCount || Number(recipeCount[1]) < 1) {
                throw new Error("collection response must contain at least one recipe");
            }
            if (!/href=["']\/recipe\/[0-9a-f-]{36}["']/i.test(html)) {
                throw new Error("collection response must contain a valid recipe link");
            }
        }
        break;
    case "invite":
        if (!/<title>[^<]*Cauldron Invite/i.test(html)) throw new Error("invite response is missing its Cauldron title");
        requireText(html, "cauldron://invite", "invite response is missing the safe app handoff");
        requireText(html, "invalid or expired", "monitor invite unexpectedly represents an accepting invite");
        break;
    default:
        throw new Error(`Unknown HTML monitor kind: ${kind}`);
    }
}

function isUUID(value) {
    return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function requireNonemptyString(value, message) {
    if (typeof value !== "string" || !value.trim()) throw new Error(message);
}

export function validateDataAPI(kind, payload, expected) {
    if (payload?.success !== true || !payload.data || typeof payload.data !== "object" || Array.isArray(payload.data)) {
        throw new Error(`${kind} data API response is missing a successful data object`);
    }
    const data = payload.data;
    if (!isUUID(data.ownerId)) throw new Error(`${kind} data API response has an invalid ownerId`);
    for (const privateField of ["capability", "identityRecordName", "shouldCreate", "redirectShareId"]) {
        if (Object.hasOwn(data, privateField)) {
            throw new Error(`${kind} data API response exposed private field ${privateField}`);
        }
    }

    switch (kind) {
    case "recipe":
        if (data.recipeId !== expected.resourceId) throw new Error("recipe data API response has the wrong recipeId");
        requireNonemptyString(data.title, "recipe data API response is missing its title");
        if (!Array.isArray(data.tags) || !data.tags.every((tag) => typeof tag === "string")) {
            throw new Error("recipe data API response has invalid tags");
        }
        break;
    case "profile":
        if (data.userId !== expected.resourceId) throw new Error("profile data API response has the wrong userId");
        if (data.ownerId !== data.userId) throw new Error("profile data API response has mismatched ownership");
        if (data.username !== expected.handle) throw new Error("profile data API response has the wrong username");
        if (data.displayName !== expected.displayName) throw new Error("profile data API response has the wrong display name");
        if (!Number.isInteger(data.recipeCount) || data.recipeCount < 0) {
            throw new Error("profile data API response has an invalid recipe count");
        }
        break;
    case "collection":
        if (data.collectionId !== expected.resourceId) throw new Error("collection data API response has the wrong collectionId");
        if (data.title !== expected.title) throw new Error("collection data API response has the wrong title");
        if (!Array.isArray(data.recipeIds) || data.recipeIds.length < 1 || !data.recipeIds.every(isUUID)) {
            throw new Error("collection data API response must contain at least one valid recipeId");
        }
        break;
    default:
        throw new Error(`Unknown data API monitor kind: ${kind}`);
    }
}

function monitoredPath(name, { defaultValue, required }) {
    const value = process.env[name]?.trim() || defaultValue;
    if (!value) {
        if (required) throw new Error(`${name} must name a stable, public production fixture path`);
        return undefined;
    }
    if (!value.startsWith("/") || value.startsWith("//") || value.includes("\\")) {
        throw new Error(`${name} must be an absolute path on the configured Hosting origin`);
    }
    return value;
}

export function resolvedMonitoredURL(baseURL, path) {
    const resolved = new URL(path, baseURL);
    if (resolved.origin !== baseURL.origin) throw new Error(`${path} resolves off the configured Hosting origin`);
    return resolved;
}

export function dataAPIMonitorRequests(hostingBaseURL, functionBaseURL, checks) {
    return checks.flatMap((check) => [
        {
            baseURL: hostingBaseURL,
            check: { ...check, label: `Hosting ${check.label}` },
        },
        {
            baseURL: functionBaseURL,
            check: { ...check, label: `direct function ${check.label}` },
        },
    ]);
}

async function fetchWithRetry(url, attempts = 3) {
    let lastError;
    for (let attempt = 1; attempt <= attempts; attempt += 1) {
        try {
            const response = await fetch(url, {
                redirect: "follow",
                headers: {
                    accept: "text/html,application/json;q=0.9,*/*;q=0.8",
                    "cache-control": "no-cache",
                    "user-agent": "Cauldron-Hosted-Monitor/1.0",
                },
                signal: AbortSignal.timeout(15_000),
            });
            if (response.status >= 500 && attempt < attempts) {
                lastError = new Error(`HTTP ${response.status}`);
                continue;
            }
            return response;
        } catch (error) {
            lastError = error;
        }
    }
    throw lastError ?? new Error("request failed without an error");
}

async function monitorResponse(baseURL, check) {
    const requestedURL = resolvedMonitoredURL(baseURL, check.path);
    const response = await fetchWithRetry(requestedURL);
    if (!response.ok) throw new Error(`${check.label} returned HTTP ${response.status} at ${requestedURL}`);
    if (new URL(response.url).origin !== baseURL.origin) {
        throw new Error(`${check.label} redirected off the configured origin to ${response.url}`);
    }
    const contentType = response.headers.get("content-type") ?? "";
    if (check.kind === "aasa") {
        if (!contentType.includes("application/json")) throw new Error(`AASA returned unexpected content type: ${contentType || "missing"}`);
        validateAASA(await response.json());
    } else if (check.kind === "data") {
        if (!contentType.includes("application/json")) throw new Error(`${check.label} returned unexpected content type: ${contentType || "missing"}`);
        validateDataAPI(check.dataKind, await response.json(), check.expected);
    } else {
        if (!contentType.includes("text/html")) throw new Error(`${check.label} returned unexpected content type: ${contentType || "missing"}`);
        validateHTML(check.kind, await response.text(), check.expected);
    }
    process.stdout.write(`PASS ${check.label}: ${requestedURL}\n`);
}

export async function runHostedMonitor() {
    const baseURL = new URL(process.env.CAULDRON_MONITOR_BASE_URL?.trim() || DEFAULT_BASE_URL);
    const aliasBaseURL = new URL(process.env.CAULDRON_MONITOR_ALIAS_BASE_URL?.trim() || DEFAULT_ALIAS_BASE_URL);
    const functionBaseURL = new URL(process.env.CAULDRON_MONITOR_FUNCTION_BASE_URL?.trim() || DEFAULT_FUNCTION_BASE_URL);
    if (baseURL.protocol !== "https:") throw new Error("CAULDRON_MONITOR_BASE_URL must use HTTPS");
    if (aliasBaseURL.protocol !== "https:") throw new Error("CAULDRON_MONITOR_ALIAS_BASE_URL must use HTTPS");
    if (functionBaseURL.protocol !== "https:") throw new Error("CAULDRON_MONITOR_FUNCTION_BASE_URL must use HTTPS");

    const profilePath = monitoredPath("CAULDRON_MONITOR_PROFILE_PATH", { defaultValue: DEFAULT_PROFILE_PATH, required: true });
    const legacyProfilePath = monitoredPath("CAULDRON_MONITOR_LEGACY_PROFILE_PATH", { defaultValue: DEFAULT_LEGACY_PROFILE_PATH, required: true });
    const recipePath = monitoredPath("CAULDRON_MONITOR_RECIPE_PATH", { defaultValue: DEFAULT_RECIPE_PATH, required: true });
    const canonicalRecipePath = monitoredPath("CAULDRON_MONITOR_CANONICAL_RECIPE_PATH", { defaultValue: DEFAULT_CANONICAL_RECIPE_PATH, required: true });
    const collectionPath = monitoredPath("CAULDRON_MONITOR_COLLECTION_PATH", {
        defaultValue: DEFAULT_COLLECTION_PATH,
        required: true,
    });
    const profileHandle = process.env.CAULDRON_MONITOR_PROFILE_HANDLE?.trim() || "nadav";
    const profileName = process.env.CAULDRON_MONITOR_PROFILE_NAME?.trim() || "Nadav";
    const collectionTitle = process.env.CAULDRON_MONITOR_COLLECTION_TITLE?.trim() || "Bakery";
    const recipeId = recipePath.split("/").filter(Boolean).at(-1);
    const legacyProfileId = legacyProfilePath.split("/").filter(Boolean).at(-1);
    const collectionId = collectionPath.split("/").filter(Boolean).at(-1);
    const recipeExpected = {
        canonicalURL: resolvedMonitoredURL(baseURL, recipePath).href,
        recipeId,
        creatorPath: profilePath,
        creatorName: profileName,
        creatorHandle: profileHandle,
    };
    const dataChecks = [
        {
            path: `/api/data/profile/${encodeURIComponent(profileHandle)}`,
            kind: "data",
            dataKind: "profile",
            label: "profile data API",
            expected: { resourceId: legacyProfileId, handle: profileHandle, displayName: profileName },
        },
        {
            path: `/api/data/recipe/${encodeURIComponent(recipeId)}`,
            kind: "data",
            dataKind: "recipe",
            label: "recipe data API",
            expected: { resourceId: recipeId },
        },
        {
            path: `/api/data/collection/${encodeURIComponent(collectionId)}`,
            kind: "data",
            dataKind: "collection",
            label: "collection data API",
            expected: { resourceId: collectionId, title: collectionTitle },
        },
    ];
    const checks = [
        { path: "/", kind: "home", label: "home" },
        { path: "/.well-known/apple-app-site-association", kind: "aasa", label: "aasa" },
        {
            path: profilePath, kind: "profile", label: "canonical profile alias",
            expected: {
                canonicalURL: resolvedMonitoredURL(baseURL, legacyProfilePath).href,
                deepLinkIdentity: profileHandle, displayName: profileName, handle: profileHandle,
            },
        },
        {
            path: legacyProfilePath, kind: "profile", label: "legacy profile route",
            expected: {
                canonicalURL: resolvedMonitoredURL(baseURL, legacyProfilePath).href,
                deepLinkIdentity: legacyProfileId, displayName: profileName, handle: profileHandle,
            },
        },
        { path: canonicalRecipePath, kind: "recipe", label: "canonical recipe route", expected: recipeExpected },
        { path: recipePath, kind: "recipe", label: "direct recipe alias", expected: recipeExpected },
        { path: "/invite", kind: "invite", label: "invite landing" },
        { path: INVALID_INVITE_PATH, kind: "invite", label: "invalid invite handoff" },
        {
            path: collectionPath, kind: "collection", label: "collection route",
            expected: {
                canonicalURL: resolvedMonitoredURL(baseURL, collectionPath).href,
                collectionId,
                title: collectionTitle,
            },
        },
    ];
    for (const check of checks) await monitorResponse(baseURL, check);
    for (const request of dataAPIMonitorRequests(baseURL, functionBaseURL, dataChecks)) {
        await monitorResponse(request.baseURL, request.check);
    }
    await monitorResponse(aliasBaseURL, {
        path: "/.well-known/apple-app-site-association",
        kind: "aasa",
        label: "firebaseapp compatibility AASA",
    });
}

const invokedDirectly = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (invokedDirectly) {
    runHostedMonitor().catch((error) => {
        const message = error instanceof Error ? error.message : String(error);
        process.stderr.write(`::error title=Cauldron hosted monitor failed::${message}\n`);
        process.exitCode = 1;
    });
}
