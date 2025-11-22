---
description: Build and install Cauldron on simulator or device
allowed-tools: Bash(xcodebuild:*), Bash(xcrun simctl:*)
argument-hint: [device-name]
---

Build and install the Cauldron app on a connected device or simulator.

**Steps:**

1. If an argument is provided ($1), use that as the device name. Otherwise, default to "iPhone 16".

2. First, list available devices to confirm the target exists:
```bash
xcrun simctl list devices available | grep -i "$DEVICE_NAME" || xcrun simctl list devices booted
```

3. Build and install:
```bash
xcodebuild -project Cauldron.xcodeproj \
  -scheme Cauldron \
  -destination "platform=iOS Simulator,name=$DEVICE_NAME,OS=latest" \
  -derivedDataPath /tmp/CauldronBuild \
  build
```

4. Get the app bundle path and install it on the simulator:
```bash
APP_PATH=$(find /tmp/CauldronBuild/Build/Products -name "Cauldron.app" | head -n 1)
DEVICE_UDID=$(xcrun simctl list devices | grep "$DEVICE_NAME" | grep -E -o -i "([0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12})" | head -n 1)
xcrun simctl install $DEVICE_UDID "$APP_PATH"
```

5. Launch the app:
```bash
xcrun simctl launch $DEVICE_UDID Nadav.Cauldron
```

Display success message with the device name when complete.
