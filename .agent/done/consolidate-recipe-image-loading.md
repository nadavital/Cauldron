# ExecPlan: Consolidate Recipe Image Loading into a Single Pipeline

## Assumptions
- Scope is the whole repository at `/Users/nadav/Desktop/Cauldron`.
- Production-level caution is required (app has tests and user-facing CloudKit sync behavior).
- The goal is to reduce conceptual and file surface area, not to redesign storage/sync architecture.

## Problem Statement
Recipe image loading currently uses overlapping abstractions:
- `RecipeImageService` maintains its own `NSCache` and performs load/fallback logic (`/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/RecipeImageService.swift`).
- `RecipeImageView` and `HeroRecipeImageView` each duplicate cache checks, fetch flow, image-comparison logic, and cache writes (`/Users/nadav/Desktop/Cauldron/Cauldron/Core/Components/RecipeImageView.swift`).
- The app already has a global image cache used across features (`/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/ImageCache.swift`).

This creates double-caching, duplicated code paths, and higher bug risk when image behavior changes.

## Evidence-Based Mental Model

### Core concepts and locations
- App composition root and service graph:
  - `/Users/nadav/Desktop/Cauldron/Cauldron/App/DependencyContainer.swift`
- Recipe storage/sync:
  - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Persistence/RecipeRepository.swift`
  - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Persistence/RecipeRepository+Images.swift`
  - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/RecipeSyncService.swift`
- Unified image storage and cloud transport:
  - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Utilities/EntityImageManager.swift`
- UI recipe image rendering:
  - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Components/RecipeImageView.swift`
- Call sites:
  - `/Users/nadav/Desktop/Cauldron/Cauldron/Features/Library/RecipeDetailView.swift`
  - `/Users/nadav/Desktop/Cauldron/Cauldron/Features/Importer/RecipeImportPreviewView.swift`
  - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Components/RecipeCardView.swift`
  - `/Users/nadav/Desktop/Cauldron/Cauldron/Features/Cook/RecipeRowView.swift`
  - `/Users/nadav/Desktop/Cauldron/Cauldron/Features/Library/RecipeEditorViewModel.swift`

### Dependency/call-path highlights (3 core flows)
1. Import flow:
   - `ImporterViewModel.importFromURL` downloads and stores recipe images via `imageManager`
   - then UI loads via `RecipeImageService` + `RecipeImageView`
   - Files:
     - `/Users/nadav/Desktop/Cauldron/Cauldron/Features/Importer/ImporterViewModel.swift`
     - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Utilities/EntityImageManager.swift`
     - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/RecipeImageService.swift`
