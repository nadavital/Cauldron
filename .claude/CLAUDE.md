# Cauldron - Recipe Management iOS App

## Project Overview
Cauldron is a modern iOS recipe management and social sharing platform built with SwiftUI and CloudKit. Users can import recipes from multiple sources (web, YouTube, TikTok, Instagram), cook with interactive timers, share recipes with friends, and generate new recipes using Apple Intelligence.

**Current Version:** 1.2
**Deployment Target:** iOS 18.0+
**App Store:** Live on the App Store
**TestFlight:** https://testflight.apple.com/join/Zk5WuCcE

---

## Architecture

### Clean Architecture Pattern
The app follows a clean architecture with clear separation of concerns:

- **Core Layer** (`Cauldron/Core/`) - Shared business logic, models, services, persistence
- **Features Layer** (`Cauldron/Features/`) - Feature-specific UI and ViewModels
- **App Layer** (`Cauldron/App/`) - Dependency injection container and app lifecycle

### Key Technologies
- **UI Framework:** 100% SwiftUI (no UIKit/Storyboards)
- **Concurrency:** Swift Actors, async/await, Combine
- **Local Persistence:** SwiftData (modern replacement for Core Data)
- **Cloud Backend:** Apple CloudKit (primary) + Firebase (sharing/preview pages)
- **AI/ML:** Apple FoundationModels (on-device generation)

### Data Flow
```
User Action → ViewModel → Service → Repository → SwiftData/CloudKit → UI Update
```

### 5-Layer Dependency Container Architecture
Services are organized in the `DependencyContainer` in a clear hierarchy:

1. **Infrastructure Layer**: CloudKitCore, ModelContainer
2. **Cloud Services Layer**: RecipeCloudService, UserCloudService, CollectionCloudService, ConnectionCloudService, SearchCloudService
3. **Local Persistence Layer**: RecipeRepository, CollectionRepository, ConnectionRepository, etc.
4. **Domain Services Layer**: RecipeSyncService, ConnectionManager, GroceryService, SharingService, etc.
5. **Feature Services Layer**: EntityImageManager, RecipeImageService, TimerManager, Parsers, etc.

---

## Code Organization

### Feature Modules
Each feature is self-contained with its own views and view models:

- **Cook** (`Features/Cook/`) - Main recipe browsing tab
- **CookMode** (`Features/CookMode/`) - Active cooking with timers & live activities
- **Library** (`Features/Library/`) - Recipe editor & detail views
- **Search** (`Features/Search/`) - Explore page with tags
- **Collections** (`Features/Collections/`) - Recipe organization
- **Profile** (`Features/Profile/`) - User profile & friend management
- **Sharing** (`Features/Sharing/`) - Social features & CloudKit sharing
- **Groceries** (`Features/Groceries/`) - Grocery list with auto-categorization
- **AIGenerator** (`Features/AIGenerator/`) - Apple Intelligence recipe generation
- **Importer** (`Features/Importer/`) - Multi-source recipe import flow

### Core Services

#### CloudKit Services (`Cauldron/Core/Services/CloudKit/`)
Modular CloudKit services organized by domain:

- **CloudKitCore.swift** - Shared infrastructure (container, zones, account status)
- **CloudKitTypes.swift** - Common types, errors, and constants
- **RecipeCloudService.swift** - Recipe sync, sharing, and image operations
- **UserCloudService.swift** - User profiles and authentication
- **CollectionCloudService.swift** - Collection sync and sharing
- **ConnectionCloudService.swift** - Friend connections and requests
- **SearchCloudService.swift** - Recipe discovery and search

#### Image Management
Unified image management system using generic `EntityImageManager<T>`:

- **EntityImageManager.swift** (`Core/Utilities/`) - Generic actor for all entity images with:
  - Two-tier caching (memory + disk)
  - Request coalescing for duplicate downloads
  - Automatic image compression and resizing
  - CloudKit upload/download integration
- **RecipeImageService.swift** - Recipe image loading with CloudKit fallback
- **ImageSyncManager.swift** - Tracks pending image syncs with status reporting
- **CloudImageMigration.swift** - Background migration of images to public database
- **ImageCache.swift** - Shared in-memory image cache

Type aliases for domain-specific managers:
- `RecipeImageManager` = `EntityImageManager<RecipeModel>`
- `ProfileImageManagerV2` = `EntityImageManager<UserModel>`
- `CollectionImageManagerV2` = `EntityImageManager<CollectionModel>`

#### Other Services (`Cauldron/Core/Services/`)
- **RecipeSyncService.swift** - Recipe cloud synchronization with conflict resolution
- **OperationQueueService.swift** - Persistent operation queue for offline-first operations
- **CurrentUserSession.swift** - User authentication state singleton
- **ReferralManager.swift** - Referral system management
- **UnitsService.swift** - Unit conversion and scaling
- **GroceryService.swift** - Grocery list management
- **ConnectionManager.swift** - Friend connections
- **CookSessionManager.swift** - Active cooking sessions
- **SharingService.swift** - Recipe sharing coordination
- **ExternalShareService.swift** - External sharing (links, social)

