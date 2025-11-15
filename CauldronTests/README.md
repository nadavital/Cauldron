# CauldronTests

Comprehensive test suite for the Cauldron iOS app.

## Setup Instructions

### 1. Add Test Target to Xcode

Since the test files have been created, you need to add the test target to the Xcode project:

1. Open **Cauldron.xcodeproj** in Xcode
2. Go to **File > New > Target**
3. Select **iOS > Test > Unit Testing Bundle**
4. Click **Next**
5. Set the following:
   - **Product Name:** CauldronTests
   - **Team:** (Your team)
   - **Organization Identifier:** (Your org ID)
   - **Project:** Cauldron
   - **Target to be Tested:** Cauldron
6. Click **Finish**

### 2. Configure Test Target

1. Select the **CauldronTests** target in project settings
2. Go to **Build Phases**
3. In **Dependencies**, ensure **Cauldron** is listed
4. Go to **Build Settings**
   - Set **iOS Deployment Target** to match main app (iOS 17.0+)
   - Verify **TEST_HOST** is set to `$(BUILT_PRODUCTS_DIR)/Cauldron.app/$(BUNDLE_EXECUTABLE_PATH)`
5. Go to **General**
   - Set **Host Application** to **Cauldron**

### 3. Add Test Files to Target

The test files are already created in the `CauldronTests/` directory. You need to add them to the target:

1. In Xcode, right-click the project navigator
2. Select **Add Files to "Cauldron"...**
3. Navigate to the `CauldronTests` folder
4. Select the folder and click **Add**
5. Make sure **CauldronTests** target is checked

Alternatively, drag the files from Finder into the Xcode project navigator.

### 4. Enable Code Coverage

1. Edit the **Cauldron** scheme (Product > Scheme > Edit Scheme)
2. Select **Test** in the sidebar
3. Go to **Options** tab
4. Check **Code Coverage** and select **Cauldron** target
5. Click **Close**

## Running Tests

### Run All Tests
```bash
# In Xcode
⌘ + U

# Or from command line
xcodebuild test \
  -project Cauldron.xcodeproj \
  -scheme Cauldron \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'
```

### Run Specific Test Class
```bash
xcodebuild test \
  -project Cauldron.xcodeproj \
  -scheme Cauldron \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  -only-testing:CauldronTests/YouTubeRecipeParserTests
```

### Run Specific Test Method
```bash
xcodebuild test \
  -project Cauldron.xcodeproj \
  -scheme Cauldron \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  -only-testing:CauldronTests/YouTubeRecipeParserTests/testParseQuantityValue_Decimal
```

## Current Test Coverage

### ✅ Completed (Phase 1 - Partial)

#### Parsing Tests
- **YouTubeRecipeParserTests** (50+ tests)
  - ✅ Quantity parsing (decimal, fractions, mixed, unicode)
  - ✅ Unit parsing (all standard units + abbreviations)
  - ✅ Ingredient text parsing
  - ✅ Section detection (ingredients vs steps)
  - ✅ Numbered step detection
  - ✅ Description validation
  - ✅ Meta tag extraction
  - ✅ Video title extraction
  - ✅ ytInitialData extraction
  - ⚠️ Integration tests (require network mocking)

- **PlatformDetectorTests** (30+ tests)
  - ✅ YouTube URL detection (all formats)
  - ✅ TikTok URL detection
  - ✅ Instagram URL detection
  - ✅ Recipe website detection
  - ✅ YouTube URL normalization
  - ✅ Edge cases and case insensitivity

### 🔜 Next Steps

1. **Add test target to Xcode** (follow instructions above)
2. **Run tests and fix any compilation issues**
3. **Write remaining Phase 1 tests:**
   - QuantityParserTests (if separate component exists)
   - TimerExtractorTests
4. **Move to Phase 2:** Repository tests with mocking

## Test Structure

```
CauldronTests/
├── TestHelpers/
│   ├── TestFixtures.swift          ✅ Sample data and fixtures
│   ├── MockCloudKitService.swift   🔜 Todo
│   └── MockModelContainer.swift    🔜 Todo
├── Parsing/
│   ├── YouTubeRecipeParserTests.swift  ✅ Complete
│   ├── PlatformDetectorTests.swift     ✅ Complete
│   ├── QuantityParserTests.swift       🔜 Todo
│   └── TimerExtractorTests.swift       🔜 Todo
├── Persistence/
│   ├── RecipeRepositoryTests.swift     🔜 Todo
│   └── CollectionRepositoryTests.swift 🔜 Todo
├── Services/
│   └── CloudKitServiceTests.swift      🔜 Todo
└── Features/
    └── ImporterViewModelTests.swift    🔜 Todo
```

## Test Conventions

### Naming
- Test files: `[ComponentName]Tests.swift`
- Test methods: `test[Method]_[Scenario]_[ExpectedResult]`
- Example: `testParseQuantityValue_MixedNumber_ReturnsCorrectValue`

### Structure
```swift
func testSomething() async {
    // Given - Set up test data
    let input = "test data"

    // When - Execute the code being tested
    let result = await parser.parse(input)

    // Then - Verify expectations
    XCTAssertEqual(result, expectedValue)
}
```

### Async Testing
- Use `async` test methods for actor methods
- Use `await` when calling actor methods
- Clean up in `tearDown()`

## Known Issues

1. **YouTubeRecipeParser is an actor** - All test methods must be `async` and use `await`
2. **Network mocking needed** - Integration tests require mocking URLSession
3. **SwiftData testing** - Repository tests need in-memory ModelContainer setup

## Contributing Tests

When adding new tests:

1. Update the test count in [TESTING_PLAN.md](../TESTING_PLAN.md)
2. Follow the naming conventions
3. Add test fixtures to `TestFixtures.swift` if needed
4. Document any mocks or special setup required
5. Ensure tests are isolated (no shared state)

## Resources

- [TESTING_PLAN.md](../TESTING_PLAN.md) - Full testing roadmap
- [XCTest Documentation](https://developer.apple.com/documentation/xctest)
- [Testing Actors in Swift](https://developer.apple.com/documentation/swift/actor)
