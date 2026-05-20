# App-Wide Bug Audit - May 20, 2026

## Purpose

This is the working ledger for large verified or strongly suspected bugs found after the recipe ownership/save-reference hardening checkpoint:

- Checkpoint commit: `d2796a7 Harden recipe ownership and save references`
- Scope: unrelated app-wide correctness, data integrity, sync, social, UI state, import/parser, and test/runtime risks
- Status: audit ledger plus implementation progress

## Severity Guide

- P0: active data leak or destructive data loss likely in normal use
- P1: major correctness/data integrity bug, likely to affect real users or core workflows
- P2: important bug with narrower trigger, stale data, bad recovery, or misleading UI
- P3: correctness gap worth fixing, but lower blast radius

## Implementation Progress

Verified by Mac Catalyst build unless noted:

- Fixed session-scoped app data reset across sign-out/account change.
- Fixed `ConnectionManager`, friends tab view model, and sharing-service cache scoping by current user.
- Fixed account deletion cleanup so queued destructive recipe/profile work is not silently dropped by user switching.
- Fixed CloudKit recipe record mapping for source URL/title, nutrition, favorite state, preview/copy fields, and private image record-name handling.
- Fixed accepted-friend duplicate cleanup so accepted connections win over newer pending duplicates.
- Fixed share-extension handoff durability and text-vs-URL routing for recipe-like plain text containing source links.
- Fixed collection delete tombstones, membership removal edges, remote tombstone suppression, and local collection detail dismissal.
- Fixed open recipe detail/editor stale-delete resurrection.
- Fixed operation queue persistence decode recovery and dead-lettering.
- Fixed editor image preservation when saving before async image load completes.
- Fixed Cook tab create/edit sheet state so Create cannot reopen a previously selected recipe.
- Fixed favorite toggle optimistic row updates so ownership, copy, preview, and CloudKit metadata are preserved.
- Fixed external shared-link routing so loaded content is deferred until `MainTabView` is mounted; SceneDelegate now also stores pending external share URLs.
- Fixed share-extension URL/text preview saves so they post `RecipeAdded` and refresh Cook tab like other import paths.
- Fixed AI generation completion so invalid final streams fail cleanly and canceled old tasks cannot reset newer generations.
- Fixed recipe search stale-result overwrites with a generation token after every async boundary.
- Fixed all `Dictionary(uniqueKeysWithValues:)` call sites to use explicit duplicate merge policies.
- Fixed profile CloudKit saves so nil avatar fields clear stale emoji/photo metadata.
- Fixed onboarding photo save/upload order so the selected image is stored under the final user ID.
- Fixed collection cover image CloudKit decode so cover record name and modified date round-trip.
- Fixed owner collection fetch missing-schema fallback to match other collection CloudKit reads.
- Fixed friends feed duplicate lineages by deduplicating shared feed recipes by source lineage.
- Fixed public search/discovery fetch limiting so selected groups keep their saver copies for search context.
- Fixed shared/owner collection CloudKit fetches so membership edge records overlay legacy `recipeIds` when available.
- Verified root detached startup/background tasks are session-checked in the current implementation.
- Fixed cloud image migration completion so failures do not set the completed flag, public uploads are not swallowed, and retries can repair public images for recipes that already have private metadata.
- Fixed profile recipe/tier counts so other-user profile stats use the CloudKit public count query instead of the capped display page; raised profile display fetch limit to 500.

Current verification:
- `git diff --check` passed after each batch.
- `xcodebuild build -scheme Cauldron -destination 'platform=macOS,variant=Mac Catalyst,name=My Mac' -configuration Debug CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/CauldronDerivedData` passed after the latest batch.
- Targeted Mac Catalyst tests are blocked locally: `My Mac` is macOS 26.2 while `CauldronTests` has a macOS 26.5 deployment target.

Known remaining audit work:
- Parser parity internals, iPad/Mac visual QA, and production-like persistent-store smoke tests remain audit gaps.

## Verified Issues

The first wave of findings was verified by a second-pass reviewer. The corrections were scope-related:

- The own-collection missing-schema issue is real but narrow.
- The duplicate `Dictionary(uniqueKeysWithValues:)` issue is real, but some call sites are more exposed than others.
- The production-like QA/test gap is a quality gate rather than a direct product bug.

