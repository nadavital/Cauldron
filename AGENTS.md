# AGENTS.md

Guidance for coding agents working in this repository.

## Project Snapshot
- App: `Cauldron` (SwiftUI-first recipe app)
- Main targets: iOS/iPad app, Mac Catalyst app, Widget extension, Share extension
- Core backend: CloudKit (+ Firebase for share-link hosting endpoints)
- Parser stack: model-backed import pipeline with parity-tested assembly
- Intelligence routing: deterministic parsing plus Apple on-device Foundation Models and availability-gated Private Cloud Compute

## Repository Layout
- App code: `/Users/nadav/Desktop/Cauldron/Cauldron`
- Tests: `/Users/nadav/Desktop/Cauldron/CauldronTests`
- Share extension: `/Users/nadav/Desktop/Cauldron/CauldronShareExtension`
- Widget: `/Users/nadav/Desktop/Cauldron/CauldronWidget`
- Parser tooling/labs: `/Users/nadav/Desktop/Cauldron/tools`

## Build And Test Commands
- iOS build:
  - `xcodebuild build -scheme Cauldron -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO`
- Mac Catalyst build:
  - `xcodebuild build -scheme Cauldron -destination 'platform=macOS,variant=Mac Catalyst,name=My Mac' -configuration Debug CODE_SIGNING_ALLOWED=NO`
- iOS tests:
  - `xcodebuild test -scheme Cauldron -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO`
- Mac Catalyst tests:
  - `xcodebuild test -scheme Cauldron -destination 'platform=macOS,variant=Mac Catalyst,name=My Mac' -configuration Debug CODE_SIGNING_ALLOWED=NO`
- Firebase functions and Firestore rules tests (Node 22 + Java 21):
  - `cd firebase/functions && npm ci && npm test`
- Firebase production dependency audit:
  - `cd firebase/functions && npm run audit:production`
- Hosted public sharing contract:
  - `cd firebase/functions && npm run monitor:hosted`
- Simulator QA mode:
  - Launch Debug builds with `--cauldron-simulator-qa` or `CAULDRON_SIMULATOR_QA=1` to use in-memory social/import/offline mock data and suppress CloudKit startup sync for repeatable visual smoke checks.
  - Add `--cauldron-desktop-workspace` to preview the iPhone/iPad-on-Mac single-workspace layout in an iPad simulator.

## Current Product Priorities
- Maintain first-class iPad and Mac experiences (not only iPhone layouts)
- Preserve parser quality and import consistency across share sheet, URL, and text flows
- Keep social/invite flows stable and performant
- Favor practical incremental changes over broad refactors unless requested

## Critical Features And Behaviors
- Import quality is core product value:
  - Model-backed parser + shared import pipeline should stay consistent across URL, text, and share-extension entry points.
  - Parser behavior changes should keep parity/regression tests green.
  - Share-extension handoffs must be persisted into `RecipeImportInboxStore` before the cross-process transport item is acknowledged; dismissal is not completion.
- Social sharing is a core workflow:
  - Invite links/referrals, friend connections, and profile/friends UX should remain reliable and low-friction.
  - Saving someone else's recipe should preserve attribution while creating a synced, profile-visible user-owned copy that follows source updates until the saver edits it.
  - Saving someone else's collection should create a user-owned copy, save visible recipes through `RecipeSaveService`, persist membership through `CollectionRepository`, and preserve source metadata to prevent duplicate saved collections.
  - CloudKit + Firebase share-link behavior must remain compatible with app routing. Canonical pages use `cauldron-f900a.web.app`; the cross-domain `cauldron-f900a.firebaseapp.com` alias must remain in Associated Domains/AASA but cannot replace the backward-compatible custom-scheme button until a containing app build has shipped broadly.
  - Public recipe, profile, and collection links are managed by Firebase summary snapshots and a private, iCloud-synchronized Keychain capability. Full recipe web pages hydrate current public image, ingredient, method, and canonical creator identity/avatar data from CloudKit after validating the Firebase publication pointer; rich recipe content is not duplicated in Firebase. The capability hash is registered on the creator-write-protected public CloudKit `User` record and verified by versioned Firebase mutation functions. Creator-protected `UsernameClaim` records provide global profile-alias uniqueness, and server mutation generations prevent stale publishes from racing privacy removals. Publish failures must retry, and privacy/deletion flows must remove Firebase snapshots before deleting CloudKit identity/content records.
