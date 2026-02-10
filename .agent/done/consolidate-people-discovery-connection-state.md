# Consolidate People Discovery and Connection Interaction into One Shared Feature Path

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document must be maintained in accordance with `.agent/PLANS.md`.

## Purpose / Big Picture

Today, people discovery and friend-request interaction are implemented in multiple parallel feature paths. A user can search for people from the Search tab and also from the Friends sheet, but each path computes connection state differently and performs similar actions through separate view-model logic. After this refactor, there will be one shared people-discovery and connection-interaction path used by both surfaces, so behavior is consistent and changes happen in one place.

The user-visible effect is straightforward: adding, accepting, rejecting, and showing connection status behaves the same in Search and in Friends modal search, including sync/error states. A maintainer can verify this by running the app, triggering the same actions in both surfaces, and observing matching button states and outcomes.

## Progress

- [x] (2026-02-10 05:43Z) Analyzed architecture and call paths for connection-related features; identified duplicate state/action logic across Search, People Search sheet, and Profile flows.
- [x] (2026-02-10 05:43Z) Chose single best consolidation refactor and authored this ExecPlan in `.agent/execplan-pending.md`.
- [x] (2026-02-10 05:57Z) Implemented Milestone 1: added shared `ConnectionRelationshipState` and `ConnectionInteractionCoordinator`, plus `ConnectionInteractionCoordinatorTests` and `PeopleDiscoveryStateMappingTests`.
- [x] (2026-02-10 05:57Z) Implemented Milestone 2: migrated Search People row and People Search sheet to shared relationship state and shared action routing.
- [x] (2026-02-10 05:57Z) Implemented Milestone 3: migrated Profile connection state/actions, removed feature-specific connection enums, and updated `ProfileCacheManager` to use shared state.

## Surprises & Discoveries

- Observation: The repository has no `PLANS.md` at root.
  Evidence: `rg --files -g 'PLANS.md'` returned no results, so `.agent/PLANS.md` was created from skill template and used as source of truth.

- Observation: Connection state is modeled in three separate feature-specific enums in addition to service-level sync state.
  Evidence: `rg -n "enum .*Connection" Cauldron/Features Cauldron/Core/Services/ConnectionManager.swift -g '*.swift'` shows `PeopleSearchConnectionState`, `UserProfileViewModel.ConnectionState`, and `SearchTabView.ConnectionUIState` plus `ConnectionSyncState`.

- Observation: People-search behavior exists in two separate feature stacks with overlapping responsibilities.
  Evidence: `Cauldron/Features/Search/SearchTabViewModel.swift` has `updatePeopleSearch`, `performPeopleSearch`, and connection actions; `Cauldron/Features/Sharing/PeopleSearchSheet.swift` has `performSearch`, `connectionState(for:)`, and similar connection actions.

- Observation: Build/test verification in this environment is blocked by unavailable CoreSimulator services and widget asset compilation that requires simulator runtimes.
  Evidence: `xcodebuild -project Cauldron.xcodeproj -scheme Cauldron -destination 'generic/platform=iOS' -derivedDataPath /tmp/CauldronDerived CODE_SIGNING_ALLOWED=NO build` fails with `No available simulator runtimes for platform iphonesimulator` during `CompileAssetCatalogVariant ... CauldronWidgetExtension`.

## Decision Log

- Decision: Recommend consolidating people discovery and connection interaction as the highest-value single refactor.
  Rationale: This removes duplicate abstractions across large feature files with moderate blast radius and clear behavior-level validation.
  Date/Author: 2026-02-10 / Codex

- Decision: Do not recommend queue/infrastructure refactors in this plan.
  Rationale: Queue consolidation already has a completed plan in `.agent/done/consolidate-connection-sync-queue.md`; this plan targets remaining surface-area duplication in feature layer.
  Date/Author: 2026-02-10 / Codex

- Decision: Standardize on one connection presentation model shared by all people-discovery UIs.
  Rationale: Feature-specific enums currently diverge and create inconsistent UI states; one shared model reduces bug surface.
  Date/Author: 2026-02-10 / Codex

- Decision: Introduce `ConnectionManaging` protocol and inject it into `ConnectionInteractionCoordinator`.
  Rationale: This keeps runtime behavior unchanged while enabling deterministic unit tests for coordinator routing and state mapping.
  Date/Author: 2026-02-10 / Codex

## Outcomes & Retrospective

Implemented outcome: Search People rows, Friends People search rows, and Profile connection actions now consume one shared connection relationship model and one shared action coordinator. Feature-local duplicate enums and duplicated accept/reject/send logic were removed. Remaining gap is full automated verification in this sandbox because CoreSimulator services are unavailable for widget asset compilation; code-level and repository-level checks were completed.

## Context and Orientation

The connection domain already has a strong core service in `Cauldron/Core/Services/ConnectionManager.swift`. That manager owns connection cache, optimistic updates, queue-backed sync, and sync/error states via `ManagedConnection` and `ConnectionSyncState`.

