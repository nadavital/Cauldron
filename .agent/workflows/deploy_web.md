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

3. Deploy the functions
// turbo
```bash
firebase deploy --only functions
```

4. (Optional) Deploy hosting if you have static assets changes
```bash
firebase deploy --only hosting
```
