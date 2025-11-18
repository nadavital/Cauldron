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
    const { userId, username, displayName, profileImageURL, recipeCount } = req.body;

    if (!userId || !username) {
      return res.status(400).json({ error: 'Missing required fields' });
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

    const shareUrl = `https://${req.headers.host}/profile/${shareId}`;

    return res.status(200).setHeader('Access-Control-Allow-Origin', '*').json({
      shareId,
      shareUrl
    });
  } catch (error) {
    console.error('Error sharing profile:', error);
    return res.status(500).json({ error: 'Failed to create share link' });
  }
}
