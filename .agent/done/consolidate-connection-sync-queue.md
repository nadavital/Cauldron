# ExecPlan: Consolidate Connection Sync Queue into OperationQueueService

## Assumptions
- Scope is the full repo at `/Users/nadav/Desktop/Cauldron`.
- Production-level caution is required (CloudKit-backed user data, test suite present).
- Goal is consolidation (fewer overlapping sync concepts), not a CloudKit behavior redesign.

## Problem Statement
Connection sync currently uses a second, custom retry queue that overlaps with the generic operation queue stack:
- `ConnectionManager` owns `OperationType`, private `PendingOperation`, retry timer, in-flight tracking, and retry/backoff flow (`/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/ConnectionManager.swift`).
- Recipes/collections already use shared queue primitives and persistence via `OperationQueueService`/`SyncOperation` (`/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/OperationQueue/OperationQueueService.swift`, `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/OperationQueue/PendingOperation.swift`).

This creates duplicated retry logic, two queue mental models, and inconsistent durability behavior for pending sync work.

## Evidence-Based Mental Model

### Core concepts and locations
- Composition root:
  - `/Users/nadav/Desktop/Cauldron/Cauldron/App/DependencyContainer.swift`
- Connection domain:
  - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/ConnectionManager.swift`
  - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Persistence/ConnectionRepository.swift`
  - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/CloudKit/ConnectionCloudService.swift`
- Generic sync queue:
  - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/OperationQueue/OperationQueueService.swift`
  - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/OperationQueue/PendingOperation.swift`
  - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/OperationQueue/OperationQueueViewModel.swift`
- UI callers:
  - `/Users/nadav/Desktop/Cauldron/Cauldron/Features/Sharing/ConnectionsView.swift`
  - `/Users/nadav/Desktop/Cauldron/Cauldron/Features/Sharing/FriendsTabViewModel.swift`

### Dependency/call-path highlights (3 core flows)
1. Recipe/collection sync path (shared queue path):
   - `RecipeRepository.create/update/delete` and `CollectionRepository.create/update/delete`
   - enqueue into `OperationQueueService`, then async CloudKit sync, then completion/failure updates.
   - Files:
     - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Persistence/RecipeRepository+CRUD.swift`
     - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Persistence/CollectionRepository.swift`
     - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/OperationQueue/OperationQueueService.swift`

2. Connections path (custom queue path):
   - `ConnectionsViewModel.acceptRequest/rejectRequest` -> `ConnectionManager.acceptConnection/rejectConnection`
   - `ConnectionManager.queueOperation/processOperation/processRetries` handles retry and CloudKit.
   - Files:
     - `/Users/nadav/Desktop/Cauldron/Cauldron/Features/Sharing/ConnectionsView.swift`
     - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/ConnectionManager.swift`
     - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/CloudKit/ConnectionCloudService.swift`

3. Shared feed path (independent connection fetch):
   - `FriendsTabViewModel.loadSharedRecipes` -> `SharingService.getSharedRecipes`
   - service fetches connections directly from CloudKit (`connectionCloudService.fetchConnections`), bypassing `ConnectionManager` state.
   - Files:
     - `/Users/nadav/Desktop/Cauldron/Cauldron/Features/Sharing/FriendsTabViewModel.swift`
     - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/SharingService.swift`

### Smells with file evidence
- Duplicate abstractions:
  - `ConnectionManager` has its own retry queue primitives that overlap with `SyncOperation` + `OperationQueueService`.
- Shotgun surgery:
  - Sync policy changes require touching both `OperationQueueService` and `ConnectionManager`.
- Leaky consistency model:
  - Two queue systems means pending/retry behavior is entity-specific instead of platform-wide.

## Candidate Refactors and Ranking

| Candidate | Payoff (30%) | Blast Radius (25%) | Cognitive Load (20%) | Velocity Unlock (15%) | Validation/Rollback (10%) | Weighted |
|---|---:|---:|---:|---:|---:|---:|
| A. Move connection sync/retry to `OperationQueueService` and delete custom connection queue internals | 5 | 3 | 5 | 4 | 4 | 4.25 |
| B. Consolidate friend-graph source of truth so `SharingService` consumes cached connection data path instead of fresh direct fetch every time | 3 | 4 | 4 | 3 | 4 | 3.55 |
| C. Consolidate duplicated friend-image/user preloading in `ContentView` into existing `ConnectionsViewModel`/`EntityImageLoader` path | 2 | 5 | 3 | 2 | 5 | 3.25 |

