---
description: Deploy the Firebase Functions to update the web landing page
---

1. Navigate to the firebase directory
```bash
cd firebase
```

2. Install dependencies (if needed)
```bash
cd functions && npm install && cd ..
```

3. Preflight the production CloudKit fields, permissions, server-to-server key,
   and Firebase secrets listed in `firebase/README.md`. Export the named QA
   records, then run the executable preflight. Do not continue until all tests
   and signed lookups succeed.
```bash
cd functions
npm run preflight:production
cd ..
```

4. Cut off the seven insecure legacy publishers first. Firebase updates
   functions independently, so do not describe a multi-function deploy as
   atomic. This bounded compatibility outage is the deliberate privacy-safe
   side of the rollout.
// turbo
```bash
firebase deploy --only functions:shareRecipe,functions:unshareRecipe,functions:shareProfile,functions:unshareProfile,functions:unshareAccount,functions:shareCollection,functions:unshareCollection
```

5. Verify every legacy endpoint returns HTTP 426, then deploy the authenticated
   V2 and read functions. Do not proceed if any legacy mutation still accepts a
   write.
```bash
for name in shareRecipe unshareRecipe shareProfile unshareProfile unshareAccount shareCollection unshareCollection; do curl -sS -o /dev/null -w "$name %{http_code}\n" "https://us-central1-cauldron-f900a.cloudfunctions.net/$name"; done
firebase deploy --only functions
```

6. Deploy hosting, locked-down Firestore rules, indexes, and TTL configuration.
```bash
firebase deploy --only hosting,firestore:rules,firestore:indexes
```

7. Release the V2-capable app immediately after the backend cutoff. Older builds
   keep reading existing links but receive an explicit update-required response
   if they attempt an insecure legacy publication.
