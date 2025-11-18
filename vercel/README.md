# Cauldron API - Vercel Serverless Functions

Backend API for Cauldron recipe sharing, deployed on Vercel.

## API Endpoints

### Share Endpoints (POST)
- `/api/share/recipe` - Create a shareable recipe link
- `/api/share/profile` - Create a shareable profile link
- `/api/share/collection` - Create a shareable collection link

### Data Endpoint (GET)
- `/api/data/:type/:shareId` - Get share data for app import
  - Types: `recipe`, `profile`, `collection`

### Preview Pages (GET)
- `/recipe/:shareId` - HTML preview page for recipes
- `/profile/:shareId` - HTML preview page for profiles
- `/collection/:shareId` - HTML preview page for collections

## Deployment

### Prerequisites
1. Install Vercel CLI:
   ```bash
   npm install -g vercel
   ```

2. Get Firebase credentials:
   - Go to Firebase Console → Project Settings → Service Accounts
   - Generate new private key
   - Download the JSON file

### First-time Setup

1. Install dependencies:
   ```bash
   cd vercel
   npm install
   ```

2. Login to Vercel:
   ```bash
   vercel login
   ```

3. Deploy and configure:
   ```bash
   vercel
   ```

4. Add environment variables in Vercel dashboard:
   - Go to your project → Settings → Environment Variables
   - Add these variables from your Firebase service account JSON:
     - `FIREBASE_PROJECT_ID` = "your-project-id"
     - `FIREBASE_CLIENT_EMAIL` = "your-service-account-email"
     - `FIREBASE_PRIVATE_KEY` = "your-private-key" (keep the quotes and newlines)

5. Redeploy after adding env vars:
   ```bash
   vercel --prod
   ```

### Production Deployment

To deploy to production:
```bash
vercel --prod
```

Your API will be live at: `https://your-project.vercel.app`

## Update iOS App

After deployment, update the `baseURL` in `ExternalShareService.swift`:

```swift
private let baseURL = "https://your-project.vercel.app/api"
```

## Testing

Test the endpoints:

```bash
# Share a recipe
curl -X POST https://your-project.vercel.app/api/share/recipe \
  -H "Content-Type: application/json" \
  -d '{
    "recipeId": "test123",
    "ownerId": "user123",
    "title": "Test Recipe",
    "ingredientCount": 5,
    "totalMinutes": 30
  }'

# Get share data
curl https://your-project.vercel.app/api/data/recipe/abcd1234

# Preview page
open https://your-project.vercel.app/recipe/abcd1234
```

## Project Structure

```
vercel/
├── api/
│   ├── _utils.ts              # Shared utilities (Firestore, helpers)
│   ├── share/
│   │   ├── recipe.ts         # POST /api/share/recipe
│   │   ├── profile.ts        # POST /api/share/profile
│   │   └── collection.ts     # POST /api/share/collection
│   ├── data/
│   │   └── [type]/
│   │       └── [shareId].ts  # GET /api/data/:type/:shareId
│   └── preview/
│       ├── recipe/
│       │   └── [shareId].ts  # GET /recipe/:shareId
│       ├── profile/
│       │   └── [shareId].ts  # GET /profile/:shareId
│       └── collection/
│           └── [shareId].ts  # GET /collection/:shareId
├── package.json
├── vercel.json               # Vercel configuration & rewrites
└── README.md
```

## Environment Variables

Required environment variables (set in Vercel dashboard):

- `FIREBASE_PROJECT_ID` - Your Firebase project ID
- `FIREBASE_CLIENT_EMAIL` - Firebase service account email
- `FIREBASE_PRIVATE_KEY` - Firebase service account private key

## Firestore Collections

The API uses these Firestore collections:

- `shared_recipes` - Shared recipe metadata
- `shared_profiles` - Shared profile metadata
- `shared_collections` - Shared collection metadata

## Notes

- All endpoints support CORS for web clients
- Share IDs are 8-character random strings
- View counts are tracked automatically
- HTML previews include Open Graph tags for social media
