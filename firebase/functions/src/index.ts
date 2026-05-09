import { onRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

admin.initializeApp();
const db = admin.firestore();

// --- Utilities ---

const MAX_TITLE_LENGTH = 160;
const MAX_DISPLAY_NAME_LENGTH = 80;
const MAX_TAG_COUNT = 20;
const MAX_TAG_LENGTH = 48;
const MAX_RECIPE_IDS_PER_COLLECTION = 200;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const usernamePattern = /^[A-Za-z0-9_]{3,20}$/;

type ValidationResult<T> =
    | { ok: true; value: T }
    | { ok: false; error: string };

type SanitizedRecipeShare = {
    recipeId: string;
    ownerId: string;
    title: string;
    imageURL: string | null;
    ingredientCount: number;
    totalMinutes: number | null;
    tags: string[];
};

type SanitizedProfileShare = {
    userId: string;
    username: string;
    displayName: string;
    profileImageURL: string | null;
    recipeCount: number;
};

type SanitizedCollectionShare = {
    collectionId: string;
    ownerId: string;
    title: string;
    coverImageURL: string | null;
    recipeCount: number;
    recipeIds: string[];
};

export function escapeHtml(value: unknown): string {
    return String(value ?? "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;");
}

export function safeImageURL(rawURL: unknown): string | null {
    if (typeof rawURL !== "string") {
        return null;
    }

    try {
        const parsed = new URL(rawURL);
        return parsed.protocol === "https:" ? parsed.toString() : null;
    } catch {
        return null;
    }
}

export function isValidUUID(value: unknown): value is string {
    return typeof value === "string" && uuidPattern.test(value);
}

function requiredBoundedString(value: unknown, field: string, maxLength: number): ValidationResult<string> {
    if (typeof value !== "string") {
        return { ok: false, error: `${field} must be a string` };
    }

    const trimmed = value.trim();
    if (!trimmed) {
        return { ok: false, error: `${field} is required` };
    }

    if (trimmed.length > maxLength) {
        return { ok: false, error: `${field} is too long` };
    }

    return { ok: true, value: trimmed };
}

function optionalNonNegativeInteger(value: unknown, fallback: number, max: number): number {
    if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
        return fallback;
    }

    return Math.min(value, max);
}

function optionalPositiveInteger(value: unknown, max: number): number | null {
    if (value === null || value === undefined) {
        return null;
    }

    if (typeof value !== "number" || !Number.isInteger(value) || value <= 0) {
        return null;
    }

    return Math.min(value, max);
}

function sanitizedTagList(value: unknown): string[] {
    if (!Array.isArray(value)) {
        return [];
    }

    const seen = new Set<string>();
    const tags: string[] = [];

    for (const item of value) {
        if (typeof item !== "string") {
            continue;
        }

        const trimmed = item.trim().slice(0, MAX_TAG_LENGTH);
        const key = trimmed.toLocaleLowerCase();
        if (!trimmed || seen.has(key)) {
            continue;
        }

        seen.add(key);
        tags.push(trimmed);
        if (tags.length >= MAX_TAG_COUNT) {
            break;
        }
    }

    return tags;
}

function sanitizedUUIDList(value: unknown): string[] {
    if (!Array.isArray(value)) {
        return [];
    }

    const seen = new Set<string>();
    const ids: string[] = [];

    for (const item of value) {
        if (!isValidUUID(item) || seen.has(item)) {
            continue;
        }

        seen.add(item);
        ids.push(item);
        if (ids.length >= MAX_RECIPE_IDS_PER_COLLECTION) {
            break;
        }
    }

    return ids;
}

export function sanitizeRecipeShareInput(input: Record<string, unknown>): ValidationResult<SanitizedRecipeShare> {
    if (!isValidUUID(input.recipeId)) {
        return { ok: false, error: "recipeId must be a UUID" };
    }
    if (!isValidUUID(input.ownerId)) {
        return { ok: false, error: "ownerId must be a UUID" };
    }

    const title = requiredBoundedString(input.title, "title", MAX_TITLE_LENGTH);
    if (!title.ok) {
        return title;
    }

    return {
        ok: true,
        value: {
            recipeId: input.recipeId,
            ownerId: input.ownerId,
            title: title.value,
            imageURL: safeImageURL(input.imageURL),
            ingredientCount: optionalNonNegativeInteger(input.ingredientCount, 0, 500),
            totalMinutes: optionalPositiveInteger(input.totalMinutes, 1440),
            tags: sanitizedTagList(input.tags),
        },
    };
}

