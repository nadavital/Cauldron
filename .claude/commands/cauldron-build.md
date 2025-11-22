---
description: Quick Xcode build for iPhone 16 simulator
allowed-tools: Bash(xcodebuild:*)
---

Build the Cauldron app for the iPhone 16 simulator. Parse any build errors and display them clearly.

Run this command:
```bash
xcodebuild -project Cauldron.xcodeproj -scheme Cauldron -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' build
```

If the build fails, analyze the error messages and suggest fixes.
