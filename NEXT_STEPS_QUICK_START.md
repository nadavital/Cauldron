# External Sharing - Quick Start Guide

## What's Been Built ✅

I've implemented a complete external sharing system for Cauldron! Here's what's ready:

### Backend (Firebase)
- ✅ Cloud Functions for generating share links
- ✅ Firestore database for storing share metadata
- ✅ Web preview pages with Open Graph tags (for social media previews)
- ✅ Complete deployment configuration

### iOS App
- ✅ `ExternalShareService` - Generates and imports share links
- ✅ Deep link handling for `cauldron://` and `https://` URLs
- ✅ `ImportPreviewSheet` - Beautiful UI for importing shared content
- ✅ Share button in RecipeDetailView (for public recipes)
- ✅ iOS ShareSheet integration

### How It Works
1. User taps "Share Recipe" on a public recipe
2. App generates link via Firebase (e.g., `your-project.web.app/recipe/abc123`)
3. iOS ShareSheet appears → user shares via Messages/Instagram/etc.
4. Recipient sees rich preview with recipe image
5. Taps link → Opens in Cauldron app (or web preview if no app)
6. User imports recipe to their library

---

## Your Next Steps (30-60 minutes)

### Step 1: Deploy Firebase Backend (20-30 min)

**Open Terminal and run these commands:**

```bash
# Navigate to firebase directory
cd /Users/navital/Desktop/Cauldron/firebase

# Login to Firebase
firebase login

# Create Firebase project (or select existing)
# Follow the prompts to create a project named "Cauldron"

# Link your local code to the Firebase project
firebase use --add
# Select your project and name the alias "default"

# Save your project ID for later
firebase use
# You'll see something like: "Active Project: cauldron-abc123"
# Write down "cauldron-abc123" (your project ID)

# Install dependencies
cd functions
npm install
cd ..

# Deploy everything!
firebase deploy
```

**This will output:**
```
✔  Deploy complete!

Function URL(api): https://us-central1-YOUR-PROJECT-ID.cloudfunctions.net/api
Hosting URL: https://YOUR-PROJECT-ID.web.app
```

**Save these URLs!**

---

### Step 2: Enable Firebase Services (5-10 min)

Go to: https://console.firebase.google.com/

**Enable Firestore:**
1. Build → Firestore Database → "Create database"
2. Select "Production mode"
3. Choose region: us-central (or closest to you)
4. Click "Enable"

**Upgrade to Blaze Plan (for Cloud Functions):**
1. ⚙️ Settings → "Usage and billing"
2. "Modify plan" → Select "Blaze (Pay as you go)"
3. Add payment method
4. Don't worry - has generous FREE tier:
   - 2M function calls/month free
   - 50K Firestore reads/day free
   - You'll likely stay within free limits!

**Enable Hosting:**
1. Build → Hosting → "Get started"
2. Click through the wizard

---

### Step 3: Update iOS App with Firebase URL (2 min)

**File:** `/Users/navital/Desktop/Cauldron/Cauldron/Core/Services/ExternalShareService.swift`

Find line 53:
```swift
private let baseURL = "https://us-central1-YOUR-PROJECT-ID.cloudfunctions.net/api"
```

Replace `YOUR-PROJECT-ID` with your actual project ID from Step 1:
```swift
private let baseURL = "https://us-central1-cauldron-abc123.cloudfunctions.net/api"
```

---

### Step 4: Test It! (5 min)

**Test the API first:**
```bash
# Replace YOUR-PROJECT-ID with your actual ID
curl -X POST https://us-central1-YOUR-PROJECT-ID.cloudfunctions.net/api/share/recipe \
  -H "Content-Type: application/json" \
  -d '{
    "recipeId": "test-123",
    "ownerId": "user-456",
    "title": "Test Recipe",
    "imageURL": "https://example.com/image.jpg",
    "ingredientCount": 5,
    "totalMinutes": 30,
    "tags": ["dinner"]
  }'
```