Chosen refactor: **A**, highest weighted score and largest concept reduction without repo-wide redesign.

## Proposed Refactor (Single Recommendation)

### Current state
- Connections have bespoke queue types and retry orchestration in `ConnectionManager`.
- Other syncable entities use the shared operation queue.
- Result: two sync infrastructures with similar responsibilities.

### Proposed change
Consolidate connection sync onto the shared queue:
1. Extend queue entity model to support connections in `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/OperationQueue/PendingOperation.swift`.
2. Route connection create/accept/reject through `OperationQueueService` rather than `ConnectionManager` private queue.
3. Remove `ConnectionManager` queue internals:
   - `OperationType`
   - private `PendingOperation`
   - `pendingOperations`, `operationsInFlight`, retry timer loop methods.
4. Keep optimistic UI updates and badge behavior in `ConnectionManager`, but delegate retry durability to queue service.

### Files/directories impacted
- `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/ConnectionManager.swift`
- `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/OperationQueue/PendingOperation.swift`
- `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/OperationQueue/OperationQueueService.swift`
- `/Users/nadav/Desktop/Cauldron/Cauldron/App/DependencyContainer.swift` (wiring only if needed)
- `/Users/nadav/Desktop/Cauldron/CauldronTests/Services/ConnectionManagerTests.swift`
- `/Users/nadav/Desktop/Cauldron/CauldronTests/Persistence/CollectionRepositoryTests.swift` (if queue enum/API changes require fixture updates)

### Expected outcome (new shape)
- One generalized pending/retry queue abstraction for sync operations.
- `ConnectionManager` becomes connection state/orchestration only, not queue infrastructure.
- Retry behavior is consistent across recipe, collection, and connection sync.

## Acceptance Criteria
1. `ConnectionManager` no longer defines or owns queue primitives (`OperationType`, private `PendingOperation`, retry timer loop).
2. Connection create/accept/reject operations are represented in `OperationQueueService` and survive app restart.
3. Existing optimistic connection UX remains intact (immediate UI state updates, badge updates).
4. Connection sync tests cover enqueue -> retry -> completion and max-retry failure behavior.

## Risks and Mitigations
- Risk: operation semantics mismatch for `accept`/`reject` vs generic CRUD.
  - Mitigation: introduce explicit connection operation metadata or mapping with clear translator tests.
- Risk: duplicate execution when app restarts with queued operations.
  - Mitigation: idempotency checks keyed by connection ID + status before executing cloud writes.
- Risk: UI regressions in pending/failure indicators.
  - Mitigation: preserve `ConnectionSyncState` derivation from queue state and add focused view-model tests.

## Implementation Plan
1. Extend queue entity typing for connections in `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/OperationQueue/PendingOperation.swift`.
2. Add connection operation execution path in `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/OperationQueue/OperationQueueService.swift` (or a dedicated executor called by it).
3. Refactor `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/ConnectionManager.swift` to enqueue operations and derive sync state from queue outcomes, while preserving optimistic local cache writes.
4. Remove obsolete queue/retry internals from `ConnectionManager`.
5. Update tests for connection retry lifecycle and regression-protect optimistic transitions.

## Validation and Test Steps
1. Run focused connection and queue tests:
   - `xcodebuild -project Cauldron.xcodeproj -scheme Cauldron -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:CauldronTests/ConnectionManagerTests`
2. Run repository sync tests touching queue behavior:
   - `xcodebuild -project Cauldron.xcodeproj -scheme Cauldron -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:CauldronTests/CollectionRepositoryTests`
3. Manual smoke checks:
   - Send friend request, accept request, reject request.
   - Force network failure mode and verify retry/pending/failure states.
   - Restart app during pending operation and verify operation resumes correctly.

## Rollback Plan
1. Revert:
   - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/ConnectionManager.swift`
   - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/OperationQueue/PendingOperation.swift`
   - `/Users/nadav/Desktop/Cauldron/Cauldron/Core/Services/OperationQueue/OperationQueueService.swift`
   - any touched tests.
2. Restore prior connection-specific queue behavior in `ConnectionManager`.
3. Re-run connection flow smoke tests (send/accept/reject + badge updates).
