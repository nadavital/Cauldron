---
description: Clean derived data and rebuild from scratch
allowed-tools: Bash(rm:*), Bash(xcodebuild:*)
---

Clean all build artifacts and perform a fresh build of Cauldron.

**Steps:**

1. Find and display the DerivedData directory:
```bash
DERIVED_DATA=$(xcodebuild -project Cauldron.xcodeproj -showBuildSettings | grep -m 1 "BUILD_DIR" | grep -oEi "/.*DerivedData/[^/]+")
echo "DerivedData location: $DERIVED_DATA"
```

2. Clean using Xcode:
```bash
xcodebuild clean -project Cauldron.xcodeproj -scheme Cauldron
```

3. Remove DerivedData for this project:
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/Cauldron-*
```

4. Rebuild from scratch:
```bash
xcodebuild -project Cauldron.xcodeproj \
  -scheme Cauldron \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  clean build
```

Display build status and any errors that occur.