export function sanitizeProfileShareInput(input: Record<string, unknown>): ValidationResult<SanitizedProfileShare> {
    if (!isValidUUID(input.userId)) {
        return { ok: false, error: "userId must be a UUID" };
    }
    if (typeof input.username !== "string" || !usernamePattern.test(input.username)) {
        return { ok: false, error: "username is invalid" };
    }

    const displayName = requiredBoundedString(
        input.displayName || input.username,
        "displayName",
        MAX_DISPLAY_NAME_LENGTH
    );
    if (!displayName.ok) {
        return displayName;
    }

    return {
        ok: true,
        value: {
            userId: input.userId,
            username: input.username.toLocaleLowerCase(),
            displayName: displayName.value,
            profileImageURL: safeImageURL(input.profileImageURL),
            recipeCount: optionalNonNegativeInteger(input.recipeCount, 0, 10000),
        },
    };
}

export function sanitizeCollectionShareInput(input: Record<string, unknown>): ValidationResult<SanitizedCollectionShare> {
    if (!isValidUUID(input.collectionId)) {
        return { ok: false, error: "collectionId must be a UUID" };
    }
    if (!isValidUUID(input.ownerId)) {
        return { ok: false, error: "ownerId must be a UUID" };
    }

    const title = requiredBoundedString(input.title, "title", MAX_TITLE_LENGTH);
    if (!title.ok) {
        return title;
    }

    const recipeIds = sanitizedUUIDList(input.recipeIds);

    return {
        ok: true,
        value: {
            collectionId: input.collectionId,
            ownerId: input.ownerId,
            title: title.value,
            coverImageURL: safeImageURL(input.coverImageURL),
            recipeCount: optionalNonNegativeInteger(input.recipeCount, recipeIds.length, 10000),
            recipeIds,
        },
    };
}

async function rejectExistingIdentityMismatch(
    collection: string,
    shareId: string,
    ownerId: string,
    identityFields: Record<string, string>
): Promise<boolean> {
    const existing = await db.collection(collection).doc(shareId).get();
    if (!existing.exists) {
        return false;
    }

    const data = existing.data() ?? {};
    const existingOwnerId = data.ownerId;
    if (typeof existingOwnerId === "string" && existingOwnerId !== ownerId) {
        return true;
    }

    return Object.entries(identityFields).some(([field, expectedValue]) => {
        const existingValue = data[field];
        return typeof existingValue === "string" && existingValue !== expectedValue;
    });
}

// function generateShareId(): string {
//     const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
//     let result = '';
//     for (let i = 0; i < 8; i++) {
//         result += chars.charAt(Math.floor(Math.random() * chars.length));
//     }
//     return result;
// }
// 
// async function isShareIdUnique(collection: string, shareId: string): Promise<boolean> {
//     const doc = await db.collection(collection).doc(shareId).get();
//     return !doc.exists;
// }

// function createUniqueShareId(collection: string): Promise<string> {
//     let shareId = generateShareId();
//     let attempts = 0;
//     while (!(await isShareIdUnique(collection, shareId)) && attempts < 10) {
//         shareId = generateShareId();
//         attempts++;
//     }
//     if (attempts >= 10) {
//         throw new Error('Failed to generate unique share ID');
//     }
//     return shareId;
// }

// --- API Endpoints ---

// Share Recipe
export const shareRecipe = onRequest({ cors: true, invoker: 'public' }, async (req, res) => {
    if (req.method !== 'POST') {
        res.status(405).send('Method Not Allowed');
        return;
    }

    try {
        const sanitized = sanitizeRecipeShareInput(req.body ?? {});
        if (!sanitized.ok) {
            res.status(400).json({ error: sanitized.error });
            return;
        }
        const share = sanitized.value;

        const shareId = share.recipeId; // Use the recipe UUID as the share ID
        if (await rejectExistingIdentityMismatch('shared_recipes', shareId, share.ownerId, { recipeId: share.recipeId })) {
            res.status(403).json({ error: 'Owner mismatch for existing share' });
            return;
        }

        const shareData = {
            recipeId: share.recipeId,
            ownerId: share.ownerId,
            title: share.title,
            imageURL: share.imageURL,
            ingredientCount: share.ingredientCount,
            totalMinutes: share.totalMinutes,
            tags: share.tags,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            // Don't overwrite viewCount if it exists
        };

        // Use merge: true to preserve viewCount and existing data
        await db.collection('shared_recipes').doc(shareId).set(shareData, { merge: true });

        // Construct URL using the Hosting domain
        // New Format: /u/{username}/{recipeId} is handled by the client/rewrite, 
        // but for the direct API response we can return the canonical URL
        // stored in the app or just the basic one. 
        // The iOS app generates https://cauldron-f900a.web.app/u/{username}/{recipeId} locally.
        const shareUrl = `https://cauldron-f900a.web.app/recipe/${shareId}`;

        res.status(200).json({
            shareId,
            shareUrl
        });
    } catch (error) {
        logger.error('Error sharing recipe:', error);
        res.status(500).json({ error: 'Failed to create share link' });
    }
});

