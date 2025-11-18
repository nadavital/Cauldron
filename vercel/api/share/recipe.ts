import type { VercelRequest, VercelResponse } from '@vercel/node';
import admin from 'firebase-admin';
import { db, createUniqueShareId, corsHeaders } from '../_utils';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return res.status(200).json({});
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
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

    // Validate required fields
    if (!recipeId || !ownerId || !title) {
      return res.status(400).json({ error: 'Missing required fields' });
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

    const shareUrl = `https://${req.headers.host}/recipe/${shareId}`;

    return res.status(200).setHeader('Access-Control-Allow-Origin', '*').json({
      shareId,
      shareUrl
    });
  } catch (error) {
    console.error('Error sharing recipe:', error);
    return res.status(500).json({ error: 'Failed to create share link' });
  }
}