- Large-screen experience is intentional:
  - iPad layouts are first-class, not stretched iPhone views.
  - Mac app behavior is intentionally supported via Mac Catalyst target configuration.
- Offline-first sync reliability matters:
  - `CauldronPersistenceSchema` is the single source of truth for the shipping SwiftData model set; full-container tests and recovery probes must use it rather than duplicating the schema.
  - Portable library restores are idempotent newest-wins merges: stable IDs are retained unless a foreign-owner or deletion-history collision requires deterministic remapping, ownership is rebound to the signed-in account, CloudKit record metadata is cleared, and absent destination recipes are not restored as collection memberships.
  - Operation queue + CloudKit sync paths should not be bypassed without a clear migration plan.
  - Deleted recipes are represented by durable private CloudKit `DeletedRecipe` tombstones; deletion wins over stale active recipe records.
  - Collection membership correctness is represented by CloudKit `CollectionMembership` edge records; legacy collection `recipeIds` is a compatibility cache.
  - A durable collection mutation may rebind to a new canonical Cauldron user ID only when its persisted stable CloudKit identity exactly matches the verified current account; the creator-bound legacy collection graph is retired before canonical replay, and different identities remain deferred.
  - If the local SwiftData store cannot open, preserve it and its sidecars under `Cauldron Store Backups` before creating a clean store. Keep the committed 1.5 store fixture opening in current-schema tests.
- Cook Mode state shared with Live Activities and App Intents is persisted through `CookSessionSharedStore`; app and widget navigation must use the shared reducer rather than independent defaults mutations.
- Update-surface behavior matters:
  - `What's New` is gated by content version and should be updated for meaningful user-visible changes.

## Release/Update Checklist
- CI uses GitHub's dedicated `xcode-27` preview runner and
  `tools/ci/verify_xcode_27.sh` fails if its Xcode or iPhoneOS SDK major drifts.
  PR/push checks warn when the preview build rotates; manually dispatched
  release verification requires the exact Xcode build supplied in its input.
- The scheduled hosted-sharing monitor is public/read-only and fails closed.
  Keep its profile, recipe, and Bakery collection fixtures published; override
  the corresponding repository variable before intentionally retiring one.
- App versioning is managed in:
  - `/Users/nadav/Desktop/Cauldron/Cauldron.xcodeproj/project.pbxproj`
  - `MARKETING_VERSION` should be updated consistently across targets.
- "What’s New" screen:
  - UI content: `/Users/nadav/Desktop/Cauldron/Cauldron/Features/Settings/WhatsNewView.swift`
  - show-once content gate: `/Users/nadav/Desktop/Cauldron/Cauldron/ContentView.swift` (`whatsNewContentVersion`)
- If update text changes materially, bump `whatsNewContentVersion` so existing users see it.

## Platform Notes
- Mac app path is Mac Catalyst-enabled in the main target.
- Embedded iOS extensions and their target dependencies are filtered for iOS-only builds in project settings.
- ActivityKit/Live Activities are conditionally excluded from Mac Catalyst code paths.

## Working Norms
- Keep SwiftUI code idiomatic and readable; prefer focused edits over wide churn.
- When touching parser or import flows, run relevant parser/import tests before finalizing.
- Avoid modifying unrelated files in a dirty worktree.
- Do not remove existing product behavior unless explicitly requested.

## AGENTS.md Maintenance Rules
- Update this file in the same PR whenever any of the following changes:
  - Build/test commands, destinations, scheme names, or required flags
  - App targets/platform support (iOS/iPad/Mac Catalyst/extension behavior)
  - Core architecture boundaries (new layer, service ownership shift, major DI changes)
  - Critical feature workflows (import/parser pipeline, sharing/invites, sync model)
  - Release/update process (`MARKETING_VERSION`, `What's New` gating, rollout steps)
- Keep updates minimal and factual; prefer editing existing sections over adding noisy new ones.
- If a change is temporary, annotate it as temporary and include expected cleanup timing.