// Share Profile
export const shareProfile = onRequest({ cors: true, invoker: 'public' }, async (req, res) => {
    if (req.method !== 'POST') {
        res.status(405).send('Method Not Allowed');
        return;
    }

    try {
        const sanitized = sanitizeProfileShareInput(req.body ?? {});
        if (!sanitized.ok) {
            res.status(400).json({ error: sanitized.error });
            return;
        }
        const share = sanitized.value;

        // Use username as the share ID for profiles
        const shareId = share.username;
        if (await rejectExistingIdentityMismatch('shared_profiles', shareId, share.userId, { userId: share.userId, username: share.username })) {
            res.status(403).json({ error: 'Owner mismatch for existing share' });
            return;
        }

        const shareData = {
            userId: share.userId,
            ownerId: share.userId,
            username: share.username,
            displayName: share.displayName,
            profileImageURL: share.profileImageURL,
            recipeCount: share.recipeCount,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            // Don't overwrite viewCount if it exists
        };

        // Use merge: true
        await db.collection('shared_profiles').doc(shareId).set(shareData, { merge: true });

        const shareUrl = `https://cauldron-f900a.web.app/u/${shareId}`;

        res.status(200).json({
            shareId,
            shareUrl
        });
    } catch (error) {
        logger.error('Error sharing profile:', error);
        res.status(500).json({ error: 'Failed to create share link' });
    }
});

// Share Collection
export const shareCollection = onRequest({ cors: true, invoker: 'public' }, async (req, res) => {
    if (req.method !== 'POST') {
        res.status(405).send('Method Not Allowed');
        return;
    }

    try {
        const sanitized = sanitizeCollectionShareInput(req.body ?? {});
        if (!sanitized.ok) {
            res.status(400).json({ error: sanitized.error });
            return;
        }
        const share = sanitized.value;

        const shareId = share.collectionId; // Use collection UUID
        if (await rejectExistingIdentityMismatch('shared_collections', shareId, share.ownerId, { collectionId: share.collectionId })) {
            res.status(403).json({ error: 'Owner mismatch for existing share' });
            return;
        }

        const shareData = {
            collectionId: share.collectionId,
            ownerId: share.ownerId,
            title: share.title,
            coverImageURL: share.coverImageURL,
            recipeCount: share.recipeCount,
            recipeIds: share.recipeIds,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            // Don't overwrite viewCount
        };

        await db.collection('shared_collections').doc(shareId).set(shareData, { merge: true });

        const shareUrl = `https://cauldron-f900a.web.app/collection/${shareId}`;

        res.status(200).json({
            shareId,
            shareUrl
        });
    } catch (error) {
        logger.error('Error sharing collection:', error);
        res.status(500).json({ error: 'Failed to create share link' });
    }
});

