# Consolidate Image Loading Into One Service

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document must be maintained in accordance with `/Users/nadav/Desktop/Cauldron/.agent/PLANS.md`.

## Purpose / Big Picture

Cauldron currently loads images through multiple overlapping services and ad-hoc code paths, which makes image behavior harder to reason about and increases the chance of regressions when changing caching, fallback, or CloudKit download behavior. After this change, every recipe/profile/collection image load will go through one service with one fallback policy. A developer will be able to change image loading behavior in one place and verify it with one focused test suite.

User-visible behavior stays the same: recipe cards, profile avatars, and collection covers still load local images immediately, then fall back to CloudKit when needed, and still avoid flicker with memory caching.

## Progress

- [x] (2026-02-10 06:09Z) Repo analysis completed, candidate refactors ranked, and this consolidation selected as highest value.
- [ ] Implement Milestone 1 (introduce unified image loading service interface and test seam).
- [ ] Implement Milestone 2 (migrate recipe/profile/collection call sites to unified service and remove duplicate startup preloading logic).
- [ ] Implement Milestone 3 (remove deprecated image loading service/file, run full validation, document outcomes).

## Surprises & Discoveries

- Observation: One screen uses two different image loading stacks at the same time (recipes via `RecipeImageService`, profiles via `EntityImageLoader`), increasing conceptual overhead.
  Evidence: `Cauldron/Features/Sharing/FriendsTabView.swift` uses both `ProfileAvatar` and `RecipeImageView`; `ProfileAvatar` calls `dependencies.entityImageLoader` while `RecipeImageView` calls `dependencies.recipeImageService`.
- Observation: Startup preloading duplicates profile image logic instead of reusing the existing loader service.
  Evidence: `Cauldron/ContentView.swift` contains a `withTaskGroup` block that does file reads and `profileImageManager.downloadImageFromCloud`, similar to `EntityImageLoader.preloadProfileImages`.
- Observation: Core image logic currently spans multiple files with similar responsibilities.
  Evidence: `Cauldron/Core/Services/RecipeImageService.swift`, `Cauldron/Core/Services/EntityImageLoader.swift`, plus direct cache/file logic in `Cauldron/ContentView.swift`.

## Decision Log

- Decision: Target image loading consolidation first instead of connection-flow or repository-structure consolidation.
  Rationale: Highest payoff in reducing duplicate abstractions and shotgun-surgery risk with moderate, bounded blast radius.
  Date/Author: 2026-02-10 / Codex
- Decision: Keep storage/sync actors (`RecipeImageManager`, `ProfileImageManagerV2`, `CollectionImageManagerV2`) and consolidate only load-orchestration paths.
  Rationale: Storage/sync actors are already the canonical write/read primitives; replacing them would increase risk without equivalent payoff.
  Date/Author: 2026-02-10 / Codex

## Outcomes & Retrospective

This plan is authored but not yet implemented. Expected outcome is one image loading orchestration service and deletion of duplicate load orchestration code paths.

## Context and Orientation

`/Users/nadav/Desktop/Cauldron/Cauldron/App/DependencyContainer.swift` currently injects several image-related dependencies:

- `imageManager` (recipe image local/cloud operations)
- `profileImageManager` (profile image local/cloud operations)
- `collectionImageManager` (collection image local/cloud operations)
- `recipeImageService` (recipe image loading/caching/fallback orchestration)
- `entityImageLoader` (profile/collection loading/caching/fallback orchestration)

The split between `recipeImageService` and `entityImageLoader` is the core duplication. Both perform local-file checks, memory-cache writes, and optional CloudKit fallback.

Key call paths today:

1. Recipe display path:
   `RecipeImageView` -> `RecipeImageService.loadImage(forRecipeId:localURL:ownerId:)` -> `RecipeImageManager.downloadImageFromCloud(...)`.
2. Profile avatar path:
   `ProfileAvatar` -> `EntityImageLoader.loadProfileImage(...)` -> `ProfileImageManagerV2.downloadImageFromCloud(...)`.
3. Collection cover path:
   `CollectionCardView` -> `EntityImageLoader.loadCollectionCoverImage(...)` -> `CollectionImageManagerV2.downloadImageFromCloud(...)`.
4. Startup preload path:
   `ContentView` executes its own profile image preloading task group using direct file reads and `profileImageManager.downloadImageFromCloud(...)`.

The target is to keep only one orchestration concept: a unified image loading service used by all three entity types.

## Plan of Work

### Milestone 1: Introduce unified image loading orchestration with test seam

Create a single orchestration service in `Cauldron/Core/Services/EntityImageLoader.swift` (or rename file/class to `ImageLoadingService.swift` if preferred during implementation, but keep one service concept). It must own recipe/profile/collection load logic and memory-cache interactions. This milestone keeps old call sites compiling by temporarily preserving compatibility methods.

Write tests first in a new file `CauldronTests/Services/ImageLoadingServiceTests.swift` for deterministic orchestration behavior:

- cache-first behavior for recipe/profile/collection keys,
- local-file fallback before CloudKit download,
- recipe CloudKit database order selection (private-first for own recipe, public-first for non-owned recipe),
- no duplicate downloads when a cached image exists.

Implement only enough production changes for these tests to pass.

### Milestone 2: Migrate all UI and preload call sites to unified service

Replace recipe image call sites that currently depend on `RecipeImageService` with the unified service. This includes `Cauldron/Core/Components/RecipeImageView.swift` and all views that currently inject `dependencies.recipeImageService`.