The duplication is in feature-layer orchestration:

- `Cauldron/Features/Search/SearchTabViewModel.swift` loads connections, performs people search, sends/accepts/rejects requests, and computes recommendation lists.
- `Cauldron/Features/Search/SearchTabView.swift` declares `ConnectionUIState` and contains request accept/reject lookup/retry logic in `UserSearchRowView`.
- `Cauldron/Features/Sharing/PeopleSearchSheet.swift` declares `PeopleSearchConnectionState`, has a second people-search view model, and repeats send/accept/reject flows.
- `Cauldron/Features/Profile/UserProfileViewModel.swift` declares `ConnectionState` and repeats connection action orchestration against `ConnectionManager`.
- `Cauldron/Features/Sharing/ConnectionsView.swift` has yet another feature view model that derives received/sent/accepted lists from `ConnectionManager`.

The result is concept duplication, not missing capability. The app already has the backend behavior needed; it lacks a single shared feature-level abstraction for “relationship to user X” and “what actions/buttons are valid right now”.

### Candidate Refactors and Scoring

Candidate A is selected. Scores use the requested weighted criteria where 5 is best:

Candidate A: Consolidate people discovery + connection interaction into one shared feature module used by Search and PeopleSearch surfaces.
Payoff 5, Blast radius 4, Cognitive load reduction 5, Velocity unlock 4, Validation/rollback 4, weighted score 4.55.

Candidate B: Introduce only a shared connection presentation enum while leaving duplicated action/search code in place.
Payoff 3, Blast radius 5, Cognitive load reduction 3, Velocity unlock 3, Validation/rollback 5, weighted score 3.70.

Candidate C: Consolidate only user-detail hydration and caching across connection-related view models.
Payoff 3, Blast radius 3, Cognitive load reduction 3, Velocity unlock 3, Validation/rollback 3, weighted score 3.00.

## Plan of Work

Milestone 1 establishes the shared foundation in the feature/core boundary without changing visible behavior. Add a shared relationship-state type and action coordinator that consumes `ConnectionManager` and exposes a stable API: derive per-user relationship state, send request, accept incoming request, reject incoming request, retry failed sync, and refresh as needed.

Milestone 2 migrates both people-discovery surfaces to this shared path. `SearchTabView` people rows and `PeopleSearchSheet` rows must render from the same state mapping and call the same action methods. Keep existing UI styling, but remove duplicate state-machine branches and duplicated lookup/retry scaffolding in row views.

Milestone 3 migrates remaining dependent screens that currently replicate connection-state mapping (notably `UserProfileViewModel`) and removes obsolete enums/helpers left behind by Milestones 1 and 2. This milestone finalizes consolidation by deleting dead code and locking behavior with tests.

The implementation should remain additive-first: introduce shared abstractions, migrate call sites one-by-one, then remove obsolete code only after tests and manual checks pass.

## Concrete Steps

All commands are run from `/Users/nadav/Desktop/Cauldron`.

1. Create shared connection interaction API and tests first.

       rg -n "ConnectionUIState|PeopleSearchConnectionState|enum ConnectionState" Cauldron/Features -g '*.swift'
       # Expect matches in SearchTabView.swift, PeopleSearchSheet.swift, UserProfileViewModel.swift before migration.

2. Add test file(s) before implementation:

       # New tests recommended:
       # CauldronTests/Features/ConnectionInteractionCoordinatorTests.swift
       # CauldronTests/Features/PeopleDiscoveryStateMappingTests.swift

3. Implement shared feature module (suggested path):

       # Suggested new files:
       # Cauldron/Features/Sharing/ConnectionInteractionCoordinator.swift
       # Cauldron/Features/Sharing/ConnectionRelationshipState.swift

4. Migrate Search and PeopleSearch to shared path, then remove duplicated enums and row action helper methods.

       rg -n "ConnectionUIState|PeopleSearchConnectionState" Cauldron/Features -g '*.swift'
       # After migration, expect zero references.

5. Run focused tests during each milestone, then full suite subset:

       xcodebuild -project Cauldron.xcodeproj -scheme Cauldron -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:CauldronTests/ConnectionManagerTests
       xcodebuild -project Cauldron.xcodeproj -scheme Cauldron -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:CauldronTests/Features

6. Perform manual behavior verification:

       # In app:
       # - Search tab -> People: send request, accept incoming request, reject incoming request.
       # - Friends tab -> + button sheet: repeat same actions.
       # - Verify both surfaces show matching states for the same target user.

## Validation and Acceptance

Acceptance is behavior-first and must be satisfied per milestone.

Milestone 1 acceptance:
1. Tests to write first:
   - `CauldronTests/Features/ConnectionInteractionCoordinatorTests.swift`
   - `testRelationshipState_mapsPendingOutgoingPendingIncomingAcceptedAndSyncing()`
   - `testCoordinator_acceptRejectSend_routeThroughConnectionManager()`
   These tests should fail before shared coordinator exists.