// Generic Data Fetcher
export const api = onRequest({ cors: true, invoker: 'public' }, async (req, res) => {
    // Handle routing manually for /api/data/:type/:shareId
    // Expected path: /data/recipe/12345678
    const pathParts = req.path.split('/').filter(p => p);

    // Check if this is a data request
    if (pathParts[0] === 'data' && pathParts.length === 3) {
        const type = pathParts[1];
        const shareId = pathParts[2];

        if (req.method !== 'GET') {
            res.status(405).json({ error: 'Method not allowed' });
            return;
        }

        try {
            const collectionMap: { [key: string]: string } = {
                recipe: 'shared_recipes',
                profile: 'shared_profiles',
                collection: 'shared_collections',
            };

            const collectionName = collectionMap[type];
            if (!collectionName) {
                res.status(400).json({ error: 'Invalid share type' });
                return;
            }

            const doc = await db.collection(collectionName).doc(shareId).get();
            if (!doc.exists) {
                res.status(404).json({ error: 'Share not found' });
                return;
            }

            // View counts are analytics only; keep import response latency independent from this write.
            void doc.ref.update({
                viewCount: admin.firestore.FieldValue.increment(1),
            }).catch((error) => {
                logger.warn('Failed to increment share view count:', error);
            });

            res.status(200).json({
                success: true,
                data: doc.data(),
            });
        } catch (error) {
            logger.error('Error fetching share data:', error);
            res.status(500).json({ error: 'Failed to fetch share data' });
        }
        return;
    }

    // Handle legacy share endpoints if they come through /api prefix
    if (pathParts[0] === 'share') {
        if (pathParts[1] === 'recipe') {
            // Forward to shareRecipe function
            // Note: In a real deployment, we'd use rewrites, but for simplicity in this single function:
            // We can't easily invoke another function here without HTTP.
            // So we rely on firebase.json rewrites to map /api/share/recipe -> shareRecipe function directly
            res.status(404).send('Use specific function endpoints');
            return;
        }
    }

    res.status(404).send('Not Found');
});

// --- Preview Pages ---

// --- Preview Pages ---

function generatePreviewHtml(title: string, description: string, imageURL: string | null, appURL: string, downloadURL: string): string {
    // Use default icon for meta tags if no specific image is available
    const safeTitle = escapeHtml(title);
    const safeDescription = escapeHtml(description);
    const safeAppURL = escapeHtml(appURL);
    const safeDownloadURL = escapeHtml(downloadURL);
    const metaImageURL = safeImageURL(imageURL) || 'https://cauldron-f900a.web.app/icon-light.svg';
    const safeMetaImageURL = escapeHtml(metaImageURL);

    return `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${safeTitle} - Cauldron</title>

    <!-- Open Graph / Facebook -->
    <meta property="og:type" content="article">
    <meta property="og:title" content="${safeTitle}">
    <meta property="og:description" content="${safeDescription}">
    <meta property="og:image" content="${safeMetaImageURL}">
    <meta property="og:url" content="${safeAppURL}">
    <meta property="og:site_name" content="Cauldron">

    <!-- Twitter -->
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="${safeTitle}">
    <meta name="twitter:description" content="${safeDescription}">
    <meta name="twitter:image" content="${safeMetaImageURL}">
    <meta name="twitter:app:name:iphone" content="Cauldron">
    <meta name="twitter:app:id:iphone" content="6468697878">

    <style>
        :root {
            --cauldron-orange: #FF9933;
            --bg-color: #F2F2F7;
            --card-bg: #FFFFFF;
            --text-primary: #000000;
            --text-secondary: #8E8E93;
            --shadow-color: rgba(0,0,0,0.1);
            --border-color: rgba(0,0,0,0.05);
            --button-text: #FFFFFF;
            --secondary-button-bg: rgba(0, 0, 0, 0.05);
            --secondary-button-text: #FF6B35;
        }

        @media (prefers-color-scheme: dark) {
            :root {
                --bg-color: #000000;
                --card-bg: #1C1C1E;
                --text-primary: #FFFFFF;
                --text-secondary: #8E8E93;
                --shadow-color: rgba(0,0,0,0.5);
                --border-color: #333;
                --secondary-button-bg: rgba(255, 255, 255, 0.1);
            }
        }

        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
            background-color: var(--bg-color);
            color: var(--text-primary);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
            transition: background-color 0.3s ease, color 0.3s ease;
        }

        .container {
            background: var(--card-bg);
            border-radius: 24px;
            padding: 40px;
            max-width: 480px;
            width: 100%;
            box-shadow: 0 20px 60px var(--shadow-color);
            text-align: center;
            border: 1px solid var(--border-color);
            transition: background-color 0.3s ease, border-color 0.3s ease;
        }

        .logo {
            width: 80px;
            height: 80px;
            margin: 0 auto 24px auto;
            background-size: contain;
            background-repeat: no-repeat;
            background-position: center;
            background-image: url('/icon-light.svg');
        }

        @media (prefers-color-scheme: dark) {
            .logo {
                background-image: url('/icon-dark.svg');
            }
        }

        .preview-image {
            width: 100%;
            height: 320px;
            object-fit: cover;
            border-radius: 16px;
            margin-bottom: 24px;
            box-shadow: 0 8px 24px var(--shadow-color);
            background-color: var(--secondary-button-bg);
        }

        h1 {
            font-size: 28px;
            margin-bottom: 12px;
            color: var(--text-primary);
            font-weight: 700;
            line-height: 1.2;
        }

        .description {
            font-size: 17px;
            color: var(--text-secondary);
            margin-bottom: 32px;
            line-height: 1.5;
        }

        .button {
            display: block;
            width: 100%;
            background: var(--cauldron-orange);
            color: var(--button-text);
            padding: 16px;
            border-radius: 14px;
            text-decoration: none;
            font-weight: 600;
            font-size: 17px;
            margin-bottom: 12px;
            transition: transform 0.2s, opacity 0.2s;
            cursor: pointer;
            border: none;
        }

        .button:active {
            transform: scale(0.98);
            opacity: 0.9;
        }

        .button.secondary {
            background: var(--secondary-button-bg);
            color: var(--secondary-button-text);
        }
    </style>

</head>
<body>
    <div class="container">
        <div class="logo"></div>
        
        ${metaImageURL !== 'https://cauldron-f900a.web.app/icon-light.svg' ? `<img src="${safeMetaImageURL}" alt="${safeTitle}" class="preview-image" onerror="this.style.display='none'">` : ''}
        
        <h1>${safeTitle}</h1>
        <p class="description">${safeDescription}</p>
        
        <a href="${safeAppURL}" class="button">Open in Cauldron</a>
        <a href="${safeDownloadURL}" class="button secondary">Download App</a>
    </div>
</body>
</html>
    `;
}

