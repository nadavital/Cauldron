# Vercel Deployment Guide

## Quick Start

Follow these steps to deploy the Cauldron API to Vercel.

### 1. Install Vercel CLI

**If on corporate network (eBay):**

You don't need to install Vercel globally. Use `npx` with the public registry:

```bash
# No installation needed - npx will download and run Vercel
# Just use this command format for all Vercel commands:
npx --registry https://registry.npmjs.org vercel@latest [command]
```

**If on regular network:**

```bash
npm install -g vercel
```

### 2. Get Firebase Credentials

You need your Firebase service account credentials:

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project (`cauldron-f900a`)
3. Click the gear icon → Project Settings
4. Go to "Service Accounts" tab
5. Click "Generate new private key"
6. Download the JSON file (keep it safe!)

### 3. Deploy to Vercel

**If on corporate network (eBay):**

```bash
# Navigate to the vercel directory
cd vercel

# Login to Vercel (first time only)
npx --registry https://registry.npmjs.org vercel@latest login
# Visit the URL shown and authorize

# Deploy to preview
npx --registry https://registry.npmjs.org vercel@latest

# When prompted:
# - Link to existing project? No
# - What's your project's name? cauldron-api (or whatever you want)
# - In which directory is your code located? ./
```

**If on regular network:**

```bash
cd vercel
vercel login
vercel
```

### 4. Add Environment Variables

After the first deployment, you need to add Firebase credentials:

**Option A: Via Vercel Dashboard (Recommended)**

1. Go to [vercel.com/dashboard](https://vercel.com/dashboard)
2. Select your project (cauldron-api)
3. Go to Settings → Environment Variables
4. Add these variables from your Firebase service account JSON:

   ```
   FIREBASE_PROJECT_ID = "cauldron-f900a"
   FIREBASE_CLIENT_EMAIL = "firebase-adminsdk-xxxxx@cauldron-f900a.iam.gserviceaccount.com"
   FIREBASE_PRIVATE_KEY = "-----BEGIN PRIVATE KEY-----\nYour\nMulti\nLine\nKey\nHere\n-----END PRIVATE KEY-----\n"
   ```

   **Important for FIREBASE_PRIVATE_KEY:**
   - Keep the quotes around the value
   - Keep all the `\n` newline characters
   - Copy the entire value from `"-----BEGIN` to `KEY-----"`

**Option B: Via CLI**

```bash
vercel env add FIREBASE_PROJECT_ID
# Enter value: cauldron-f900a

vercel env add FIREBASE_CLIENT_EMAIL
# Enter value: firebase-adminsdk-xxxxx@cauldron-f900a.iam.gserviceaccount.com

vercel env add FIREBASE_PRIVATE_KEY
# Paste the entire private key including BEGIN/END markers
```

### 5. Deploy to Production

After adding environment variables:

**If on corporate network (eBay):**
```bash
npx --registry https://registry.npmjs.org vercel@latest --prod
```

**If on regular network:**
```bash
vercel --prod
```

You'll get a production URL like: `https://cauldron-api.vercel.app`

### 6. Update iOS App

Update the `baseURL` in `ExternalShareService.swift`:

```swift
private let baseURL = "https://cauldron-api.vercel.app/api"
```

Replace `cauldron-api.vercel.app` with your actual Vercel domain.

### 7. Test the Deployment

Test that everything works:

```bash
# Share a recipe (replace with your Vercel URL)
curl -X POST https://cauldron-api.vercel.app/api/share/recipe \
  -H "Content-Type: application/json" \
  -d '{
    "recipeId": "test-123",
    "ownerId": "user-123",
    "title": "Test Recipe",
    "ingredientCount": 5,
    "totalMinutes": 30
  }'

# You should get back:
# {"shareId":"abc12345","shareUrl":"https://cauldron-api.vercel.app/recipe/abc12345"}

# Then visit the preview page:
open https://cauldron-api.vercel.app/recipe/abc12345
```

## Custom Domain (Optional)

To use a custom domain like `api.cauldron.app`:

1. Go to your Vercel project → Settings → Domains
2. Add your custom domain
3. Update your DNS records as instructed by Vercel
4. Update the `baseURL` in `ExternalShareService.swift` to use your custom domain

## Troubleshooting

### Error: "Cannot find module 'firebase-admin'"

Run `npm install` in the vercel directory and redeploy.

### Error: "Invalid Firebase credentials"

Check that your environment variables are correctly set in Vercel dashboard. The `FIREBASE_PRIVATE_KEY` must include all newlines (`\n`).

### Error: "Share not found" when importing

Make sure Firestore is enabled in your Firebase project and the share was successfully created.

### Preview pages not working

Check the Vercel function logs:
- Go to Vercel dashboard → Your project → Deployments
- Click on the latest deployment → Functions
- Check the logs for errors

## Project Structure

```
vercel/
├── api/
│   ├── _utils.ts                    # Shared utilities
│   ├── share/
│   │   ├── recipe.ts               # POST /api/share/recipe
│   │   ├── profile.ts              # POST /api/share/profile
│   │   └── collection.ts           # POST /api/share/collection
│   ├── data/
│   │   └── [type]/[shareId].ts     # GET /api/data/:type/:shareId
│   └── preview/
│       ├── recipe/[shareId].ts     # GET /recipe/:shareId
│       ├── profile/[shareId].ts    # GET /profile/:shareId
│       └── collection/[shareId].ts # GET /collection/:shareId
├── package.json
├── vercel.json                      # Vercel config
└── README.md
```

## API Endpoints

### Share Endpoints
- `POST /api/share/recipe` - Create recipe share link
- `POST /api/share/profile` - Create profile share link
- `POST /api/share/collection` - Create collection share link

### Data Endpoint
- `GET /api/data/:type/:shareId` - Get share data (for app import)

### Preview Pages
- `GET /recipe/:shareId` - Recipe preview page (HTML)
- `GET /profile/:shareId` - Profile preview page (HTML)
- `GET /collection/:shareId` - Collection preview page (HTML)

## Environment Variables

Required in Vercel:

- `FIREBASE_PROJECT_ID` - Your Firebase project ID
- `FIREBASE_CLIENT_EMAIL` - Service account email
- `FIREBASE_PRIVATE_KEY` - Service account private key (with newlines)

## Next Steps

After deployment:

1. ✅ Test all API endpoints
2. ✅ Update iOS app with production URL
3. ✅ Test sharing a recipe from the app
4. ✅ Test importing a shared link
5. ✅ Verify preview pages display correctly
6. 🎉 Share your first recipe!
