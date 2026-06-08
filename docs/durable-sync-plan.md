# Durable Recipe and Collection Sync Plan

## Goal

Make recipe deletion, duplicate repair, and collection membership converge correctly across app updates, restarts, offline edits, reinstalls, and multiple devices.

This plan treats CloudKit records as durable sync facts rather than best-effort mirrors of local UI state. Local optimistic updates remain fast, but every user-visible mutation must be replayable, idempotent, and reconcilable.

## Non-Negotiable Invariants

1. A recipe ID is immutable.
2. A recipe ID has one effective state: active, pending delete, or deleted.
3. A deleted recipe ID must not be rehydrated from stale private or public CloudKit records.
4. Recipe deletion wins over collection membership.
5. Collection membership changes must not be lost by whole-record overwrites.
6. Duplicate local recipe rows with the same ID are corruption and must be repaired deterministically.
7. Operation queue entries are retry hints, not the long-term source of truth.
8. Every CloudKit mutation must be safe to retry after app kill or network failure.
9. Saving someone else's recipe must always go through one reusable copy-on-write path.
10. Whole-collection save must go through one reusable copy-on-write path with durable source metadata and duplicate prevention.

## Target Architecture

### Recipe Records

Active recipes continue to live in the private CloudKit recipe table for owner backup and sync. Public recipes continue to have public shared records for discovery and sharing.

### Deleted Recipe Records

Add a durable private CloudKit deletion record per deleted recipe:

- `recipeId`
- `ownerId`
- `deletedAt`
- `cloudRecordName`
- `sourceDeviceId`
- `schemaVersion`

The deletion record is the durable fact. If a stale active recipe record still exists, reconciliation should delete it again. If an active recipe and deletion record both exist, deletion wins.

### Collection Metadata Records

Collection name, description, presentation, visibility, cover image metadata, and owner continue to live on the collection record.

### Collection Membership Edge Records

Move membership correctness from `collection.recipeIds` JSON to one state record per pair:

- `collectionId`
- `recipeId`
- `ownerId`
- `status`: active or removed
- `updatedAt`
- `sourceDeviceId`
- `schemaVersion`

The legacy `recipeIds` field becomes a compatibility cache during migration, not the source of truth.

## Sync Rules

### Recipe Delete

1. Save local deletion tombstone.
2. Remove local recipe row.
3. Hide the recipe from all local collections immediately.
4. Persist a replayable delete operation with enough payload to retry.
5. Write private `DeletedRecipe` record.
6. Delete private recipe record. Missing is success if the deletion record exists.
7. Delete public recipe record. Missing is success if the deletion record exists.
8. Mark operation complete only after the deletion record is persisted and active records are gone or confirmed missing.

### Recipe Full Sync

1. Fetch private active recipes.
2. Fetch private deleted recipe records.
3. Build the deleted ID set from local and remote tombstones.
4. Drop any active cloud recipe whose ID is deleted.
5. Delete any local active recipe whose ID is deleted.
6. Retry remote active-record deletion for any cloud recipe blocked by a tombstone.
7. Merge remaining active recipes by timestamp.
8. Push local-only active recipes unless they are tombstoned.
9. Clean collections by ignoring or removing membership for deleted recipe IDs.

### Collection Membership

1. Reads compute membership from active edge records minus deleted recipe IDs.
2. Add creates or updates the edge to active.
3. Remove creates or updates the edge to removed.
4. Same `collectionId + recipeId` conflict resolves by latest `updatedAt`.
5. Recipe deletion overrides all membership states.
6. Legacy `recipeIds` is updated as a derived compatibility field after reconciliation.

### Recipe Save

1. User-facing recipe saves call `RecipeSaveService`.
2. If the user already owns the recipe, the existing recipe is reused.
3. If the user already has a non-preview local row for the source ID, that row is reused.
4. If the user already has an owned copy for the source graph ID, that copy is reused.
5. If the local row is only a preview, it is converted into a user-owned copy with source tracking.
6. Related recipes selected during save are saved first and remapped into the saved recipe.
7. Public CloudKit image references are localized to the user's copy when possible.
8. Import preview, shared recipe save, recipe detail save, and collection "copy then add" all use this service.