### P1 - Cross-account root preload data can leak after sign-out or account deletion

Evidence:
- `ContentView` keeps `isDataReady` and `preloadedData` as root state.
- Startup load is driven by an unkeyed `.task`.
- `MainTabView` receives whatever preloaded arrays remain in memory.
- `CurrentUserSession.signOut()` clears session/onboarding state but does not reset root preload state.
- `CookTabViewModel` can initialize from stale preloaded arrays.

Failure mode:
After sign-out/account deletion and new onboarding, the new user can briefly or persistently see the previous user's library data.

Likely fix:
Make app-shell data session-scoped. Clear preload state on sign-out/onboarding and reload with `.task(id: userSession.userId)`. Consider `.id(userSession.userId)` around the main shell so view model state is recreated per account.

### P1 - ConnectionManager state is not scoped to the signed-in user

Evidence:
- `ConnectionManager` has one in-memory `connections` dictionary and one `lastSyncTime`.
- `loadConnections(forUserId:)` can return early for 30 minutes if the dictionary is non-empty.

Failure mode:
A new user can inherit the previous user's in-memory connections, badges, and friend rows.

Likely fix:
Track `loadedUserId`; clear `connections` and `lastSyncTime` when the requested user changes. Reset the manager on sign-out.

### P1 - Friends tab shared content singleton can leak across users

Evidence:
- `FriendsTabViewModel.shared` owns shared recipes, shared collections, tiers, and `hasLoadedOnce`.
- `FriendsTabView` uses an unkeyed `.task`.
- First-load cache behavior is not tied to a user id.
- `SharingService` also has an unkeyed in-memory shared-recipes cache, so fixing only `FriendsTabViewModel.shared` would not fully solve stale friends-feed data after account switch.

Failure mode:
A different account can see the prior account's friends' recipes or shared collections.

Likely fix:
Remove the singleton or key/reset it by current user id. Clear arrays and force refresh on session changes.

### P1 - CloudKit recipe round-trips drop user data

Evidence:
- `RecipeCloudService.populateRecipeRecord` does not persist `sourceURL`, `sourceTitle`, `nutrition`, or `isFavorite`.
- `recipeFromRecord` hardcodes `nutrition: nil`, `sourceURL: nil`, `sourceTitle: nil`, and `isFavorite: false`.
- Existing record mapping tests create these values but do not assert round-trip preservation.

Failure mode:
After CloudKit sync, reinstall, or another-device restore, imported attribution disappears, nutrition disappears, and favorites reset.

Likely fix:
Add backward-compatible CloudKit fields for `sourceURL`, `sourceTitle`, encoded `nutrition`, and `isFavorite`. Extend record mapping tests to assert the full round trip.

### P1 - Image retry state is shared between private and public uploads

Evidence:
- Pending image upload state is keyed only by `recipe.id`.
- Private upload can fail and mark the recipe pending, then public upload can succeed and clear the same pending bit.
- Retry uploads private then public while both mutate the same pending set.

Failure mode:
A public recipe image can exist in the public DB while private backup never retries, so reinstall/new device loses the owner image. The reverse can also leave the public asset missing.

Likely fix:
Track pending image uploads per target database, for example `(recipeId, database)`. Clear only the matching target after success. Prefer returning success/failure from upload calls and completing queue state only after all required targets finish.

### P1 - Cloud image migration marks complete despite per-image failures

Evidence:
- `CloudImageMigration` counts failures but swallows them.
- It sets `.completed` and persists `imageMigrationCompleted_v2` unconditionally.
- Public upload failures are ignored with `try?`.

Failure mode:
One transient CloudKit error during legacy image migration leaves that recipe with only a local image and no durable cloud backup. Automatic migration never retries.

Likely fix:
Only mark migration complete when all required uploads succeed. Persist remaining recipe IDs or enqueue per-database pending image uploads for retry.

### P1 - Private image asset operations ignore `cloudRecordName`

Evidence:
- Recipe metadata sync uses `recipe.cloudRecordName` when present.
- Decoding preserves the actual CloudKit record name.
- Private image upload/download/delete build the record ID from `recipe.id.uuidString`.

Failure mode:
A legacy private recipe whose record name is not the recipe UUID can sync metadata but fail image upload/download/delete.

Likely fix:
Make private image asset APIs accept the private recipe record name or resolve by `cloudRecordName`. Keep public DB keyed by recipe id.