type InviteRequestLike = {
    query?: Record<string, unknown>;
    path?: string;
};

function normalizeReferralCode(rawCode: unknown): string | null {
    if (typeof rawCode !== "string") {
        return null;
    }

    const normalized = rawCode.toUpperCase().trim();
    if (!/^[A-Z0-9]{6}$/.test(normalized)) {
        return null;
    }

    return normalized;
}

function extractReferralCodeFromRequest(req: InviteRequestLike): string | null {
    const rawQueryCode = Array.isArray(req.query?.code) ? req.query?.code[0] : req.query?.code;
    const queryCode = normalizeReferralCode(rawQueryCode);
    if (queryCode) {
        return queryCode;
    }

    const pathParts = (req.path ?? "").split("/").filter(Boolean);
    if (pathParts.length >= 2 && pathParts[0].toLowerCase() === "invite") {
        return normalizeReferralCode(pathParts[1]);
    }

    if (pathParts.length === 1 && pathParts[0].toLowerCase() !== "invite") {
        return normalizeReferralCode(pathParts[0]);
    }

    return null;
}

function generateInvitePreviewHtml(inviteCode: string | null): string {
    const hasValidCode = inviteCode !== null;
    const universalURL = hasValidCode
        ? `https://cauldron-f900a.web.app/invite/${inviteCode}`
        : "https://cauldron-f900a.web.app/invite";
    const appURL = hasValidCode
        ? `cauldron://invite?code=${inviteCode}`
        : "cauldron://invite";
    const appStoreURL = "https://apps.apple.com/us/app/cauldron-magical-recipes/id6754004943";
    const title = hasValidCode ? "You were invited to Cauldron" : "Cauldron Invite";
    const description = hasValidCode
        ? `Join Cauldron with invite code ${inviteCode} to connect with your friend instantly.`
        : "This invite link is invalid or expired. Ask your friend to send a new one.";
    const statusLine = hasValidCode
        ? "Use this code during sign up if needed:"
        : "Invite code could not be read from this link.";

    return `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${title}</title>
    <meta property="og:type" content="website">
    <meta property="og:title" content="${title}">
    <meta property="og:description" content="${description}">
    <meta property="og:image" content="https://cauldron-f900a.web.app/icon-light.svg">
    <meta property="og:url" content="${universalURL}">
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="${title}">
    <meta name="twitter:description" content="${description}">
    <meta name="twitter:image" content="https://cauldron-f900a.web.app/icon-light.svg">
    <meta name="apple-itunes-app" content="app-id=6754004943, app-argument=${universalURL}">
    <style>
        :root {
            --orange: #ff9933;
            --bg: #f5f5f7;
            --card: #ffffff;
            --text: #1d1d1f;
            --subtext: #6e6e73;
            --border: rgba(0, 0, 0, 0.08);
        }

        @media (prefers-color-scheme: dark) {
            :root {
                --bg: #000000;
                --card: #1c1c1e;
                --text: #f5f5f7;
                --subtext: #a1a1a6;
                --border: rgba(255, 255, 255, 0.12);
            }
        }

        * { box-sizing: border-box; }

        body {
            margin: 0;
            min-height: 100vh;
            background: radial-gradient(circle at top, rgba(255, 153, 51, 0.22), transparent 48%), var(--bg);
            color: var(--text);
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }

        .card {
            width: 100%;
            max-width: 480px;
            border-radius: 24px;
            background: var(--card);
            border: 1px solid var(--border);
            box-shadow: 0 24px 60px rgba(0, 0, 0, 0.18);
            padding: 28px;
            text-align: center;
        }

        .logo {
            width: 72px;
            height: 72px;
            margin: 0 auto 20px;
            border-radius: 16px;
            background: rgba(255, 153, 51, 0.12);
            display: flex;
            align-items: center;
            justify-content: center;
        }

        .logo img {
            width: 44px;
            height: 44px;
        }

        h1 {
            margin: 0;
            font-size: 28px;
            line-height: 1.2;
        }

        p {
            margin: 10px 0 0;
            color: var(--subtext);
            line-height: 1.45;
        }

        .code-label {
            margin-top: 22px;
            color: var(--subtext);
            font-size: 13px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .code-chip {
            margin-top: 8px;
            font-size: 26px;
            font-weight: 700;
            letter-spacing: 2px;
            background: rgba(255, 153, 51, 0.12);
            color: var(--orange);
            border-radius: 14px;
            padding: 10px 14px;
            display: inline-block;
            min-width: 180px;
        }

        .button {
            margin-top: 14px;
            width: 100%;
            display: inline-flex;
            justify-content: center;
            align-items: center;
            text-decoration: none;
            border-radius: 14px;
            padding: 14px 16px;
            font-weight: 600;
            border: 0;
            cursor: pointer;
            font-size: 16px;
        }

        .button-primary {
            margin-top: 24px;
            background: var(--orange);
            color: white;
        }

        .button-secondary {
            background: rgba(255, 153, 51, 0.16);
            color: var(--orange);
        }
    </style>
</head>
<body>
    <main class="card">
        <div class="logo">
            <img src="https://cauldron-f900a.web.app/icon-light.svg" alt="Cauldron">
        </div>
        <h1>${title}</h1>
        <p>${description}</p>

        <div class="code-label">${statusLine}</div>
        ${hasValidCode ? `<div class="code-chip" id="inviteCode">${inviteCode}</div>` : ""}
        ${hasValidCode ? `<button class="button button-secondary" id="copyCodeButton" type="button">Copy Code</button>` : ""}

        <button class="button button-primary" id="openAppButton" type="button">Open in Cauldron</button>
        <a class="button button-secondary" href="${appStoreURL}">Download Cauldron</a>
    </main>
    <script>
        (function() {
            var deepLink = ${JSON.stringify(appURL)};
            var appStoreURL = ${JSON.stringify(appStoreURL)};
            var inviteCode = ${JSON.stringify(inviteCode)};

            var openButton = document.getElementById("openAppButton");
            if (openButton) {
                openButton.addEventListener("click", function() {
                    var start = Date.now();
                    window.location.href = deepLink;
                    setTimeout(function() {
                        if (Date.now() - start < 2200) {
                            window.location.href = appStoreURL;
                        }
                    }, 1300);
                });
            }

            var copyButton = document.getElementById("copyCodeButton");
            if (copyButton && inviteCode) {
                copyButton.addEventListener("click", async function() {
                    try {
                        await navigator.clipboard.writeText(inviteCode);
                        copyButton.textContent = "Copied";
                    } catch {
                        copyButton.textContent = "Copy Failed";
                    }
                });
            }
        })();
    </script>
</body>
</html>
    `;
}

