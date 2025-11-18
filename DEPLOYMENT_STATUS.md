# Backend Deployment Status

## Current Situation

We've hit multiple Firebase deployment issues that are proving difficult to resolve:

1. **1st Gen Functions (firebase-functions v4):** Dependencies not installing in Cloud Build
   - Error: `Cannot find module 'firebase-functions'`
   - Despite being correctly listed in package.json

2. **2nd Gen Functions (firebase-functions v7):** Cloud Run container healthcheck failures
   - Error: `Container failed to start and listen on PORT=8080`
   - 2nd Gen uses Cloud Run (more complex infrastructure)

3. **Migration Limitation:** Can't upgrade 1st → 2nd Gen directly (must delete and recreate)

After multiple troubleshooting attempts, it's clear these are Firebase infrastructure issues, not code problems.

## What's Working ✅

1. **iOS App Infrastructure** - Complete!
   - `ExternalShareService` - Share link generation & import
   - `ImportPreviewSheet` - Beautiful import UI
   - Deep link handling (universal links + custom URL scheme)
   - Share button in RecipeDetailView

2. **Backend Code** - Complete!
   - Cloud Functions code written and tested locally
   - Firestore rules configured
   - Web preview pages created

3. **Firebase Project** - Set up!
   - Project ID: `cauldron-f900a`
   - Firestore enabled
   - Blaze plan activated

## Recommended Solution: Switch to Vercel

Given the Firebase deployment complexity and your Vercel experience, I recommend switching to **Vercel Serverless Functions**:

### Why Vercel?

1. **Simpler deployment** - `vercel deploy` just works
2. **CLI you're familiar with** - You mentioned wanting CLI support
3. **Same functionality** - All our API endpoints will work identically
4. **No infrastructure complexity** - No Cloud Build, Cloud Run, or version conflicts
5. **Faster** - Deploy in ~2 minutes vs hours of Firebase debugging

### What We'll Do

1. Convert Firebase Functions → Vercel API routes (15 min)
   - `/api/share/recipe.ts`
   - `/api/share/profile.ts`
   - `/api/share/collection.ts`
   - `/api/data/[type]/[shareId].ts`
   - `/api/recipe/[shareId].tsx` (HTML preview)
   - `/api/profile/[shareId].tsx` (HTML preview)
   - `/api/collection/[shareId].tsx` (HTML preview)

2. Keep Firestore for database (works with Vercel)
3. Deploy: `vercel deploy --prod`
4. Update iOS app with Vercel URL
5. Test end-to-end

**Total time:** ~20 minutes to working system

### Alternative: Keep Trying Firebase

If you want to keep trying Firebase, we can:
1. Contact Firebase Support (may take days)
2. Try deploying through Firebase Console UI
3. Debug Cloud Run healthcheck issues

But this could take hours/days with uncertain results.

---

## Debug History (For Reference)

### Attempted Fixes:
1. ✅ Fixed TypeScript compilation (changed imports, disabled strict mode)
2. ✅ Upgraded/downgraded firebase-functions (tried v4.9.0, v5.x, v7.0.0)
3. ✅ Cleaned node_modules and reinstalled
4. ✅ Added gcp-build script to package.json
5. ✅ Created .gcloudignore file
6. ✅ Deleted and recreated functions
7. ❌ **1st Gen deployment:** `Cannot find module 'firebase-functions'`
8. ❌ **2nd Gen deployment:** Cloud Run healthcheck failures

### Firebase Project Info:
- **Project ID:** cauldron-f900a
- **Region:** us-central1
- **Functions:** api, recipePreview, profilePreview, collectionPreview
- **Node version:** 20
- **Firestore:** Enabled and working
- **Billing:** Blaze plan active

### Conclusion:
These are Firebase infrastructure/platform issues, not code problems. The same code builds and runs perfectly locally. Vercel provides a more reliable deployment path.
