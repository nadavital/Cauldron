import type { VercelRequest, VercelResponse } from '@vercel/node';
import { db } from '../../_utils';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  const { shareId } = req.query;

  if (!shareId || typeof shareId !== 'string') {
    return res.status(400).send('Invalid share ID');
  }

  try {
    const doc = await db.collection('shared_profiles').doc(shareId).get();
    if (!doc.exists) {
      return res.status(404).send('Profile not found');
    }

    const data = doc.data()!;
    const displayName = data.displayName || data.username;
    const username = data.username;
    const profileImageURL = data.profileImageURL || 'https://cauldron.app/default-profile.png';
    const recipeCount = data.recipeCount || 0;
    const description = `${recipeCount} ${recipeCount === 1 ? 'recipe' : 'recipes'}`;
    const appURL = `cauldron://import/profile/${shareId}`;

    const html = `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${displayName} - Cauldron</title>

    <meta property="og:type" content="profile">
    <meta property="og:url" content="https://${req.headers.host}/profile/${shareId}">
    <meta property="og:title" content="${displayName} on Cauldron">
    <meta property="og:description" content="@${username} • ${description}">
    <meta property="og:image" content="${profileImageURL}">

    <meta property="twitter:card" content="summary">
    <meta property="twitter:title" content="${displayName} on Cauldron">
    <meta property="twitter:description" content="@${username} • ${description}">
    <meta property="twitter:image" content="${profileImageURL}">

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
        .profile-image {
            width: 120px;
            height: 120px;
            border-radius: 60px;
            object-fit: cover;
            margin: 0 auto 24px;
            border: 4px solid #FF6B35;
        }
        h1 {
            font-size: 28px;
            margin-bottom: 8px;
            color: #1a1a1a;
        }
        .username {
            font-size: 18px;
            color: #666;
            margin-bottom: 8px;
        }
        .description {
            font-size: 16px;
            color: #888;
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
        <img src="${profileImageURL}" alt="${displayName}" class="profile-image" onerror="this.style.display='none'">
        <h1>${displayName}</h1>
        <p class="username">@${username}</p>
        <p class="description">${description}</p>
        <a href="${appURL}" class="button">View Profile in Cauldron</a>
        <br>
        <a href="https://apps.apple.com/app/cauldron" class="button secondary">Download Cauldron</a>
    </div>
</body>
</html>
    `;

    res.setHeader('Content-Type', 'text/html');
    return res.status(200).send(html);
  } catch (error) {
    console.error('Error loading profile preview:', error);
    return res.status(500).send('Error loading preview');
  }
}