### Collection Save

Whole-collection save creates a user-owned collection copy, saves each visible recipe through `RecipeSaveService`, and writes membership through `CollectionRepository`. To prevent duplicate saved collections across devices, saved collection copies carry explicit source metadata:

- `originalCollectionId`
- `originalCollectionOwnerId`
- `originalCollectionName`
- `savedAt`
- `sourceCollectionUpdatedAt`
- `followsSourceUpdates`

## Migration Strategy

### Release N

- Add deletion-record CloudKit support.
- Start writing deletion records for new deletes.
- Fetch remote deletion records during full sync.
- Keep local tombstones, but stop relying on 30-day local cleanup for correctness.
- Add diagnostics for duplicate recipes and invalid collection memberships.

### Release N+1

- Add collection membership edge records.
- Backfill membership edges from local collections and remote legacy `recipeIds`.
- Continue writing legacy `recipeIds` for older clients.
- Read membership from edges first, with legacy fallback.

### Release N+2

- Treat membership edges as source of truth.
- Keep legacy `recipeIds` only as a derived cache and old-record fallback.

## Implementation Checklist

- [x] Add CloudKit `DeletedRecipe` record constants and mapping.
- [x] Add recipe deletion record save/fetch helpers.
- [x] Update recipe delete flow to write the durable deletion record before marking delete complete.
- [x] Update full sync so remote tombstones suppress stale active recipes.
- [x] Stop aggressive full-sync tombstone cleanup until cleanup is server-aware.
- [x] Add a real recipe/collection operation replay worker.
- [x] Replace duplicate cleanup with deterministic merge-and-repair.
- [x] Add collection membership edge model and CloudKit service.
- [x] Backfill membership edges from legacy collections.
- [x] Read collections from reconciled active membership edges.
- [x] Keep legacy `recipeIds` as compatibility cache during rollout.
- [x] Add cross-device and restart-oriented tests for deletes, duplicates, and collection membership.
- [x] Centralize shared/import/detail/collection recipe save behavior in `RecipeSaveService`.
- [x] Remove unused/manual shared-collection recipe copy helper.
- [x] Remove UI copy that promised whole-collection save before the durable path exists.
- [x] Add collection copy-on-write source metadata.
- [x] Centralize shared collection save behavior in `CollectionSaveService`.
- [x] Expose whole-collection save for non-owned shared collections.

## Remaining Release Work

- Deploy CloudKit schema changes for `DeletedRecipe`, `DeletedCollection`, `CollectionMembership`, and collection copy-on-write metadata, with query indexes for `ownerId`, `deletedAt`, `collectionId`, `recipeId`, `updatedAt`, `originalCollectionId`, and `originalCollectionOwnerId`.
- Run the iOS and Mac Catalyst test suites on a machine with matching Xcode/CoreSimulator/macOS components.
- Exercise a real two-device upgrade path before release: old build creates collections, new build removes membership, second device upgrades and verifies no stale `recipeIds` resurrection.

## Test Matrix

- Delete offline, restart, reconnect: recipe stays deleted.
- Delete while private CloudKit delete fails: operation retries and deletion still wins.
- Cloud has active recipe plus deleted record: local sync keeps recipe deleted.
- New device sees deleted record before or alongside active record: recipe does not appear.
- Duplicate local rows repair into one canonical recipe.
- Duplicate repair preserves collection membership.
- Add to collection on two devices: both memberships survive.
- Remove from collection on one device while another adds a different recipe: both changes survive.
- Delete recipe that appears in collections: recipe disappears from all collections on all devices.
- Public collection containing deleted or unavailable recipe: hidden gracefully.

## First Slice

Start with durable recipe deletion records and full-sync suppression. This addresses the highest-risk data-loss/resurrection path without changing the collection storage model yet.
