# External Sharing Feature - Deployment Guide

This guide will help you deploy the complete external sharing system for Cauldron.

## Phase 1: Firebase Backend Setup

### Step 1: Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click "Add project"
3. Enter project name: **Cauldron**
4. Disable Google Analytics (optional)
5. Click "Create project"

### Step 2: Enable Required Services

**Enable Firestore:**
1. In Firebase Console → Build → Firestore Database
2. Click "Create database"
3. Choose "Start in production mode"
4. Select location (choose closest to your users, e.g., `us-central`)
5. Click "Enable"

**Enable Cloud Functions:**
1. In Firebase Console → Build → Functions
2. Click "Get started"
3. Upgrade to Blaze plan (pay-as-you-go, but has generous free tier)

**Enable Hosting:**
1. In Firebase Console → Build → Hosting
2. Click "Get started"
3. Follow the setup wizard

### Step 3: Install Firebase CLI

```bash
npm install -g firebase-tools
```

### Step 4: Login and Initialize

```bash
# Login to Firebase
firebase login

# Navigate to the firebase directory
cd /Users/navital/Desktop/Cauldron/firebase

# Initialize Firebase project
firebase use --add
# Select your "Cauldron" project from the list
# Give it an alias: "default"
```

### Step 5: Install Dependencies

```bash
cd functions
npm install
cd ..
```

### Step 6: Update API Endpoint

Before deploying, you need to update the API endpoint in the iOS app:

1. After running `firebase use --add`, note your Firebase project ID
2. Open `/Users/navital/Desktop/Cauldron/Cauldron/Core/Services/ExternalShareService.swift`
3. Find this line (around line 53):
   ```swift
   private let baseURL = "https://us-central1-YOUR-PROJECT-ID.cloudfunctions.net/api"
   ```
4. Replace `YOUR-PROJECT-ID` with your actual Firebase project ID
5. Example: `https://us-central1-cauldron-abc123.cloudfunctions.net/api`

### Step 7: Deploy to Firebase

```bash
# Deploy everything (functions, hosting, firestore rules)
firebase deploy

# This will output URLs like:
# Functions: https://us-central1-YOUR-PROJECT-ID.cloudfunctions.net/api
# Hosting: https://YOUR-PROJECT-ID.web.app
```

### Step 8: Test the Backend

```bash
# Test recipe sharing API
curl -X POST https://us-central1-YOUR-PROJECT-ID.cloudfunctions.net/api/share/recipe \
  -H "Content-Type: application/json" \
  -d '{
    "recipeId": "test-123",
    "ownerId": "user-456",
    "title": "Test Recipe",
    "imageURL": "https://example.com/image.jpg",
    "ingredientCount": 5,
    "totalMinutes": 30,
    "tags": ["dinner", "easy"]
  }'

# Should return: {"shareId":"abc12345","shareUrl":"https://cauldron.app/recipe/abc12345"}

# Test the preview page (use the shareId from above)
open https://YOUR-PROJECT-ID.web.app/recipe/abc12345
```

## Phase 2: Custom Domain Setup (cauldron.app)

### Step 1: Add Custom Domain in Firebase

1. In Firebase Console → Hosting
2. Click "Add custom domain"
3. Enter: `cauldron.app`
4. Click "Continue"
5. Firebase will show you DNS records to add

### Step 2: Configure DNS

Add these records to your domain registrar (GoDaddy, Namecheap, etc.):

```
Type: A
Name: cauldron.app (or @)
Value: [IP address from Firebase - shown in console]
TTL: 3600

Type: A
Name: www.cauldron.app (or www)
Value: [IP address from Firebase - shown in console]
TTL: 3600
```

**Note:** DNS propagation can take 24-48 hours

### Step 3: Create Apple App Site Association File

Once your custom domain is active, create this file:

**File:** `/Users/navital/Desktop/Cauldron/firebase/public/.well-known/apple-app-site-association`

```json
{
  "applinks": {
    "apps": [],
    "details": [{
      "appID": "TEAM_ID.Nadav.Cauldron",
      "paths": ["/recipe/*", "/profile/*", "/collection/*"]
    }]
  }
}
```

**To find your Team ID:**
1. Open Xcode
2. Select Cauldron project
3. Go to "Signing & Capabilities"
4. Your Team ID is shown next to your team name
5. Replace `TEAM_ID` in the file above

### Step 4: Deploy Updated Hosting

```bash
cd /Users/navital/Desktop/Cauldron/firebase
mkdir -p public/.well-known
# Create the apple-app-site-association file (from Step 3)
firebase deploy --only hosting
```

