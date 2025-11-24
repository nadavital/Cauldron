---
description: Run XCTest suite with coverage report
allowed-tools: Bash(xcodebuild:*), Bash(xcrun:*)
---

Run the Cauldron test suite and display results with code coverage.

**Steps:**

1. Run tests with code coverage enabled:
```bash
xcodebuild test \
  -project Cauldron.xcodeproj \
  -scheme Cauldron \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  -enableCodeCoverage YES \
  -resultBundlePath /tmp/CauldronTestResults.xcresult
```

2. Extract and display test results:
```bash
xcrun xcresulttool get --format json --path /tmp/CauldronTestResults.xcresult
```

3. Summarize the output:
   - Total tests run
   - Passed tests
   - Failed tests (with failure details)
   - Code coverage percentage (if available)

If tests fail, display the specific failures and suggest next steps.