2. Library/detail flow:
   - `RecipeDetailView` uses `HeroRecipeImageView(recipe: recipe, recipeImageService: ...)`
   - hero view duplicates loading pipeline already present in `RecipeImageView`
   - Files:
     - `/Users/nadav/Desktop/Cauldron/Cauldron/Features/Library/RecipeDetailView.swift`
     - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Components/RecipeImageView.swift`
3. Edit flow:
   - `RecipeEditorViewModel` first checks `ImageCache`, then calls `RecipeImageService.loadImage`
   - This repeats cache and load behavior already embedded in image views
   - File:
     - `/Users/nadav/Desktop/Cauldron/Cauldron/Features/Library/RecipeEditorViewModel.swift`

### Identified smells with file evidence
- Duplicate abstraction:
  - service-level caching (`NSCache`) and app-level `ImageCache` both cache recipe images.
- Thin/overlapping wrappers:
  - `RecipeImageService` and views both handle cache read/write and fallback orchestration.
- Shotgun surgery risk:
  - cache/fallback behavior changes require edits in multiple places in the same file and service.

## Candidate Refactors and Ranking

| Candidate | Payoff (30%) | Blast Radius (25%) | Cognitive Load (20%) | Velocity Unlock (15%) | Validation/Rollback (10%) | Weighted |
|---|---:|---:|---:|---:|---:|---:|
| A. Consolidate recipe image loading/caching into one pipeline (remove duplicated view logic and service cache overlap) | 5 | 4 | 5 | 4 | 4 | 4.50 |
| B. Consolidate image-sync pending state into `OperationQueueService` (replace `ImageSyncManager`) | 4 | 3 | 4 | 4 | 3 | 3.65 |
| C. Unify `ConnectionManager` retry queue with `OperationQueueService` | 4 | 2 | 3 | 3 | 2 | 2.95 |

Chosen refactor: **A**, highest weighted score with small-to-medium blast radius and clear rollback.

## Proposed Refactor (Single Recommendation)

### Current state
- `RecipeImageService` owns an internal cache and loading logic.
- `RecipeImageView` and `HeroRecipeImageView` each replicate nearly the same loading + caching behavior.
- `ImageCache` is already the shared cache abstraction used throughout the app.

### Proposed change
Create one shared recipe image loading pipeline and remove overlap:
1. Make `RecipeImageService` the single source of loading/fallback behavior but use only `ImageCache` for memory cache (remove private `NSCache`).
2. Extract duplicated load/cached-image logic from `RecipeImageView` and `HeroRecipeImageView` into a shared internal helper (or shared view model) inside `RecipeImageView.swift`.
3. Keep UI-specific rendering differences (hero vs card/thumbnail) separate, but reuse one loader path.
4. Keep CloudKit fallback behavior unchanged.

### Files/directories impacted
- `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/RecipeImageService.swift`
- `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Components/RecipeImageView.swift`
- `/Users/nadav/Desktop/Cauldron/Cauldron/Features/Library/RecipeEditorViewModel.swift`
- `/Users/nadav/Desktop/Cauldron/Cauldron/App/DependencyContainer.swift` (only if constructor/API shape changes)
- Optional tests:
  - `/Users/nadav/Desktop/Cauldron/CauldronTests/Features/...` (new tests)
  - `/Users/nadav/Desktop/Cauldron/CauldronTests/Services/...` (new tests)

### Expected outcome (new shape)
- One cache abstraction for recipe images: `ImageCache`.
- One loader/fallback path used by all recipe image UI.
- One place to change recipe image loading behavior.
- Smaller and less error-prone `RecipeImageView.swift` with no duplicated loader blocks.

## Acceptance Criteria
1. `HeroRecipeImageView` and `RecipeImageView` no longer duplicate image-loading/cache/fallback logic.
2. Recipe image memory caching is routed through `ImageCache` only (no second private cache in `RecipeImageService`).
3. Existing recipe image behaviors still work:
   - local file load
   - remote URL load with retry
   - CloudKit fallback for missing local image
4. No UX regression in common screens:
   - Cook list cards/thumbnails
   - Recipe detail hero image
   - Import preview hero image

## Risks and Mitigations
- Risk: subtle UI flicker due to changed caching sequence.
  - Mitigation: preserve pre-seeded state from cache before async load; verify back-navigation behavior.
- Risk: fallback ordering regressions for shared vs own recipes.
  - Mitigation: keep existing `ownerId`-based database selection logic unchanged; add focused tests.
- Risk: hidden dependencies on current `RecipeImageService` internals.
  - Mitigation: keep API signatures stable where possible and migrate call sites incrementally.

## Implementation Plan
1. Introduce shared loader helper in `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Components/RecipeImageView.swift` used by both `RecipeImageView` and `HeroRecipeImageView`.
2. Refactor `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/RecipeImageService.swift` to delegate cache read/write to `ImageCache` (for recipe-id keyed paths) and remove private `NSCache` reliance.
3. Update `/Users/nadav/Desktop/Cauldron/Cauldron/Features/Library/RecipeEditorViewModel.swift` to use consolidated service behavior without duplicate cache orchestration where unnecessary.
4. Remove dead helper code and redundant comparison/loading branches in `RecipeImageView.swift`.
5. Run tests and smoke-check image-heavy flows.

## Validation and Test Steps
1. Build and run test suite (or focused tests if full suite is slow):
   - `xcodebuild -project Cauldron.xcodeproj -scheme Cauldron -destination 'platform=iOS Simulator,name=iPhone 16' test`
2. Manual validation:
   - Open cook list and scroll through recipe cards.
   - Open a recipe detail screen and verify hero image loading.
   - Import a recipe with image and confirm preview + post-save rendering.
   - Open a shared/friend recipe to verify CloudKit fallback still works.
3. Confirm no duplicate loader blocks remain in `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Components/RecipeImageView.swift`.

## Rollback Plan
1. Revert changes to:
   - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/RecipeImageService.swift`
   - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Components/RecipeImageView.swift`
   - `/Users/nadav/Desktop/Cauldron/Cauldron/Features/Library/RecipeEditorViewModel.swift`
2. Restore prior service cache behavior and per-view load logic.
3. Re-run smoke tests on Cook/Detail/Import image flows.