export const previewInvite = onRequest({ cors: true, invoker: "public" }, async (req, res) => {
    const inviteCode = extractReferralCodeFromRequest({
        query: req.query as Record<string, unknown>,
        path: req.path,
    });

    res.set("Cache-Control", "public, max-age=300");
    res.send(generateInvitePreviewHtml(inviteCode));
});

export const previewRecipe = onRequest({ cors: true, invoker: 'public' }, async (req, res) => {
    const pathParts = req.path.split('/');
    const shareId = pathParts[pathParts.length - 1]; // Last part of path

    // Support for /u/{username}/{recipeId} format
    // In this case, shareId might be the username if we aren't careful, 
    // but the rewrite sends /recipe/** to this function so usually it's just /recipe/{id}
    // However, if we add a rewrite for /u/*/* -> previewRecipe, we need to handle it.

    // If path matches /u/username/recipeId
    // pathParts would be ['', 'u', 'username', 'recipeId']

    let recipeId = shareId;
    if (req.path.includes('/u/') && pathParts.length >= 4) {
        recipeId = pathParts[3]; // 0='', 1='u', 2='username', 3='recipeId'
    }

    if (!recipeId) {
        res.status(400).send('Invalid share ID');
        return;
    }

    try {
        const doc = await db.collection('shared_recipes').doc(recipeId).get();
        if (!doc.exists) {
            res.status(404).send('Recipe not found');
            return;
        }

        const data = doc.data()!;
        const title = data.title || 'Untitled Recipe';
        const imageURL = data.imageURL || null;
        const description = `Check out this recipe on Cauldron!`;
        const appURL = `cauldron://import/recipe/${recipeId}`;
        const downloadURL = 'https://apps.apple.com/us/app/cauldron-magical-recipes/id6754004943';

        res.set("Cache-Control", "public, max-age=300, s-maxage=600");
        res.send(generatePreviewHtml(title, description, imageURL, appURL, downloadURL));
    } catch (error) {
        logger.error('Error loading recipe preview:', error);
        res.status(500).send('Error loading preview');
    }
});

