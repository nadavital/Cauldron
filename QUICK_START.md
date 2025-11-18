# Quick Start - Deploy Cauldron API

## Corporate Network (eBay) - Use This! 🏢

Since you're on eBay's corporate network, use these commands:

### Option 1: Use the deployment script (easiest)

```bash
cd vercel
./deploy.sh
```

The script will:
- Login to Vercel (first time)
- Ask if you want preview or production
- Deploy automatically

### Option 2: Manual commands

```bash
cd vercel

# Login (first time only)
npx --registry https://registry.npmjs.org vercel@latest login

# Deploy to preview (for testing)
npx --registry https://registry.npmjs.org vercel@latest

# Or deploy to production
npx --registry https://registry.npmjs.org vercel@latest --prod
```

## After Deployment

### 1. Get your Vercel URL

After deployment, you'll see something like:
```
✅ Deployed to production: https://cauldron-api-abc123.vercel.app
```

Copy this URL!

### 2. Add Firebase credentials

Go to [vercel.com/dashboard](https://vercel.com/dashboard):
1. Select your project (cauldron-api)
2. Settings → Environment Variables
3. Add these variables from your Firebase service account JSON:

```
FIREBASE_PROJECT_ID = "cauldron-f900a"
FIREBASE_CLIENT_EMAIL = "firebase-adminsdk-xxxxx@cauldron-f900a.iam.gserviceaccount.com"
FIREBASE_PRIVATE_KEY = "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
```

**Get Firebase credentials:**
- Firebase Console → Project Settings → Service Accounts
- Click "Generate new private key"
- Download the JSON file and copy the values

### 3. Redeploy after adding env vars

```bash
npx --registry https://registry.npmjs.org vercel@latest --prod
```

### 4. Update iOS app

Edit `Cauldron/Core/Services/ExternalShareService.swift`:

Change line 46 from:
```swift
private let baseURL = "https://your-project.vercel.app/api"
```

To (using your actual Vercel URL):
```swift
private let baseURL = "https://cauldron-api-abc123.vercel.app/api"
```

### 5. Test it!

```bash
# Test share endpoint (replace with your URL)
curl -X POST https://your-vercel-url.vercel.app/api/share/recipe \
  -H "Content-Type: application/json" \
  -d '{
    "recipeId": "test-123",
    "ownerId": "user-123",
    "title": "Test Recipe",
    "ingredientCount": 5,
    "totalMinutes": 30
  }'
```

You should get back a share URL!

## Troubleshooting

### Error: npm ENOTFOUND

✅ **Solution:** You're already using the right command with `--registry https://registry.npmjs.org`

### Error: "Invalid Firebase credentials"

Make sure you:
1. Added all 3 environment variables in Vercel dashboard
2. The `FIREBASE_PRIVATE_KEY` includes the full key with `\n` characters
3. Redeployed after adding the variables

### Can't find Vercel CLI

✅ **Solution:** Use `npx` - no installation needed!

## Full Documentation

- `VERCEL_DEPLOYMENT_GUIDE.md` - Complete step-by-step guide
- `vercel/README.md` - API documentation
- `VERCEL_MIGRATION_SUMMARY.md` - What changed from Firebase

## Time Estimate

- First-time setup: ~10 minutes
- Deployment: ~2 minutes
- Total: ~12 minutes to working API! 🎉