### Step 5: Verify Universal Links

```bash
# Test that the file is accessible
curl https://cauldron.app/.well-known/apple-app-site-association

# Should return the JSON content without errors
```

## Phase 3: iOS App Configuration

### Step 1: Update API Endpoint (Again)

Now that you have a custom domain, update the API endpoint to use it:

**File:** `/Users/navital/Desktop/Cauldron/Cauldron/Core/Services/ExternalShareService.swift`

Change:
```swift
private let baseURL = "https://us-central1-YOUR-PROJECT-ID.cloudfunctions.net/api"
```

To:
```swift
private let baseURL = "https://cauldron.app/api"
```

### Step 2: Add Associated Domains Capability

1. Open `Cauldron.xcodeproj` in Xcode
2. Select the "Cauldron" target
3. Go to "Signing & Capabilities" tab
4. Click "+ Capability"
5. Add "Associated Domains"
6. Click "+" under Associated Domains
7. Add: `applinks:cauldron.app`

**Screenshot of what it should look like:**
```
Associated Domains
    Domains
        applinks:cauldron.app
```

### Step 3: Build and Test

1. Build the app in Xcode
2. Run on a physical device (universal links don't work in Simulator)
3. Test the sharing flow

## Phase 4: Testing the Complete Flow

### Test 1: Share a Recipe

1. Open Cauldron app
2. Navigate to a public recipe
3. Tap the share button (once UI is implemented)
4. Share via Messages to yourself
5. Tap the link in Messages
6. Should see web preview with recipe image and details
7. Tap "Open in Cauldron" button
8. App should open and show import sheet

### Test 2: Social Media Preview

1. Share a recipe link
2. Paste it in Notes app
3. Should see rich preview with recipe image and title
4. Try sharing to Instagram/Facebook (in DMs)
5. Verify preview shows correctly

### Test 3: Without App Installed

1. Share link to someone without Cauldron installed
2. They tap the link
3. Should see web preview page
4. "Download Cauldron" button should open App Store

## Troubleshooting

### Universal Links Not Working

**Problem:** Tapping links opens Safari instead of app

**Solutions:**
1. Verify apple-app-site-association file is accessible at `https://cauldron.app/.well-known/apple-app-site-association`
2. Make sure you're testing on a physical device (not Simulator)
3. Delete and reinstall the app
4. Wait a few minutes after install for iOS to fetch the association file
5. Verify Team ID matches in both the association file and Xcode

### Share API Returning Errors

**Problem:** Share link generation fails

**Solutions:**
1. Check Firebase Functions logs: `firebase functions:log`
2. Verify Firestore rules allow writes
3. Check that your project is on Blaze (pay-as-you-go) plan
4. Verify API endpoint URL is correct in ExternalShareService.swift

### Preview Images Not Showing

**Problem:** Social media previews don't show images

**Solutions:**
1. Verify image URLs are publicly accessible (not behind authentication)
2. Check Open Graph meta tags in HTML preview pages
3. Use Facebook's [Sharing Debugger](https://developers.facebook.com/tools/debug/) to test
4. Clear social media cache (some platforms cache previews)

## Cost Estimates

### Firebase Free Tier (Generous)
- **Cloud Functions:** 2M invocations/month free
- **Hosting:** 10GB storage, 360MB/day transfer free
- **Firestore:** 50K reads, 20K writes, 1GB storage/day free

**Expected costs for Cauldron:**
- **Low usage (< 1000 users):** FREE
- **Medium usage (1000-10000 users):** $5-20/month
- **High usage (10000+ users):** $50-200/month

Most of the cost comes from Cloud Functions invocations and Firestore reads.

## Monitoring

### View Firebase Console

1. **Functions logs:** Build → Functions → Logs tab
2. **Firestore data:** Build → Firestore Database
3. **Hosting analytics:** Build → Hosting → Usage tab
4. **Cost tracking:** Spark (settings icon) → Usage and billing

### Key Metrics to Monitor

- Share link creation count (POST requests)
- Preview page views (GET requests)
- Import actions (app opens from links)
- Error rates in function logs

## Next Steps After Deployment

1. Implement share buttons in RecipeDetailView, ProfileView, CollectionDetailView
2. Implement deep link handling in CauldronApp.swift
3. Create ImportPreviewSheet UI
4. Test end-to-end flow
5. Submit app update to App Store

## Support

If you encounter issues:
1. Check Firebase Console logs
2. Review this guide's Troubleshooting section
3. Test with Firebase emulators locally first: `firebase emulators:start`