export const previewProfile = onRequest({ cors: true, invoker: 'public' }, async (req, res) => {
    const pathParts = req.path.split('/');
    const shareId = pathParts[pathParts.length - 1];

    if (!shareId) {
        res.status(400).send('Invalid share ID');
        return;
    }

    // Support for /u/{username}
    // The rewrite maps /u/* -> previewProfile.
    // So shareId is the username.

    try {
        const doc = await db.collection('shared_profiles').doc(shareId).get();
        if (!doc.exists) {
            // Because we use username as ID, this is a direct lookup
            // If it fails, we might want to try to look up by user ID if shareId matches UUID format??
            // For now, assume username.
            res.status(404).send('Profile not found');
            return;
        }

        const data = doc.data()!;
        const title = data.displayName || data.username || 'Cauldron User';
        const imageURL = data.profileImageURL || null;
        const recipeCount = data.recipeCount || 0;
        const description = `Check out my Cauldron profile! ${recipeCount} recipes and counting 🍲`;
        const appURL = `cauldron://import/profile/${shareId}`;
        const downloadURL = 'https://apps.apple.com/us/app/cauldron-magical-recipes/id6754004943';

        res.set("Cache-Control", "public, max-age=300, s-maxage=600");
        res.send(generatePreviewHtml(title, description, imageURL, appURL, downloadURL));
    } catch (error) {
        logger.error('Error loading profile preview:', error);
        res.status(500).send('Error loading preview');
    }
});

export const previewCollection = onRequest({ cors: true, invoker: 'public' }, async (req, res) => {
    const pathParts = req.path.split('/');
    const shareId = pathParts[pathParts.length - 1];

    if (!shareId) {
        res.status(400).send('Invalid share ID');
        return;
    }

    try {
        const doc = await db.collection('shared_collections').doc(shareId).get();
        if (!doc.exists) {
            res.status(404).send('Collection not found');
            return;
        }

        const data = doc.data()!;
        const title = data.title || 'Untitled Collection';
        const imageURL = data.coverImageURL || null;
        const recipeCount = data.recipeCount || 0;
        const description = `Check out my ${title} collection on Cauldron! ${recipeCount} recipes.`;
        const appURL = `cauldron://import/collection/${shareId}`;
        const downloadURL = 'https://apps.apple.com/us/app/cauldron-magical-recipes/id6754004943';

        res.set("Cache-Control", "public, max-age=300, s-maxage=600");
        res.send(generatePreviewHtml(title, description, imageURL, appURL, downloadURL));
    } catch (error) {
        logger.error('Error loading collection preview:', error);
        res.status(500).send('Error loading preview');
    }
});
