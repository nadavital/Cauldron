import { onRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

admin.initializeApp();
const db = admin.firestore();

// --- Utilities ---

function generateShareId(): string {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    let result = '';
    for (let i = 0; i < 8; i++) {
        result += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return result;
}

async function isShareIdUnique(collection: string, shareId: string): Promise<boolean> {
    const doc = await db.collection(collection).doc(shareId).get();
    return !doc.exists;
}

async function createUniqueShareId(collection: string): Promise<string> {
    let shareId = generateShareId();
    let attempts = 0;
    while (!(await isShareIdUnique(collection, shareId)) && attempts < 10) {
        shareId = generateShareId();
        attempts++;
    }
    if (attempts >= 10) {
        throw new Error('Failed to generate unique share ID');
    }
    return shareId;
}

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

        const shareId = await createUniqueShareId('shared_recipes');
        const shareData = {
            recipeId,
            ownerId,
            title,
            imageURL: imageURL || null,
            ingredientCount: ingredientCount || 0,
            totalMinutes: totalMinutes || null,
            tags: tags || [],
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            viewCount: 0,
        };

        await db.collection('shared_recipes').doc(shareId).set(shareData);

        // Construct URL using the Hosting domain
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

        const shareId = await createUniqueShareId('shared_profiles');
        const shareData = {
            userId,
            username,
            displayName: displayName || username,
            profileImageURL: profileImageURL || null,
            recipeCount: recipeCount || 0,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            viewCount: 0,
        };

        await db.collection('shared_profiles').doc(shareId).set(shareData);

        const shareUrl = `https://cauldron-f900a.web.app/profile/${shareId}`;

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

        const shareId = await createUniqueShareId('shared_collections');
        const shareData = {
            collectionId,
            ownerId,
            title,
            coverImageURL: coverImageURL || null,
            recipeCount: recipeCount || 0,
            recipeIds: recipeIds || [],
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            viewCount: 0,
        };

        await db.collection('shared_collections').doc(shareId).set(shareData);

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

export const previewRecipe = onRequest({ cors: true, invoker: 'public' }, async (req, res) => {
    const pathParts = req.path.split('/');
    const shareId = pathParts[pathParts.length - 1]; // Last part of path

    if (!shareId) {
        res.status(400).send('Invalid share ID');
        return;
    }

    try {
        const doc = await db.collection('shared_recipes').doc(shareId).get();
        if (!doc.exists) {
            res.status(404).send('Recipe not found');
            return;
        }

        const data = doc.data()!;
        const title = data.title || 'Untitled Recipe';
        const imageURL = data.imageURL || null;
        const description = `Check out this recipe on Cauldron!`;
        const appURL = `cauldron://import/recipe/${shareId}`;
        const downloadURL = 'https://testflight.apple.com/join/Zk5WuCcE';

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

    try {
        const doc = await db.collection('shared_profiles').doc(shareId).get();
        if (!doc.exists) {
            res.status(404).send('Profile not found');
            return;
        }

        const data = doc.data()!;
        const title = data.displayName || data.username || 'Cauldron User';
        const imageURL = data.profileImageURL || null;
        const recipeCount = data.recipeCount || 0;
        const description = `Check out my Cauldron profile! ${recipeCount} recipes and counting 🍲`;
        const appURL = `cauldron://import/profile/${shareId}`;
        const downloadURL = 'https://testflight.apple.com/join/Zk5WuCcE';

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
        const downloadURL = 'https://testflight.apple.com/join/Zk5WuCcE';

        res.send(generatePreviewHtml(title, description, imageURL, appURL, downloadURL));
    } catch (error) {
        logger.error('Error loading collection preview:', error);
        res.status(500).send('Error loading preview');
    }
});