### Persistence Layer
SwiftData repositories in `Cauldron/Core/Persistence/`:

- **RecipeRepository.swift** - CRUD operations for recipes
- **CollectionRepository.swift** - Recipe collections
- **ConnectionRepository.swift** - Friend connections
- **DeletedRecipeRepository.swift** - Soft deletes & sync
- **SharingRepository.swift** - CloudKit share records
- And more...

### Recipe Parsing
Platform-specific parsers in `Cauldron/Core/Parsing/`:

- **YouTubeRecipeParser.swift** - Extracts recipes from YouTube descriptions
- **InstagramRecipeParser.swift** - Parses Instagram recipe posts
- **TikTokRecipeParser.swift** - TikTok recipe extraction
- **HTMLRecipeParser.swift** - Schema.org structured data
- **TextRecipeParser.swift** - Plain text recipe parsing
- **IngredientParser.swift** - Natural language ingredient parsing

---

## CloudKit Architecture

### Container
- **Production:** `iCloud.Nadav.Cauldron`
- **Development:** Uses same container with dev zone

### Record Types
- `CD_Recipe` - User recipes with SwiftData mapping
- `CD_Collection` - Recipe collections
- `CD_Connection` - Friend connections
- `CD_DeletedRecipe` - Tombstone records for sync
- `CD_UserProfile` - User profile data
- And more SwiftData-generated types...

### Sharing Model
- CloudKit sharing for collaborative collections
- Public database for shared recipe previews
- Firebase hosting for web preview pages with Universal Links

### Sync Strategy
- Manual sync triggers via pull-to-refresh
- Actor-based concurrency for thread safety
- Conflict resolution via CloudKit change tokens
- Deleted item tracking with tombstone records
- Persistent operation queue for offline-first operations

### Service Architecture
CloudKit operations are organized into domain-specific services:

```
CloudKitCore (shared infrastructure)
    ├── RecipeCloudService (recipes)
    ├── UserCloudService (profiles)
    ├── CollectionCloudService (collections)
    ├── ConnectionCloudService (friends)
    └── SearchCloudService (discovery)
```

Each service is an actor that depends on `CloudKitCore` for shared functionality.

---

## Swift Coding Conventions

### Naming
- **Types:** PascalCase (`RecipeDetailView`, `CloudKitCore`)
- **Properties/Variables:** camelCase (`selectedRecipe`, `isLoading`)
- **Functions:** camelCase with verb prefix (`fetchRecipes()`, `updateProfile()`)
- **SwiftUI Views:** Noun-based names ending in `View` or `Screen`
- **Actors:** Suffix with `Service`, `Manager`, or `Repository`

### SwiftUI Best Practices
- **Prefer @Observable over ObservableObject** for iOS 17+
- **Use @State for view-local state**
- **Use @Environment for dependency injection**
- **Extract complex views into smaller components**
- **Keep ViewModels thin** - delegate to services
- **Use @MainActor for UI-bound classes**

### Concurrency
- **Use Swift actors** for shared mutable state (all services are actors)
- **Prefer async/await** over completion handlers
- **Use Task groups** for parallel operations
- **Avoid @MainActor.run** when possible - mark types instead

### Error Handling
- Use `Result<Success, Error>` for operations that can fail
- Throw errors from async functions
- Display user-friendly error messages in UI
- Log errors for debugging

### Memory Management
- **Avoid retain cycles** - use `[weak self]` in closures when needed
- **Use value types** (structs) where possible
- **Be careful with CloudKit references** - they hold strong references

---

## Testing Conventions

### Test Structure
Tests are organized in `CauldronTests/` mirroring the main app structure:
- `Features/` - Feature-level tests
- `Parsing/` - Parser tests (most comprehensive)
- `Persistence/` - Repository tests
- `Services/` - Service layer tests
- `TestHelpers/` - Mocks and fixtures

### Testing Patterns
- **Use MockCloudKitService** for CloudKit operations
- **Use TestModelContainer** for in-memory SwiftData
- **Test parsers with real-world examples** from TestFixtures
- **Follow AAA pattern:** Arrange, Act, Assert
- **Test edge cases:** Empty inputs, malformed data, nil values

### Coverage Goals
- **Critical paths:** 80%+ coverage
- **Parsers:** Comprehensive test coverage (currently best tested)
- **Services:** Focus on business logic, mock external dependencies
- **UI:** Test ViewModels, not SwiftUI views directly

See `CauldronTests/README.md` for detailed testing documentation.

---

## Build & Deployment