Replace the ad-hoc profile preloading block in `Cauldron/ContentView.swift` with a call to the unified service preloading API so startup path and screen path use identical logic.

Update `Cauldron/App/DependencyContainer.swift` to expose only the unified orchestration service entrypoint. Keep manager actors (`imageManager`, `profileImageManager`, `collectionImageManager`) intact.

### Milestone 3: Remove duplicate orchestration code and finalize validation

Delete `Cauldron/Core/Services/RecipeImageService.swift` and remove all references to `RecipeImageService` from the codebase. If temporary shims were added in Milestone 1, remove them now.

Run focused tests for the new unified service, then run the full existing test suite command used in this repo. Confirm no image-loading regressions in key flows (recipe cards, profile avatars, collection covers, startup preload).

## Concrete Steps

From `/Users/nadav/Desktop/Cauldron`:

1. Write failing tests for unified behavior:

    xcodebuild test -project Cauldron.xcodeproj -scheme Cauldron -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' -only-testing:CauldronTests/ImageLoadingServiceTests

   Expected before implementation: the new tests fail due to missing unified APIs or old behavior.

2. Implement Milestone 1 code changes in service layer and rerun the same focused tests.

3. Migrate call sites in Milestone 2 and run:

    xcodebuild test -project Cauldron.xcodeproj -scheme Cauldron -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' -only-testing:CauldronTests/ImageLoadingServiceTests

4. Verify duplicate service removal target:

    rg -n "RecipeImageService" Cauldron CauldronTests

   Expected at completion: no production references remain.

5. Run full regression suite:

    xcodebuild test -project Cauldron.xcodeproj -scheme Cauldron -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'

## Validation and Acceptance

Acceptance criteria are complete when all are true:

1. Only one orchestration service remains for image loading behavior (recipe/profile/collection), and `RecipeImageService` is removed from production code.
2. `DependencyContainer` no longer exposes overlapping orchestration dependencies for image loading.
3. Unified service tests exist and pass, covering cache-first and local->cloud fallback decisions.
4. Recipe images, profile avatars, and collection covers still render in their existing screens with no functional regression.
5. Startup preload still populates profile image cache and no longer duplicates image-loading logic inline in `ContentView`.

Milestone verification pattern:

1. Tests to write first:
   - `CauldronTests/Services/ImageLoadingServiceTests.swift`
   - `testLoadRecipeImage_UsesCacheBeforeDiskAndCloud`
   - `testLoadRecipeImage_ForOwnRecipe_UsesPrivateThenPublicFallback`
   - `testLoadRecipeImage_ForSharedRecipe_UsesPublicThenPrivateFallback`
   - `testPreloadProfileImages_RespectsForceRefreshAndCache`
2. Implementation:
   - Consolidate service API and migrate call sites.
3. Verification:
   - Run focused tests and then full suite.
4. Commit:
   - Milestone 1 commit: "Milestone 1: Add unified image loading service seam and tests"
   - Milestone 2 commit: "Milestone 2: Migrate image loading call sites to unified service"
   - Milestone 3 commit: "Milestone 3: Remove RecipeImageService and finalize validation"

## Idempotence and Recovery

The migration is safe to re-run because each milestone is additive-first:

- Milestone 1 introduces unified APIs while existing call sites can remain temporarily.
- Milestone 2 moves call sites incrementally; if one path fails, revert only that path to the previous service until tests pass.
- Milestone 3 performs subtraction only after passing tests and call-site search confirms no remaining dependency.

Recovery path:

- If regression appears after migration, temporarily reintroduce the previous call path in the affected screen while keeping unified service tests in place, then fix forward.
- Keep service-level tests as the rollback guardrail; do not proceed to deletion until all targeted tests pass.

## Artifacts and Notes

Reference evidence collected during planning:

    rg -n "class RecipeImageService|func loadImage\\(forRecipeId" Cauldron/Core/Services/RecipeImageService.swift
    rg -n "final class EntityImageLoader|func loadProfileImage|func loadCollectionCoverImage" Cauldron/Core/Services/EntityImageLoader.swift
    rg -n "withTaskGroup|profileImageManager.downloadImageFromCloud|Data\\(contentsOf: imageURL\\)" Cauldron/ContentView.swift

Hotspot snapshot (dependency usage occurrences in production code):

    recipeRepository: 69
    connectionManager: 29
    userCloudService: 26
    imageManager: 16
    recipeImageService: 14
    profileImageManager: 14

## Interfaces and Dependencies

At completion, production code must expose one orchestration interface for image loading behavior. Storage/sync actors remain:

- `RecipeImageManager` for recipe file/cloud operations,
- `ProfileImageManagerV2` for profile file/cloud operations,
- `CollectionImageManagerV2` for collection file/cloud operations.

Unified orchestration service API (names may vary slightly, behavior must match):

    @MainActor
    final class ImageLoadingService {
        func loadRecipeImage(recipeId: UUID, localURL: URL?, ownerId: UUID?) async -> Result<UIImage, ImageLoadError>
        func loadProfileImage(for user: User) async -> ProfileImageResult
        func loadCollectionCoverImage(for collection: Collection) async -> UIImage?
        func preloadProfileImages(users: [User], forceRefresh: Bool) async
        func preloadSharedRecipeAndProfileImages(sharedRecipes: [SharedRecipe]) async
    }

`DependencyContainer` should provide only this orchestration dependency to views/view-models that need image loading behavior.

Plan revision note: Initial version created on 2026-02-10 to capture the selected consolidation refactor and implementation milestones.
