# CauldronTests

Comprehensive test suite for the Cauldron app. The `CauldronTests` target is already part of the Xcode project and uses synchronized filesystem groups, so new files under `CauldronTests/` are discovered by the target.

## Optional Code Coverage

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
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

### Run Specific Test Class
```bash
xcodebuild test \
  -project Cauldron.xcodeproj \
  -scheme Cauldron \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:CauldronTests/SocialRecipeParserArchitectureTests
```

### Run Specific Test Method
```bash
xcodebuild test \
  -project Cauldron.xcodeproj \
  -scheme Cauldron \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:CauldronTests/SocialRecipeParserArchitectureTests/testSocialParserExists
```

## Current Test Coverage

### ✅ Completed (Phase 1 - Partial)

#### Parsing Tests
- **SocialRecipeParserArchitectureTests** (architecture coverage)
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

1. **Run tests and fix any compilation issues**
2. **Write remaining Phase 1 tests:**
   - QuantityParserTests (if separate component exists)
   - TimerExtractorTests
3. **Move to Phase 2:** Repository tests with mocking

## Test Structure

```
CauldronTests/
├── TestHelpers/
│   ├── TestFixtures.swift          ✅ Sample data and fixtures
│   ├── MockCloudKitService.swift   🔜 Todo
│   └── MockModelContainer.swift    🔜 Todo
├── Parsing/
│   ├── SocialRecipeParserArchitectureTests.swift  ✅ Complete
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