2. Implementation:
   Create shared relationship-state and action coordinator files and wire them to `ConnectionManager`.
3. Verification:
   Run new tests and `ConnectionManagerTests`; all must pass.
4. Commit:
   Commit with message `Milestone 1: Add shared connection interaction coordinator`.

Milestone 2 acceptance:
1. Tests to write first:
   - `CauldronTests/Features/PeopleDiscoveryStateMappingTests.swift`
   - `testSearchAndPeopleSheet_useSameStateMappingForSameManagedConnection()`
   This test fails before migration because state mapping is duplicated.
2. Implementation:
   Migrate `SearchTabView.swift`, `SearchTabViewModel.swift`, and `PeopleSearchSheet.swift` to shared coordinator/state.
3. Verification:
   Run feature tests plus manual flows in both UIs and confirm matching behavior for same user.
4. Commit:
   Commit with message `Milestone 2: Migrate people discovery UIs to shared connection path`.

Milestone 3 acceptance:
1. Tests to write first:
   - Extend tests to cover profile-driven actions (`UserProfileViewModel`) using shared state.
   - Add assertion that legacy enums are removed from feature files.
2. Implementation:
   Migrate `UserProfileViewModel.swift`; remove obsolete enums/helpers in Search and PeopleSearch files.
3. Verification:
   Run connection/service tests and feature tests; perform smoke checks in Search, Friends sheet, and Profile.
4. Commit:
   Commit with message `Milestone 3: Remove duplicated connection state abstractions`.

Final acceptance criteria for the whole refactor:
- Feature-level connection state is defined once and reused; no duplicate per-screen connection-state enums remain.
- Search People and Friends modal People Search use the same action path for send/accept/reject/retry.
- Request status shown for a given user is consistent across both surfaces.
- Existing `ConnectionManager` sync/retry behavior remains unchanged and tests continue to pass.

## Idempotence and Recovery

This migration is safe to run incrementally. Each milestone can be re-run because it is file-scoped and test-gated. If a milestone fails midway, revert only the touched files in that milestone and re-run focused tests before retrying.

If UI regressions appear after Milestone 2, temporarily keep the old row rendering but retain the shared coordinator under a feature flag-like switch (simple branching in view model), then re-migrate once tests confirm parity. This provides a no-data-loss rollback because changes are presentation and action routing, not persistence format changes.

## Artifacts and Notes

Evidence snippets collected during planning:

    $ rg -n "enum .*Connection" Cauldron/Features Cauldron/Core/Services/ConnectionManager.swift -g '*.swift'
    ...PeopleSearchConnectionState...
    ...UserProfileViewModel.ConnectionState...
    ...SearchTabView.ConnectionUIState...

    $ rg -n "func (sendConnectionRequest|acceptConnection|acceptRequest|rejectConnection|rejectRequest|connectionState\\()" Cauldron/Features -g '*.swift'
    ...duplicate action methods across SearchTabViewModel, PeopleSearchViewModel, UserProfileViewModel, ConnectionsViewModel...

    $ rg -n "dependencies\\.connectionManager" Cauldron -g '*.swift'
    ...multiple feature-layer call sites in Search, PeopleSearch, Profile, Connections...

## Interfaces and Dependencies

Introduce a shared, explicit relationship state and coordinator API at the feature boundary.

In `Cauldron/Features/Sharing/ConnectionRelationshipState.swift`, define:

    enum ConnectionRelationshipState: Equatable {
        case currentUser
        case none
        case pendingOutgoing
        case pendingIncoming
        case connected
        case syncing
        case failed(ConnectionError)
    }

In `Cauldron/Features/Sharing/ConnectionInteractionCoordinator.swift`, define:

    @MainActor
    final class ConnectionInteractionCoordinator {
        init(connectionManager: ConnectionManager, currentUserProvider: @escaping () -> UUID)
        func relationshipState(with userId: UUID) -> ConnectionRelationshipState
        func sendRequest(to user: User) async throws
        func acceptRequest(from userId: UUID) async throws
        func rejectRequest(from userId: UUID) async throws
        func removeConnection(with userId: UUID) async throws
        func retryFailedOperation(with userId: UUID) async
    }

`SearchTabViewModel`, `PeopleSearchViewModel`, and `UserProfileViewModel` should depend on this coordinator for connection action routing and state mapping instead of owning duplicated logic. `ConnectionManager` remains the source of truth for persistence/sync and should not be re-architected in this plan.

## Plan Update Note

Created on 2026-02-10 to capture one principal recommendation after repository-wide analysis: consolidate duplicate people-discovery/connection-interaction feature logic into one shared path. This plan intentionally excludes previously documented queue-level consolidation work.

Revised on 2026-02-10 after implementation to mark milestones complete, record environment-specific verification limits, and document design decisions made during coding.