Should return:
```json
{"shareId":"abc12345","shareUrl":"https://YOUR-PROJECT.web.app/recipe/abc12345"}
```

**Test in the app:**
1. Build and run Cauldron in Xcode
2. Navigate to a PUBLIC recipe
3. Tap the "..." menu → "Share Recipe"
4. ShareSheet should appear with a link
5. Share to yourself in Messages
6. Tap the link → Should show web preview page

---

## ✅ You're Done!

The basic sharing system is now working! Share links will look like:
- `https://your-project.web.app/recipe/x7k2m9p1`

---

## Optional Enhancements (Later)

### A. Add Universal Links (Better UX)

This makes links open directly in the app instead of Safari first.

**Add Associated Domains in Xcode:**
1. Open Cauldron.xcodeproj
2. Select target → Signing & Capabilities
3. Click "+ Capability" → "Associated Domains"
4. Add: `applinks:YOUR-PROJECT.web.app`

**Benefits:**
- Links open directly in app (no Safari redirect)
- Better user experience

### B. Add Custom Domain (Prettier URLs)

If you want `cauldron.app` instead of `YOUR-PROJECT.web.app`:
1. Buy domain (e.g., from Namecheap, GoDaddy)
2. Add to Firebase Hosting in console
3. Configure DNS records
4. Update API endpoint in ExternalShareService.swift

**Benefits:**
- Shorter, cleaner URLs
- Professional branding

### C. Add Share Buttons to Profile & Collections

Same pattern as Recipe sharing:
1. Add state variables
2. Add button to menu/toolbar
3. Call `externalShareService.shareProfile()` or `shareCollection()`
4. Present ShareSheet

I've already implemented the backend for these - you just need to add the UI buttons!

---

## Troubleshooting

### "Permission denied" when deploying
- Make sure you logged in: `firebase login`
- Make sure you upgraded to Blaze plan

### Share link generation fails
- Check API URL is correct in ExternalShareService.swift
- Check Firebase Functions logs: `firebase functions:log`
- Make sure Firestore is enabled

### Universal links not working
- Only works on physical devices (not Simulator)
- Delete and reinstall app after adding Associated Domains
- Wait a few minutes for iOS to fetch association file

---

## What's Next?

After testing the recipe sharing:

1. **Profile Sharing** - Add share button to ProfileView (same pattern)
2. **Collection Sharing** - Add share button to CollectionDetailView
3. **Analytics** - Track share counts in Firebase Console
4. **Custom Domain** - Make URLs prettier (optional)

The hard work is done - backend is deployed and iOS infrastructure is complete!

---

## Files Reference

**Firebase:**
- `/Users/navital/Desktop/Cauldron/firebase/` - All backend code
- `firebase/MANUAL_SETUP.md` - Detailed setup guide
- `firebase/README.md` - API documentation

**iOS:**
- `Core/Services/ExternalShareService.swift` - Sharing service
- `Core/Components/ImportPreviewSheet.swift` - Import UI
- `Core/Models/ShareableLink.swift` - Data models
- `Features/Library/RecipeDetailView.swift` - Share button

**Docs:**
- `SHARING_DEPLOYMENT_GUIDE.md` - Complete deployment guide
- `SHARING_IMPLEMENTATION_STATUS.md` - Full feature status

---

## Cost Estimate

**Firebase Free Tier:**
- 2M function calls/month
- 50K Firestore reads/day
- 10GB hosting/month

**Your Usage:**
- Recipe share: 1 function call + 1 Firestore write
- Link open: 1 Firestore read
- 1000 shares + 5000 views = Still FREE!

You'll likely stay within free tier unless you have thousands of daily active users.

---

Need help? Check the troubleshooting sections in:
- `firebase/MANUAL_SETUP.md`
- `SHARING_DEPLOYMENT_GUIDE.md`