### P1 - Collection deletes lack durable tombstones or missing-remote reconciliation

Evidence:
- Collection delete removes the local row and queues/deletes the public record.
- Sync fetches cloud collections and upserts newer/missing records, but does not remove local collections missing remotely.
- Membership edges are fetched independently and are not tombstoned/deleted with the collection.

Failure mode:
Device A deletes a collection. Device B syncs later, keeps its local collection forever, and a later local update can resurrect the deleted collection and stale membership.

Likely fix:
Add collection deletion tombstones or a server-side deleted marker. Sync deleted facts before merge, remove suppressed local collections, and mark/delete membership edges as part of collection deletion.

### P1 - Shared collection membership can be stale for non-owners

Evidence:
- Public/shared collection CloudKit fetch decodes only the legacy `recipeIds` blob.
- Shared collection detail, preview, and save paths load recipes from `collection.recipeIds`.
- The durable membership model is `CollectionMembership` edge records, but shared/profile surfaces do not overlay them.

Failure mode:
If another device has correct membership edge records but stale `recipeIds`, shared cards, detail, hidden counts, and "save collection" copy the wrong membership.

Likely fix:
Add CloudKit reads for membership edges by collection IDs/owner IDs on shared/profile fetches. Overlay active edges using the same local membership logic. Treat `recipeIds` as fallback/cache.

### P1 - Friend duplicate cleanup can downgrade accepted friendships

Evidence:
- Duplicate cleanup groups by unordered user pair.
- It keeps the most recently updated connection and deletes the rest.

Failure mode:
If an older accepted connection and a newer pending duplicate exist, cleanup keeps pending and deletes accepted, making friends look unconnected/pending again.

Likely fix:
Choose canonical connection by status priority first (`accepted` over `pending`), then timestamp. Avoid deleting accepted records unless the kept record is accepted. Add regression tests for accepted+pending duplicates in both directions.

### P1 - Share-extension imports are destructively consumed before durable save

Evidence:
- `ShareExtensionImportStore.consumePreparedRecipe` removes prepared payloads, URLs, and text during consumption.
- `MainTabView` consumes prepared recipes/text/URLs before reparsing, presenting, or saving them durably.

Failure mode:
If the app is killed, crashes, the user is unauthenticated, or save/image download fails after consumption but before a local recipe is created, the share-extension handoff is gone. For text/URL flows, opening the importer moves payloads from App Group storage into transient view state.

Likely fix:
Make share-extension handoff an explicit queue with status. Delete/acknowledge only after successful local create, explicit user discard, or expiry.

### P1 - Shared recipe text containing any URL is forced down URL import path

Evidence:
- The share extension tries URL extraction first.
- URL extraction also scans `UTType.plainText` and extracts the first URL.
- Only if no URL is found does it treat the payload as text.
- Save persists only the URL path when a URL exists.

Failure mode:
Sharing copied recipe text that includes a source link, blog URL, or social URL loses the actual ingredient/instruction text and later imports only the first URL, or fails entirely.

Likely fix:
Distinguish explicit URL attachments from plain-text recipe bodies. If plain text is recipe-like or has substantial non-URL content, persist text, or persist both text and source URL with text taking precedence.

### P1 - Open recipe detail can resurrect a recipe deleted by sync or another device

Evidence:
- Remote tombstone sync removes the local recipe and posts `RecipeDeleted`.
- `RecipeDetailView` only reacts to `RecipeDeleted` for non-owned recipes.
- `RecipeEditorViewModel.save()` treats a missing persisted recipe as a new create.

Failure mode:
A remote tombstone/delete can be undone from stale UI by editing and saving from an already-open detail screen.

Likely fix:
When a `RecipeDeleted` notification matches the open recipe id, dismiss or mark unavailable regardless of ownership. Block edit/save when an existing recipe cannot be found in persistence.

### P1 - Queued recipe deletes from account deletion can be dropped after sign-out or user switch

Evidence:
- Operation queue persistence is global, not user-scoped.
- Account deletion deletes local recipes through optimistic `delete(id:)`.
- Recipe delete queues payloads with the old owner id, then performs CloudKit work in a detached task.
- Replay later requires `payload.ownerId == currentUserId`; otherwise it marks the delete completed and drops it.

