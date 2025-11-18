import type { VercelRequest, VercelResponse } from '@vercel/node';
import admin from 'firebase-admin';
import { db, createUniqueShareId } from '../_utils';

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
      collectionId,
      ownerId,
      title,
      coverImageURL,
      recipeCount,
      recipeIds,
    } = req.body;

    if (!collectionId || !ownerId || !title) {
      return res.status(400).json({ error: 'Missing required fields' });
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

    const shareUrl = `https://${req.headers.host}/collection/${shareId}`;

    return res.status(200).setHeader('Access-Control-Allow-Origin', '*').json({
      shareId,
      shareUrl
    });
  } catch (error) {
    console.error('Error sharing collection:', error);
    return res.status(500).json({ error: 'Failed to create share link' });
  }
}
