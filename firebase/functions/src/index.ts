import { onRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

admin.initializeApp();
const db = admin.firestore();

// --- Utilities ---

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
        const {
            recipeId,
            ownerId,
            title,
            imageURL,
            ingredientCount,
            totalMinutes,
            tags,
        } = req.body;

        if (!recipeId || !ownerId || !title) {
            res.status(400).json({ error: 'Missing required fields' });
            return;
        }

        const shareId = recipeId; // Use the recipe UUID as the share ID
        const shareData = {
            recipeId,
            ownerId,
            title,
            imageURL: imageURL || null,
            ingredientCount: ingredientCount || 0,
            totalMinutes: totalMinutes || null,
            tags: tags || [],
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
        const {
            userId,
            username,
            displayName,
            profileImageURL,
            recipeCount,
        } = req.body;

        if (!userId || !username) {
            res.status(400).json({ error: 'Missing required fields' });
            return;
        }

        // Use username as the share ID for profiles
        const shareId = username;
        const shareData = {
            userId,
            username,
            displayName: displayName || username,
            profileImageURL: profileImageURL || null,
            recipeCount: recipeCount || 0,
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
        const {
            collectionId,
            ownerId,
            title,
            coverImageURL,
            recipeCount,
            recipeIds,
        } = req.body;

        if (!collectionId || !ownerId || !title) {
            res.status(400).json({ error: 'Missing required fields' });
            return;
        }

        const shareId = collectionId; // Use collection UUID
        const shareData = {
            collectionId,
            ownerId,
            title,
            coverImageURL: coverImageURL || null,
            recipeCount: recipeCount || 0,
            recipeIds: recipeIds || [],
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

            // Increment view count
            await doc.ref.update({
                viewCount: admin.firestore.FieldValue.increment(1),
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
    const metaImageURL = imageURL || 'https://cauldron-f900a.web.app/icon-light.svg';

    return `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${title} - Cauldron</title>

    <!-- Open Graph / Facebook -->
    <meta property="og:type" content="article">
    <meta property="og:title" content="${title}">
    <meta property="og:description" content="${description}">
    <meta property="og:image" content="${metaImageURL}">
    <meta property="og:url" content="${appURL}">
    <meta property="og:site_name" content="Cauldron">

    <!-- Twitter -->
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="${title}">
    <meta name="twitter:description" content="${description}">
    <meta name="twitter:image" content="${metaImageURL}">
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
        
        ${imageURL ? `<img src="${imageURL}" alt="${title}" class="preview-image" onerror="this.style.display='none'">` : ''}
        
        <h1>${title}</h1>
        <p class="description">${description}</p>
        
        <a href="${appURL}" class="button">Open in Cauldron</a>
        <a href="${downloadURL}" class="button secondary">Download App</a>
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

        res.send(generatePreviewHtml(title, description, imageURL, appURL, downloadURL));
    } catch (error) {
        logger.error('Error loading collection preview:', error);
        res.status(500).send('Error loading preview');
    }
});