Failure mode:
If account deletion removes local recipes, then the app is killed/offline or a different account signs in before replay, the old account's queued remote recipe deletes/tombstones can be silently completed without touching CloudKit. Public/private recipe records can remain after "delete account."

Likely fix:
Make queued operations owner/session-scoped. For destructive replay, use the payload's owner identity or run account-deletion deletes synchronously before sign-out. Do not complete cross-user delete payloads without executing or dead-lettering them.

### P1 - Account deletion only deletes one user profile record shape

Evidence:
- User profile fetch supports both custom `user_<systemRecordName>` and legacy system record IDs.
- Delete ignores the passed `userId` for locating profile records and deletes only `user_<currentSystemRecordName>`.

Failure mode:
A migrated/legacy account can leave a public `User` record behind after account deletion. Duplicate user records for the same `userId` may only be partially removed.

Likely fix:
Delete all profile records matching `userId`, plus both known record-name forms. Treat explicit `userId` as the deletion target and batch-delete matching public profile/image/referral artifacts.

### P1 - Queue persistence can discard the entire sync queue on one decode failure

Evidence:
- Queue state is stored as one encoded `[UUID: SyncOperation]`.
- Load uses `try? JSONDecoder().decode(...)` and treats any failure as no queue.

Failure mode:
A single incompatible enum/raw-value change, corrupt blob, or future schema change can drop all pending creates/updates/deletes, including destructive CloudKit cleanup.

Likely fix:
Use a versioned queue envelope and decode operations individually. Preserve valid operations, dead-letter invalid ones with diagnostics, and never treat decode failure as "no persisted operations."

## P2 Issues

### P2 - Editing can accidentally remove an existing recipe image

Evidence:
- Existing image loads asynchronously in `RecipeEditorViewModel`.
- `save()` treats `existingRecipe.imageURL != nil && selectedImage == nil` as image removal.
- There is already state for explicit user image changes.

Failure mode:
Open an image-backed recipe and tap Save before the image load task sets `selectedImage`; save clears the image URL/cache.

Likely fix:
Only delete image after an explicit remove action. Preserve `existingRecipe.imageURL` while image load is pending or when the image state was not user-modified.

### P2 - Cook tab "Create" can reopen a previously selected recipe

Evidence:
- `CookTabView` stores `selectedRecipe`.
- Context menu edit and cook-session conflict set it.
- The editor sheet always passes `selectedRecipe`.
- Create paths set only `showingEditor = true` and do not clear `selectedRecipe`.

Failure mode:
After editing or conflict-opening recipe A, tapping Create can open recipe A in edit mode instead of a blank recipe.

Likely fix:
Clear `selectedRecipe = nil` before every create-manual path, or model the sheet state as an enum: create vs edit(recipe).

### P2 - Favorite toggles in list views strip recipe metadata from navigation state

Evidence:
- List views rebuild `Recipe` manually after favorite toggles.
- The rebuild omits visibility, owner, cloud image/record names, source-copy fields, related IDs, and preview status.
- The omitted initializer defaults include public visibility and nil owner/cloud metadata.

Failure mode:
Rows look updated, but tapping them can open detail with metadata-stripped recipe state, making ownership checks, edit/share availability, preview-save behavior, and source-following state wrong until refresh.

Likely fix:
Refetch after toggling or add a preserving `withFavorite(_:)` helper that copies every field.

### P2 - Collection detail stays alive after deleting that collection from edit sheet

Evidence:
- Collection detail presents edit form as a sheet and refreshes on dismissal.
- The edit form can delete and dismiss.
- `CollectionRepository.delete` does not post a deletion notification.
- When detail reloads and fetch returns nil, stale collection state remains interactive.

Failure mode:
Deleting a collection from its own detail leaves the deleted collection screen visible and interactive.

Likely fix:
Add a collection-deleted notification or dismiss callback. Make detail show unavailable/dismiss when `fetch(id:)` returns nil.

### P2 - Deep links can be dropped behind onboarding or iCloud sign-in

Evidence:
- URL handlers post `.openExternalShare`.
- `ContentView` consumes the pending URL and posts `.navigateToSharedContent`.
- `MainTabView` is the only listener.

Failure mode:
If the user is still in onboarding or iCloud prompt, `MainTabView` is absent and the consumed link is lost.

