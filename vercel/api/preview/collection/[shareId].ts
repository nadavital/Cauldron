import type { VercelRequest, VercelResponse } from '@vercel/node';
import { db } from '../../_utils';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  const { shareId } = req.query;

  if (!shareId || typeof shareId !== 'string') {
    return res.status(400).send('Invalid share ID');
  }

  try {
    const doc = await db.collection('shared_collections').doc(shareId).get();
    if (!doc.exists) {
      return res.status(404).send('Collection not found');
    }

    const data = doc.data()!;
    const title = data.title || 'Untitled Collection';
    const coverImageURL = data.coverImageURL || 'https://cauldron.app/default-collection.png';
    const recipeCount = data.recipeCount || 0;
    const description = `${recipeCount} ${recipeCount === 1 ? 'recipe' : 'recipes'}`;
    const appURL = `cauldron://import/collection/${shareId}`;

    const html = `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${title} - Cauldron</title>

    <meta property="og:type" content="article">
    <meta property="og:url" content="https://${req.headers.host}/collection/${shareId}">
    <meta property="og:title" content="${title}">
    <meta property="og:description" content="${description}">
    <meta property="og:image" content="${coverImageURL}">

    <meta property="twitter:card" content="summary_large_image">
    <meta property="twitter:title" content="${title}">
    <meta property="twitter:description" content="${description}">
    <meta property="twitter:image" content="${coverImageURL}">

    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .container {
            background: white;
            border-radius: 20px;
            padding: 40px;
            max-width: 500px;
            width: 100%;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            text-align: center;
        }
        .collection-image {
            width: 100%;
            height: 300px;
            object-fit: cover;
            border-radius: 15px;
            margin-bottom: 24px;
        }
        h1 {
            font-size: 28px;
            margin-bottom: 12px;
            color: #1a1a1a;
        }
        .description {
            font-size: 16px;
            color: #666;
            margin-bottom: 32px;
        }
        .button {
            display: inline-block;
            background: #FF6B35;
            color: white;
            padding: 16px 32px;
            border-radius: 12px;
            text-decoration: none;
            font-weight: 600;
            font-size: 18px;
            margin: 8px;
            transition: transform 0.2s, box-shadow 0.2s;
        }
        .button:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(255,107,53,0.3);
        }
        .button.secondary {
            background: #4A5568;
        }
        .logo {
            font-size: 48px;
            margin-bottom: 16px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">🍲</div>
        <img src="${coverImageURL}" alt="${title}" class="collection-image" onerror="this.style.display='none'">
        <h1>${title}</h1>
        <p class="description">${description}</p>
        <a href="${appURL}" class="button">Open in Cauldron</a>
        <br>
        <a href="https://apps.apple.com/app/cauldron" class="button secondary">Download Cauldron</a>
    </div>
</body>
</html>
    `;

    res.setHeader('Content-Type', 'text/html');
    return res.status(200).send(html);
  } catch (error) {
    console.error('Error loading collection preview:', error);
    return res.status(500).send('Error loading preview');
  }
}
