import type { VercelRequest, VercelResponse } from '@vercel/node';
import admin from 'firebase-admin';
import { db } from '../../_utils';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return res.status(200).json({});
  }

  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const { type, shareId } = req.query;

    const collectionMap: { [key: string]: string } = {
      recipe: 'shared_recipes',
      profile: 'shared_profiles',
      collection: 'shared_collections',
    };

    const collectionName = collectionMap[type as string];
    if (!collectionName) {
      return res.status(400).json({ error: 'Invalid share type' });
    }

    const doc = await db.collection(collectionName).doc(shareId as string).get();
    if (!doc.exists) {
      return res.status(404).json({ error: 'Share not found' });
    }

    // Increment view count
    await doc.ref.update({
      viewCount: admin.firestore.FieldValue.increment(1),
    });

    return res.status(200).setHeader('Access-Control-Allow-Origin', '*').json({
      success: true,
      data: doc.data(),
    });
  } catch (error) {
    console.error('Error fetching share data:', error);
    return res.status(500).json({ error: 'Failed to fetch share data' });
  }
}