Likely fix:
Hoist pending navigation state into `ContentView` and deliver it after the main shell mounts, or pass an initial route into `MainTabView`.

Second-pass correction:
`SceneDelegate` also posts external share URLs without storing them in `PendingShareManager`, so cold-start timing can drop before `ContentView` observes. Include that path in the fix.

### P2 - Root background tasks are detached and not session-checked

Evidence:
- Startup launches public recipe migrations, background sync, and social/profile warmup via `Task.detached`.
- These tasks capture old `userId`/dependencies.

Failure mode:
Tasks can keep writing repositories or caches after sign-out/account deletion.

Likely fix:
Store tasks, cancel them on session changes, and re-check `CurrentUserSession.shared.userId == capturedUserId` before mutating app-visible state.

### P2 - Share-extension URL/text preview saves do not refresh Cook tab

Evidence:
- Main share handoff sheet presents `ImporterView` without an `onDismiss` refresh.
- `RecipeImportPreviewView` creates the recipe and dismisses without posting `.recipeAdded`.
- Normal Cook-tab importer does refresh/post notifications.

Failure mode:
A recipe saved from share-extension URL/text preview can exist in the repository but not appear in the current Cook tab until another refresh path runs.

Likely fix:
Post `.recipeAdded` after preview save or add an `onDismiss` refresh path matching the Cook-tab importer.

### P2 - AI recipe generation can leave UI permanently generating

Evidence:
- AI generation sets `isGenerating = true`.
- Completion resets it only inside the branch where a final partial converts to a full recipe.
- Conversion returns nil when title, ingredients, or steps are missing.

Failure mode:
A model stream that ends without all required fields leaves no generated recipe, no error, and `isGenerating` stuck true.

Likely fix:
Use `defer` to clear `isGenerating`. Explicitly handle invalid final partial with failed progress and user-facing error.

### P2 - Search results can be overwritten by a canceled older query

Evidence:
- Search checks cancellation before setting public recipes.
- It then awaits owner-tier fetch.
- After that await, it schedules result rebuilding without another cancellation or query relevance check.

Failure mode:
Fast typing/category changes can show stale recipe results from a previous query.

Likely fix:
Use a generation token or compare current query/categories after every await before mutating results or loading state.

### P2 - Own-collection CloudKit fetch does not tolerate missing schema

Evidence:
- `fetchCollections(forUserId:)` throws any CloudKit error.
- Nearby collection paths treat `unknownItem` / schema-not-ready as empty.
- Full sync reaches collection sync after recipe sync.

Failure mode:
Fresh or partially deployed CloudKit collection schema can fail full sync even though recipes/tombstones could proceed.

Likely fix:
Apply schema-missing fallback to owner collection fetch, or isolate collection sync failure from recipe sync health.

### P2 - Duplicate synced data can crash `Dictionary(uniqueKeysWithValues:)` call sites

Evidence:
Potentially duplicate data is converted with `Dictionary(uniqueKeysWithValues:)` in recipe grouping, friend saver mapping, collection save visible recipe maps, collection detail image maps, friends shared owner maps, referred-user reconstruction, and user fetch maps.

Failure mode:
Stale CloudKit duplicates, duplicate accepted connections, duplicate collection membership, or duplicate recipe summaries can trap the app.

Likely fix:
Use `Dictionary(_:uniquingKeysWith:)` or `reduce(into:)` with explicit newest/best-candidate selection. Add duplicate-input tests.

Second-pass correction:
The highest-risk confirmed call sites are duplicate friend arrays, lineage saver arrays, duplicate collection recipe IDs, and duplicate public `User` records. Some listed call sites are less exposed.

### P2 - User profile CloudKit saves do not clear optional avatar fields

Evidence:
- `User` has optional avatar fields.
- `saveUser` writes optional fields only when non-nil and never clears absent `profileEmoji`, `profileColor`, `cloudProfileImageRecordName`, or `profileImageModifiedAt`.
- Switching to emoji creates nil image metadata locally, but CloudKit nils are not written.

Failure mode:
Other devices can see stale profile-image metadata after a user switches to emoji, or stale emoji/color after switching to a photo. The app may keep trying to download a deleted profile image record.

Likely fix:
Mirror explicit optional clearing used by collection records. Add mapping tests for photo-to-emoji, emoji-to-photo, and cleared fields.

### P2 - New-user profile photo can be orphaned during onboarding

