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
- Read-only, real-production-data homepage preview (requires authorized `gcloud`; detail links open production):
  - `cd firebase/functions && npm run preview:live`
- Refresh the derived catalog sitemap manifest before first deployment or after an indexing repair (explicit production write; requires authorized `gcloud`):
  - `cd firebase/functions && npm run build && node tools/refreshSitemap.mjs --apply`
- Read-only public-user/index eligibility audit (aggregate counts only; requires authorized `gcloud`):
  - `cd firebase/functions && npm run build && node tools/auditPublicIndex.mjs`
- Read-only HTTP timing and SEO smoke audit (not field Core Web Vitals):
  - `cd firebase/functions && node tools/auditHostedWeb.mjs`
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
  - `User.avatarRepresentation` is the canonical photo/emoji/initials decision for native profile UI. An explicit legacy emoji suppresses conflicting stale photo metadata, and photo caches are revision-keyed; do not reintroduce user-ID-only avatar rendering or loading.
  - Invite links/referrals, friend connections, and profile/friends UX should remain reliable and low-friction.
  - Saving someone else's recipe should preserve attribution while creating a synced, profile-visible user-owned copy that follows source updates until the saver edits it.
  - Saving someone else's collection should create a user-owned copy, save visible recipes through `RecipeSaveService`, persist membership through `CollectionRepository`, and preserve source metadata to prevent duplicate saved collections.
  - CloudKit + Firebase share-link behavior must remain compatible with app routing. Canonical pages use `cauldronrecipes.com`; the legacy `cauldron-f900a.web.app` and cross-domain `cauldron-f900a.firebaseapp.com` aliases must remain in Associated Domains/AASA. Keep the backward-compatible custom-scheme button until a containing app build with the custom-domain entitlement has shipped broadly.
  - Public recipe, profile, and collection links are managed by Firebase summary snapshots and a private, iCloud-synchronized Keychain capability. Full recipe web pages hydrate current public image, ingredient, method, and canonical creator identity/avatar data from CloudKit after validating the Firebase publication pointer; rich recipe content is not duplicated in Firebase. The capability hash is registered on the creator-write-protected public CloudKit `User` record and verified by versioned Firebase mutation functions. Creator-protected `UsernameClaim` records provide global profile-alias uniqueness. Historical claims remain reserved while an account exists so renamed `/u/{username}` links can redirect safely; account deletion releases every claim. Server mutation generations prevent stale publishes from racing privacy removals. Publish failures must retry, and privacy/deletion flows must remove Firebase snapshots before deleting CloudKit identity/content records.
  - Firebase is a replaceable public index, not the content authority. After authoritative sync, the app submits an exact owner manifest so Firebase can upsert missing summaries and delete stale owner rows with generation, privacy, revocation, and document-revision guards. Web profile, collection, and home shelves batch-validate recipe identity, owner, and visibility in CloudKit before rendering; the homepage mixes up to 24 recent summaries with an age-independent daily document-ID ring sample of up to 36 summaries, validates up to 24 candidates, and displays up to 12 recipes with creator/category diversity. It omits cards without current validated CloudKit images; the hosted monitor fails on an empty shelf and probes up to three displayed images and recipe destinations. Collection pages resolve authoritative `CollectionMembership` edges and use legacy `recipeIds` only when no edges exist. Missing profiles may materialize lazily from canonical `UsernameClaim` and `User` records, while scheduled profile/recipe backfill must never resurrect revoked/private identities or block a public page request.
  - Recipe share links use canonical `/recipe/{id}` URLs. A successful, periodically refreshed publication receipt lets an unchanged Firebase summary share immediately; CloudKit-only recipe edits do not republish that summary, while title/time/tag changes still wait for server confirmation. Open Graph artwork uses the stable same-origin `/recipe/{id}/social-card.png` proxy with the branded static card as its fallback, never a signed CloudKit asset URL.
  - Recipe structured data uses the stable image proxy. `/recipes`, profiles and collections use bounded 24-candidate cursor pages with self-referencing canonical URLs. `/sitemap.xml` is a catalog sitemap index backed by a six-hourly atomic ID-only manifest; each leaf revalidates up to 24 recipes against current publication/privacy/CloudKit data and returns 503 on incomplete validation. Global browse uses that manifest only to select candidates, with the same live validation; profiles remain live queries. New global catalog entries can take six hours to appear. Missing/expired manifests fall back to bounded live catalog scanning. Bootstrap the manifest with `tools/refreshSitemap.mjs --apply` before deploying the new sitemap handler. The manifest expires after 24 hours and fails loudly above 10,000 indexed rows rather than silently truncating; expand/shard it before that limit. Legacy users without a creator-owned `UsernameClaim` must open a migration-capable app once before public backfill can include them; the server must not manufacture owner-protected claims.
  - Responsive recipe photos use `/recipe/{id}/image/{320|640|1280}.webp`. Each request revalidates public ownership/visibility before reading the revision-keyed 16 MB, ten-minute process-local byte cache. There is no persistent image-copy bucket or CDN authorization cache. Downloads are capped at 10 MB, decoded images at 16 megapixels, and image traffic has an independent 360/minute client budget. Keep page/API limits separate and preserve no-store on personal image responses, including social artwork.
  - CloudKit paginated web queries must retain the original query and filters alongside `continuationMarker`; use `cloudKitQueryPageRequest` for profile backfill, owner recipes, and collection membership pages.
  - `cauldronrecipes.com` is DNS-managed at Vercel and attached to the existing Firebase Hosting site. Preserve its Firebase ownership and certificate-validation DNS records when changing domain infrastructure.
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
- Public-repository CI pins actions to full commit SHAs. Keep the Gitleaks
  checksum pinned when updating its version, and never broaden its two exact
  historical false-positive exclusions. CodeQL covers JavaScript/TypeScript,
  not the native Swift targets. Dependabot changes require review and tests;
  they must not automatically deploy production. Private operational/QA reports
  stay untracked under `.agent/`; reusable instructions remain committed.
- CI uses GitHub's dedicated `xcode-27` preview runner and
  `tools/ci/verify_xcode_27.sh` fails if its Xcode or iPhoneOS SDK major drifts.
  PR/push checks warn when the preview build rotates; manually dispatched
  release verification requires the exact Xcode build supplied in its input.
- Xcode Cloud runs `tools/ci/verify_release_configuration.sh` from
  `ci_scripts/ci_post_clone.sh`; GitHub's iOS readiness job runs the same check
  for archive UTIs, signing entitlements, hosted domains, and Catalyst sandbox access.
- Xcode Cloud's `PR Checks` and manual `App Store Release (Xcode 26.6)`
  workflows are pinned to Xcode 26.6 (`17F113`) on macOS 26.6.2. The release
  workflow creates an App Store-eligible iOS archive from `main`; increment the
  build number before running it. Do not switch either workflow to `Latest Beta
  or Release` while App Store Connect rejects iOS 27 SDK binaries.
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