### Xcode Configuration
- **Project:** `Cauldron.xcodeproj`
- **Scheme:** Cauldron
- **Default Simulator:** iPhone 16, iOS latest
- **Build Configurations:** Debug, Release

### Entitlements
- CloudKit container: `iCloud.Nadav.Cauldron`
- App Groups: `group.Nadav.Cauldron`
- Push Notifications (background refresh)
- Associated Domains (Universal Links)

### Firebase Backend
Firebase is used for public recipe sharing and preview pages:
- **Functions:** TypeScript Cloud Functions in `firebase/functions/`
- **Hosting:** Static preview pages in `firebase/public/`
- **Firestore:** Share metadata storage
- **Deploy:** `firebase deploy --only functions` (from firebase/ directory)

### App Store
- Archive via Xcode → Product → Archive
- Distribute to App Store Connect
- TestFlight for beta testing

### CI/CD
- GitHub Actions for automated builds and tests
- SwiftLint for code quality checks
- Pre-commit hooks for local linting

---

## Common Workflows

### Adding a New Feature
1. Create feature directory in `Cauldron/Features/YourFeature/`
2. Add ViewModel with `@Observable` macro
3. Create SwiftUI views
4. Add services to `DependencyContainer.swift` if needed
5. Inject dependencies via `@Environment`
6. Add tests in `CauldronTests/Features/`

### Working with CloudKit
1. Choose the appropriate domain service (RecipeCloudService, UserCloudService, etc.)
2. Use async/await for all CloudKit calls
3. Handle errors gracefully - network can fail
4. For new functionality, extend the relevant domain service
5. Test with mock services

### Adding a New Recipe Parser
1. Create parser in `Cauldron/Core/Parsing/`
2. Conform to any existing parser protocols
3. Add detection logic to `PlatformDetector.swift`
4. Create comprehensive tests with real examples
5. Add to import flow in `ImporterViewModel.swift`

### Modifying SwiftData Models
1. Update model in `Cauldron/Core/Models/`
2. SwiftData handles migrations automatically for simple changes
3. For complex migrations, create migration plan
4. Test with fresh install and upgrade scenarios
5. CloudKit schema updates may require manual changes in CloudKit Console

---

## Known Issues & Technical Debt

### Test Coverage Gaps
- Many ViewModels lack tests
- Integration tests needed for sync scenarios

### Code Quality
- SwiftLint configured with lenient rules - gradually tighten over time
- Some files could benefit from further modularization

---

## Dependencies

### Zero External Dependencies in Main App
The app uses only Apple platform frameworks - no CocoaPods or SPM packages. This keeps the app lean and reduces maintenance burden.

### Firebase (Backend Only)
- `firebase-admin` (Node.js) for Cloud Functions
- `@google-cloud/firestore` for database operations

### Development Tools
- **SwiftLint** - Code style enforcement (install via Homebrew: `brew install swiftlint`)

---

## Useful Xcode Locations

- **Project File:** `/Users/nadav/Desktop/Cauldron/Cauldron.xcodeproj`
- **Main Source:** `/Users/nadav/Desktop/Cauldron/Cauldron/`
- **Tests:** `/Users/nadav/Desktop/Cauldron/CauldronTests/`
- **DerivedData:** `/Users/nadav/Library/Developer/Xcode/DerivedData/Cauldron-*/`
- **Build Logs:** `/Users/nadav/Library/Developer/Xcode/DerivedData/Cauldron-*/Logs/Build/`

---

## Performance Considerations

### Image Management
- Images stored in CloudKit as CKAssets
- Two-tier caching: memory (ImageCache) + disk (EntityImageManager)
- Request coalescing prevents duplicate downloads
- Automatic compression and resizing on save
- Background migration to public database for sharing

### SwiftData Query Performance
- Use `#Predicate` for type-safe filtering
- Index frequently queried properties
- Limit fetch batch sizes for large datasets
- Use `@Query` in views for automatic updates

### CloudKit Optimization
- Batch operations when possible
- Use CloudKit zones for better organization
- Implement pagination for large queries
- Cache frequently accessed data locally
- Persistent operation queue for offline resilience

---

## Additional Resources

- **Test Documentation:** `CauldronTests/README.md`
- **Firebase Deployment:** `.agent/workflows/deploy_web.md`
- **Apple CloudKit Docs:** Use the Apple Docs MCP server (`@apple-docs-mcp`)
- **SwiftUI Reference:** Query via Apple Docs MCP for latest patterns

---

## Working with Claude Code

This repository is configured with custom Claude Code tools:
- Use `/build` for quick Xcode builds
- Use `/install` to build and deploy to simulator/device
- Use `/test` to run the test suite
- Use `swift-ios-expert` agent for Apple framework questions
- Use `code-reviewer` agent for Swift code review
- CloudKit issues? The `cloudkit-debugging` skill activates automatically

See `.claude/` directory for all custom configurations.