Evidence:
- Onboarding saves local photo under a provisional `userId`.
- CloudKit user creation can return a different `cloudUser.id`.
- Upload looks for an image under `cloudUser.id`.
- Entity image upload reads `<entityId>.jpg`.

Failure mode:
A user who chooses a profile photo during onboarding can have the local file saved under one UUID while upload looks under another. Upload fails or final `currentUser` lacks the profile image.

Likely fix:
Create/resolve the final user id before saving the image, or move/copy the provisional image to the final user id before upload. Persist final local URL and cloud metadata.

### P2 - Collection cover image metadata is not round-tripped

Evidence:
- `Collection` and `CollectionModel` have `cloudCoverImageRecordName` and `coverImageModifiedAt`.
- Upload stores cover image asset and modified date on the CloudKit record.
- Decode reads cover type but does not set cloud cover record name or modified date.
- Loader downloads only if `collection.cloudCoverImageRecordName != nil`.

Failure mode:
A custom collection cover can sync its asset but decode on another device with no cloud cover record name, making download unreachable.

Likely fix:
When cover image asset or modified date exists, set `cloudCoverImageRecordName = record.recordID.recordName` and preserve modified date. Add mapping tests.

### P2 - Public search grouping drops saver copies needed for context

Evidence:
- Queryable public search now returns one representative per lineage group.
- `RecipeGroupingService` computes save count and friend savers from the recipes it receives.

Failure mode:
Search rows can show `saveCount == 1` and no "Saved by" context even when many friends saved the recipe.

Likely fix:
Return grouped summaries with saver counts/friend owner IDs, or preserve enough duplicate copy records for ranking while showing one visible representative.

### P2 - Profiles silently cap public recipes and tier stats at 100

Evidence:
- Other-user profiles call shared recipe query without an explicit limit.
- Discovery cache defaults to 100.
- Profile tier/counts are derived from the loaded array.

Failure mode:
Users with more than 100 public recipes show incomplete profiles and lower tier/counts.

Likely fix:
Separate profile stats from displayed page data. Use a CloudKit count query for stats and paginate recipe display.

### P2 - Friends feed duplicates recipe lineages

Evidence:
- Friends feed fetches public recipes from all friends with derived copies included.
- It filters related child recipes but only dedupes exact recipe IDs.

Failure mode:
If one friend owns a recipe and another friend saved/follows it, Friends tab can show two cards for the same lineage.

Likely fix:
Group shared recipes by `relatedGraphReferenceID` / `originalRecipeId`; pick one display recipe and carry saver context separately.

## P3 / Quality Gates

### P3 - Simulator QA and tests skip production storage/sync surfaces

Evidence:
- QA mode uses in-memory preview dependencies.
- Tests use in-memory containers.
- Runtime test/QA gates disable CloudKit and queue loops.

Failure mode:
Persistent SwiftData migration issues, queue persistence/replay bugs, CloudKit entitlement/schema/index problems, and production store failures can be invisible until production.

Likely fix:
Add non-QA simulator smoke using persistent SwiftData with CloudKit forced off. Add temp-directory persistent migration tests. Make operation queue persistence testable without relying on global `RuntimeEnvironment.isRunningTests`.

## Audit Gaps To Re-Run

These areas still need another pass:

1. Parser model assembly/parity internals beyond share-extension handoff. The second import pass covered handoff/import UI but did not deeply audit parser schema labs.
2. iPad/Mac layout-specific behavior. The UI pass focused on state/navigation correctness, not visual layout QA.
3. CloudKit record mapping breadth beyond recipe, user, collection cover, and collection membership.
4. Persistent-store and queue migration behavior under real disk-backed containers.
5. Collection membership CloudKit edge reads and stale `recipeIds` compatibility behavior.

## Recommended Fix Order

1. Session-scoped state reset and singleton cleanup.
2. Account deletion/queue destructive replay correctness.
3. Share-extension durable handoff.
4. CloudKit recipe full field round-trip.
5. Image upload/migration durability.
6. Collection delete tombstones and shared membership edge reads.
7. Connection duplicate canonical selection.
8. Editor/create/favorite UI state guards.
9. Deep-link deferred routing.
10. Duplicate-input crash hardening.
11. Search/profile/friends ranking and count correctness.
12. Production-like QA/test surface.
