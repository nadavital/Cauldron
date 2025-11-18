import admin from 'firebase-admin';

// Initialize Firebase Admin (singleton pattern)
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert({
      projectId: process.env.FIREBASE_PROJECT_ID,
      clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
      privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
    }),
  });
}

export const db = admin.firestore();

// Generate a unique 8-character share ID
export function generateShareId(): string {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  let result = '';
  for (let i = 0; i < 8; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

// Check if share ID already exists
export async function isShareIdUnique(
  collection: string,
  shareId: string
): Promise<boolean> {
  const doc = await db.collection(collection).doc(shareId).get();
  return !doc.exists;
}

// Generate unique share ID for a collection
export async function createUniqueShareId(collection: string): Promise<string> {
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

// CORS headers
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};
