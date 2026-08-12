import AppIntents
import CoreSpotlight
import XCTest
@testable import Cauldron

@MainActor
final class RecipeIntentEntityTests: XCTestCase {
    func testAccountIdentityVerificationGateDeniesAccessUntilCurrentRevisionCompletes() {
        var gate = AccountIdentityVerificationGate()
        let launchToken = gate.token

        XCTAssertFalse(gate.isVerified)
        XCTAssertTrue(gate.complete(token: launchToken))
        XCTAssertTrue(gate.isVerified)

        gate.invalidate()

        XCTAssertFalse(gate.isVerified)
        XCTAssertFalse(gate.complete(token: launchToken), "A stale verification must not unlock recipe access")
        XCTAssertFalse(gate.isVerified)

        XCTAssertTrue(gate.complete(token: gate.token))
        XCTAssertTrue(gate.isVerified)
    }

    func testRepeatedAccountInvalidationRejectsEverySupersededVerification() {
        var gate = AccountIdentityVerificationGate()
        let firstToken = gate.token
        gate.invalidate()
        let secondToken = gate.token
        gate.invalidate()

        XCTAssertFalse(gate.complete(token: firstToken))
        XCTAssertFalse(gate.complete(token: secondToken))
        XCTAssertFalse(gate.isVerified)
        XCTAssertTrue(gate.complete(token: gate.token))
    }

    func testAccountMutationTokenSurvivesVerificationWithinSameRevision() {
        var gate = AccountIdentityVerificationGate()
        let mutationToken = gate.mutationToken

        XCTAssertTrue(gate.complete(token: gate.token))
        XCTAssertTrue(gate.permitsMutation(token: mutationToken))
    }

    func testAccountMutationTokenIsRejectedAfterInvalidationAndReverification() {
        var gate = AccountIdentityVerificationGate()
        XCTAssertTrue(gate.complete(token: gate.token))
        let staleMutationToken = gate.mutationToken

        gate.invalidate()
        XCTAssertTrue(gate.complete(token: gate.token))

        XCTAssertFalse(
            gate.permitsMutation(token: staleMutationToken),
            "Reverification for a new iCloud account revision must not revive an in-flight mutation"
        )
        XCTAssertTrue(gate.permitsMutation(token: gate.mutationToken))
    }

    func testVerifiedMutationContextRequiresVerificationAndExactOwner() throws {
        var gate = AccountIdentityVerificationGate()
        let ownerID = UUID()

        XCTAssertNil(gate.mutationContext(ownerID: ownerID))
        XCTAssertTrue(gate.complete(token: gate.token))

        let context = try XCTUnwrap(gate.mutationContext(ownerID: ownerID))
        XCTAssertTrue(gate.permitsMutation(context: context, currentOwnerID: ownerID))
        XCTAssertFalse(gate.permitsMutation(context: context, currentOwnerID: UUID()))
        XCTAssertFalse(gate.permitsMutation(context: context, currentOwnerID: nil))
    }

    func testVerifiedMutationContextCannotCrossAccountSwitchGap() throws {
        var gate = AccountIdentityVerificationGate()
        let originalOwnerID = UUID()
        XCTAssertTrue(gate.complete(token: gate.token))
        let context = try XCTUnwrap(gate.mutationContext(ownerID: originalOwnerID))

        gate.invalidate()
        XCTAssertFalse(gate.permitsMutation(context: context, currentOwnerID: originalOwnerID))

        XCTAssertTrue(gate.complete(token: gate.token))
        XCTAssertFalse(
            gate.permitsMutation(context: context, currentOwnerID: originalOwnerID),
            "Reverification must not revive a mutation captured before an account change"
        )
    }

    func testProfileImageRefreshMergesIntoLatestSameAccountProfile() throws {
        let userID = UUID()
        let cloudModifiedAt = Date(timeIntervalSince1970: 123)
        let staleCloudUser = User(
            id: userID,
            username: "before",
            displayName: "Before Edit",
            profileEmoji: "🍲",
            profileColor: "AA0000",
            cloudProfileImageRecordName: "image-record",
            profileImageModifiedAt: cloudModifiedAt
        )
        let editedWhileDownloading = User(
            id: userID,
            username: "after",
            displayName: "After Edit",
            email: "after@example.com",
            cloudRecordName: "user-record",
            referralCode: "REFRESH",
            createdAt: staleCloudUser.createdAt,
            profileEmoji: staleCloudUser.profileEmoji,
            profileColor: staleCloudUser.profileColor,
            cloudProfileImageRecordName: staleCloudUser.cloudProfileImageRecordName,
            profileImageModifiedAt: staleCloudUser.profileImageModifiedAt
        )
        let downloadedURL = URL(fileURLWithPath: "/tmp/profile.jpg")

        let merged = try XCTUnwrap(ProfileImageRefreshMergePolicy.mergingDownloadedImage(
            downloadedURL,
            cloudSnapshot: staleCloudUser,
            into: editedWhileDownloading
        ))

        XCTAssertEqual(merged.username, "after")
        XCTAssertEqual(merged.displayName, "After Edit")
        XCTAssertEqual(merged.email, "after@example.com")
        XCTAssertEqual(merged.referralCode, "REFRESH")
        XCTAssertEqual(merged.profileEmoji, "🍲")
        XCTAssertEqual(merged.profileColor, "AA0000")
        XCTAssertEqual(merged.profileImageURL, downloadedURL)
        XCTAssertEqual(merged.cloudProfileImageRecordName, "image-record")
        XCTAssertEqual(merged.profileImageModifiedAt, cloudModifiedAt)
    }

    func testProfileImageRefreshRejectsDifferentCurrentAccount() {
        let cloudUser = User(id: UUID(), username: "old", displayName: "Old")
        let latestUser = User(id: UUID(), username: "new", displayName: "New")

        XCTAssertNil(ProfileImageRefreshMergePolicy.mergingDownloadedImage(
            URL(fileURLWithPath: "/tmp/profile.jpg"),
            cloudSnapshot: cloudUser,
            into: latestUser
        ))
    }

    func testProfileImageRefreshDoesNotRestorePhotoAfterEmojiSwitch() {
        let userID = UUID()
        let snapshot = User(
            id: userID,
            username: "cook",
            displayName: "Cook",
            cloudProfileImageRecordName: "old-photo",
            profileImageModifiedAt: Date(timeIntervalSince1970: 10)
        )
        let latest = User(
            id: userID,
            username: "cook",
            displayName: "Cook",
            profileEmoji: "🥘",
            profileColor: "00AA00"
        )

        XCTAssertNil(ProfileImageRefreshMergePolicy.mergingDownloadedImage(
            URL(fileURLWithPath: "/tmp/old-photo.jpg"),
            cloudSnapshot: snapshot,
            into: latest
        ))
    }

    func testProfileImageRefreshDoesNotReplaceNewerPhoto() {
        let userID = UUID()
        let oldDate = Date(timeIntervalSince1970: 10)
        let snapshot = User(
            id: userID,
            username: "cook",
            displayName: "Cook",
            cloudProfileImageRecordName: "old-photo",
            profileImageModifiedAt: oldDate
        )
        let latest = User(
            id: userID,
            username: "cook",
            displayName: "Cook",
            profileImageURL: URL(fileURLWithPath: "/tmp/new-photo.jpg"),
            cloudProfileImageRecordName: "new-photo",
            profileImageModifiedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertNil(ProfileImageRefreshMergePolicy.mergingDownloadedImage(
            URL(fileURLWithPath: "/tmp/old-photo.jpg"),
            cloudSnapshot: snapshot,
            into: latest
        ))
    }

    func testProfileAvatarRevisionIgnoresBasicInfoButDetectsAvatarChanges() {
        let ownerID = UUID()
        let imageURL = URL(fileURLWithPath: "/tmp/avatar.jpg")
        let modifiedAt = Date(timeIntervalSince1970: 20)
        let original = User(
            id: ownerID,
            username: "before",
            displayName: "Before",
            profileImageURL: imageURL,
            cloudProfileImageRecordName: "avatar-record",
            profileImageModifiedAt: modifiedAt
        )
        let renamed = User(
            id: ownerID,
            username: "after",
            displayName: "After",
            profileImageURL: imageURL,
            cloudProfileImageRecordName: "avatar-record",
            profileImageModifiedAt: modifiedAt
        )
        let switchedToEmoji = User(
            id: ownerID,
            username: "after",
            displayName: "After",
            profileEmoji: "🥘",
            profileColor: "FF5500"
        )

        XCTAssertEqual(ProfileAvatarState(user: original), ProfileAvatarState(user: renamed))
        XCTAssertNotEqual(ProfileAvatarState(user: original), ProfileAvatarState(user: switchedToEmoji))

        let localReplacement = User(
            id: ownerID,
            username: "after",
            displayName: "After",
            profileImageURL: imageURL,
            cloudProfileImageRecordName: "avatar-record",
            profileImageModifiedAt: modifiedAt,
            profileImageLocalRevision: UUID()
        )
        XCTAssertNotEqual(ProfileAvatarState(user: original), ProfileAvatarState(user: localReplacement))
    }

    func testProfileEditorBasicDirtyStateUsesOpeningSnapshotNotLiveSession() {
        let openingUser = User(username: "opening", displayName: "Opening Name")
        let renamedElsewhere = openingUser.updatedBasicInfo(
            username: "elsewhere",
            displayName: "Elsewhere Name"
        )

        XCTAssertFalse(ProfileEditChangePolicy.didEditBasicInfo(
            initialUser: openingUser,
            username: openingUser.username,
            displayName: openingUser.displayName
        ))
        XCTAssertTrue(ProfileEditChangePolicy.didEditBasicInfo(
            initialUser: openingUser,
            username: renamedElsewhere.username,
            displayName: renamedElsewhere.displayName
        ))
    }

    func testNewerWindowBasicEditInvalidatesOlderCombinedSave() {
        let ownerID = UUID()
        var gate = ProfileBasicInfoMutationGate()
        let olderCombinedSave = gate.reserve(ownerID: ownerID)
        let newerBasicSave = gate.reserve(ownerID: ownerID)
        let latestUser = User(
            id: ownerID,
            username: "newer",
            displayName: "Newer Name"
        )

        let afterOlderAvatarFinishes = ProfileBasicInfoMergePolicy.mergingCapturedBasicInfo(
            username: "older",
            displayName: "Older Name",
            whenAuthorized: gate.permits(olderCombinedSave, ownerID: ownerID),
            into: latestUser
        )
        let afterNewerBasicFinishes = ProfileBasicInfoMergePolicy.mergingCapturedBasicInfo(
            username: "newer",
            displayName: "Newer Name",
            whenAuthorized: gate.permits(newerBasicSave, ownerID: ownerID),
            into: afterOlderAvatarFinishes
        )

        XCTAssertEqual(afterOlderAvatarFinishes.username, "newer")
        XCTAssertEqual(afterOlderAvatarFinishes.displayName, "Newer Name")
        XCTAssertEqual(afterNewerBasicFinishes.username, "newer")
        XCTAssertEqual(afterNewerBasicFinishes.displayName, "Newer Name")
    }

    func testPendingBasicEditPreservesStagedAvatarGeneration() {
        let ownerID = UUID()
        let visibleRevision = UUID()
        let pendingRevision = UUID()
        let visibleUser = User(
            id: ownerID,
            username: "visible",
            displayName: "Visible",
            profileImageURL: URL(fileURLWithPath: "/tmp/visible.jpg"),
            profileImageLocalRevision: visibleRevision
        )
        let pendingUser = User(
            id: ownerID,
            username: "pending",
            displayName: "Pending",
            profileImageURL: URL(fileURLWithPath: "/tmp/pending.jpg"),
            profileImageLocalRevision: pendingRevision
        )

        let merged = PendingProfileSyncMergePolicy.mergingBasicInfo(
            username: "renamed",
            displayName: "Renamed User",
            inheritedPendingUser: pendingUser,
            visibleUser: visibleUser
        )

        XCTAssertEqual(merged.username, "renamed")
        XCTAssertEqual(merged.displayName, "Renamed User")
        XCTAssertEqual(merged.profileImageURL, pendingUser.profileImageURL)
        XCTAssertEqual(merged.profileImageLocalRevision, pendingRevision)
    }

    func testProfileMutationOrderingKeepsAvatarIntentSeparateFromBasicCommits() {
        var gate = ProfileMutationOrderingGate()
        let slowPhotoIntent = gate.reserveAvatarIntent()
        let olderBasicIntent = gate.reserveBasicIntent()
        XCTAssertTrue(gate.isCurrentAvatarIntent(slowPhotoIntent))

        let newerEmojiIntent = gate.reserveAvatarIntent()
        XCTAssertFalse(gate.isCurrentAvatarIntent(slowPhotoIntent))
        XCTAssertTrue(gate.permitsCommit(avatarIntent: newerEmojiIntent, basicIntent: nil))

        let laterBasicIntent = gate.reserveBasicIntent()
        XCTAssertTrue(gate.isCurrentAvatarIntent(newerEmojiIntent))
        XCTAssertTrue(gate.permitsCommit(avatarIntent: newerEmojiIntent, basicIntent: nil))
        XCTAssertTrue(gate.permitsCommit(avatarIntent: nil, basicIntent: laterBasicIntent))
        XCTAssertFalse(gate.permitsCommit(avatarIntent: nil, basicIntent: olderBasicIntent))
    }

    func testAvatarPublicationLinearizesBeforeDurableMarker() {
        var gate = ProfileMutationOrderingGate()
        let photoIntent = gate.reserveAvatarIntent()
        XCTAssertTrue(gate.permitsCommit(avatarIntent: photoIntent, basicIntent: nil))
        XCTAssertTrue(gate.beginAvatarPublication(photoIntent))

        // A later avatar action is ordered after the already-linearized
        // publication and cannot publish until the current critical section ends.
        let laterEmojiIntent = gate.reserveAvatarIntent()
        XCTAssertFalse(gate.beginAvatarPublication(laterEmojiIntent))
        gate.endAvatarPublication(photoIntent)
        XCTAssertTrue(gate.beginAvatarPublication(laterEmojiIntent))
    }

    func testMapsSearchableAndSiriContextFields() {
        let recipe = makeRecipe(
            title: "Lemon Pasta",
            ingredients: ["Spaghetti", "Lemon", "Parmesan"],
            tags: ["Dinner", "Quick"],
            notes: "Finish with black pepper."
        )

        let entity = RecipeIntentEntity(recipe: recipe)

        XCTAssertEqual(entity.id, recipe.id)
        XCTAssertEqual(entity.ingredientNames, ["Spaghetti", "Lemon", "Parmesan"])
        XCTAssertEqual(entity.tagNames, ["Dinner", "Quick & Easy"])
        XCTAssertTrue(entity.instructions.contains("Boil pasta"))
        XCTAssertTrue(entity.siriContext.contains("Ingredients:"))
        XCTAssertTrue(entity.siriContext.contains("Finish with black pepper"))
        XCTAssertEqual(entity.attributeSet.title, "Lemon Pasta")
        XCTAssertEqual(
            Set(entity.attributeSet.keywords ?? []),
            Set(["Spaghetti", "Lemon", "Parmesan", "Dinner", "Quick & Easy"])
        )
        XCTAssertEqual(entity.attributeSet.metadataModificationDate, recipe.updatedAt)
        XCTAssertEqual(entity.attributeSet.duration?.intValue, 1_800)
        XCTAssertEqual(entity.attributeSet.userOwned, true)
    }

    func testSiriContextIsBoundedAndOmitsCloudIdentifiers() {
        let recipe = Recipe(
            title: "Long Recipe",
            ingredients: [Ingredient(name: String(repeating: "ingredient", count: 2_000))],
            steps: [CookStep(index: 0, text: String(repeating: "instruction", count: 2_000))],
            cloudRecordName: "private-cloud-record",
            cloudImageRecordName: "private-image-record"
        )

        let context = RecipeIntentEntity(recipe: recipe).siriContext

        XCTAssertLessThanOrEqual(context.count, 12_000)
        XCTAssertFalse(context.contains("private-cloud-record"))
        XCTAssertFalse(context.contains("private-image-record"))
    }

    func testStringSearchRanksExactThenPrefixThenIngredientMatches() {
        let exact = makeRecipe(title: "Pasta", ingredients: ["Flour"])
        let prefix = makeRecipe(title: "Pasta Primavera", ingredients: ["Peas"])
        let ingredient = makeRecipe(title: "Weeknight Dinner", ingredients: ["Pasta"])

        let results = RecipeIntentSearch.stringMatches(
            "pasta",
            in: [ingredient, prefix, exact],
            limit: 10
        )

        XCTAssertEqual(results.map(\.id), [exact.id, prefix.id, ingredient.id])
    }

    func testPropertyFilteringSupportsAndOrAndLimit() {
        let favoriteQuick = RecipeIntentEntity(recipe: makeRecipe(
            title: "Fast Curry",
            ingredients: ["Chickpea"],
            totalMinutes: 20,
            isFavorite: true
        ))
        let slow = RecipeIntentEntity(recipe: makeRecipe(
            title: "Slow Curry",
            ingredients: ["Chicken"],
            totalMinutes: 90,
            isFavorite: false
        ))

        let andResults = RecipeIntentSearch.filter(
            [slow, favoriteQuick],
            comparators: [.titleContains("curry"), .maximumMinutes(30), .favorite(true)],
            requireAll: true,
            sorts: [],
            limit: nil
        )
        let orResults = RecipeIntentSearch.filter(
            [slow, favoriteQuick],
            comparators: [.ingredientContains("chicken"), .favorite(true)],
            requireAll: false,
            sorts: [],
            limit: 1
        )

        XCTAssertEqual(andResults.map(\.id), [favoriteQuick.id])
        XCTAssertEqual(orResults.count, 1)
    }

    func testTotalTimeSortKeepsUnknownDurationsLastInBothDirections() {
        let short = RecipeIntentEntity(recipe: makeRecipe(
            title: "Short",
            ingredients: [],
            totalMinutes: 15
        ))
        let long = RecipeIntentEntity(recipe: makeRecipe(
            title: "Long",
            ingredients: [],
            totalMinutes: 90
        ))
        let unknown = RecipeIntentEntity(recipe: makeRecipe(
            title: "Unknown",
            ingredients: [],
            totalMinutes: nil
        ))

        XCTAssertEqual(
            RecipeIntentSearch.sortedByTotalMinutes([unknown, long, short], ascending: true).map(\.title),
            ["Short", "Long", "Unknown"]
        )
        XCTAssertEqual(
            RecipeIntentSearch.sortedByTotalMinutes([unknown, short, long], ascending: false).map(\.title),
            ["Long", "Short", "Unknown"]
        )
    }

    func testSpotlightFingerprintChangesOnlyWhenIndexedContentChanges() {
        let original = RecipeIntentEntity(recipe: makeRecipe(
            title: "Pasta",
            ingredients: ["Lemon"]
        ))
        let same = original
        let renamed = RecipeIntentEntity(
            id: original.id,
            title: "Lemon Pasta",
            ingredientNames: original.ingredientNames,
            instructions: original.instructions,
            totalMinutes: original.totalMinutes,
            tagNames: original.tagNames,
            isFavorite: original.isFavorite,
            recipeYield: original.recipeYield,
            updatedAt: original.updatedAt,
            createdAt: original.createdAt
        )

        XCTAssertEqual(
            RecipeSpotlightIndexer.fingerprint(for: original),
            RecipeSpotlightIndexer.fingerprint(for: same)
        )
        XCTAssertNotEqual(
            RecipeSpotlightIndexer.fingerprint(for: original),
            RecipeSpotlightIndexer.fingerprint(for: renamed)
        )
    }

    func testSpotlightQueueCoalescesRequestsWhileWorkerIsActive() {
        let firstOwner = UUID()
        let secondOwner = UUID()
        var queue = RecipeSpotlightReconciliationQueue()

        XCTAssertTrue(queue.enqueue(.accountBoundary(ownerID: firstOwner)))
        XCTAssertFalse(queue.enqueue(.full(ownerID: secondOwner, recipes: [])))
        XCTAssertTrue(queue.isWorkerActive)
        XCTAssertEqual(queue.nextGeneration, 2)

        let pending = queue.takeNext()
        XCTAssertEqual(pending?.generation, 2)
        XCTAssertEqual(pending?.request.ownerID, secondOwner)
        XCTAssertNil(queue.takeNext())

        queue.finishWorker()
        XCTAssertFalse(queue.isWorkerActive)
    }

    func testSpotlightQueueDrainsRequestThatArrivesDuringSuspendedWork() {
        let staleOwner = UUID()
        let verifiedOwner = UUID()
        var queue = RecipeSpotlightReconciliationQueue()

        XCTAssertTrue(queue.enqueue(.full(ownerID: staleOwner, recipes: nil)))
        let staleRequest = queue.takeNext()
        XCTAssertEqual(staleRequest?.request.ownerID, staleOwner)

        // Models a verified account transition while the worker is suspended
        // deleting the previous account's Core Spotlight entities.
        XCTAssertFalse(queue.enqueue(.accountBoundary(ownerID: verifiedOwner)))
        let resumedRequest = queue.takeNext()
        XCTAssertEqual(resumedRequest?.generation, 2)
        XCTAssertEqual(resumedRequest?.request.ownerID, verifiedOwner)

        queue.finishWorker()
        XCTAssertFalse(queue.isWorkerActive)
        XCTAssertTrue(queue.enqueue(.full(ownerID: verifiedOwner, recipes: [])))
    }

    func testSpotlightQueueDoesNotCreateRetryWorkWithoutAnExternalRequest() {
        let ownerID = UUID()
        var queue = RecipeSpotlightReconciliationQueue()

        XCTAssertTrue(queue.enqueue(.accountBoundary(ownerID: ownerID)))
        XCTAssertNotNil(queue.takeNext())

        // An unverified request is invalidated and suspended by the indexer;
        // completing it must leave no self-generated request to hot-spin.
        XCTAssertNil(queue.takeNext())
        queue.finishWorker()
        XCTAssertFalse(queue.isWorkerActive)
        XCTAssertEqual(queue.nextGeneration, 1)
    }

    func testSpotlightRetryPolicyUsesExponentialBackoffAndStopsAtAttemptCap() {
        var policy = RecipeSpotlightRetryPolicy(
            maximumAttempts: 5,
            baseDelaySeconds: 2,
            maximumDelaySeconds: 16
        )

        XCTAssertEqual(policy.nextDelayAfterFailure(), .seconds(2))
        XCTAssertEqual(policy.nextDelayAfterFailure(), .seconds(4))
        XCTAssertEqual(policy.nextDelayAfterFailure(), .seconds(8))
        XCTAssertEqual(policy.nextDelayAfterFailure(), .seconds(16))
        XCTAssertEqual(policy.nextDelayAfterFailure(), .seconds(16))
        XCTAssertNil(policy.nextDelayAfterFailure())
        XCTAssertEqual(policy.attempts, 5)
    }

    func testSpotlightRetryPolicyExternalRequestResetsBudgetButInternalRetryDoesNot() {
        var policy = RecipeSpotlightRetryPolicy(
            maximumAttempts: 3,
            baseDelaySeconds: 2,
            maximumDelaySeconds: 8
        )

        XCTAssertEqual(policy.nextDelayAfterFailure(), .seconds(2))
        policy.prepare(for: .retry)
        XCTAssertEqual(policy.nextDelayAfterFailure(), .seconds(4))
        XCTAssertEqual(policy.attempts, 2)

        policy.prepare(for: .external)
        XCTAssertEqual(policy.attempts, 0)
        XCTAssertEqual(policy.nextDelayAfterFailure(), .seconds(2))
    }

    func testSpotlightRetryPolicySuccessResetRestoresInitialDelay() {
        var policy = RecipeSpotlightRetryPolicy(
            maximumAttempts: 2,
            baseDelaySeconds: 3,
            maximumDelaySeconds: 6
        )

        XCTAssertEqual(policy.nextDelayAfterFailure(), .seconds(3))
        XCTAssertEqual(policy.nextDelayAfterFailure(), .seconds(6))
        XCTAssertNil(policy.nextDelayAfterFailure())

        policy.reset()

        XCTAssertEqual(policy.attempts, 0)
        XCTAssertEqual(policy.nextDelayAfterFailure(), .seconds(3))
    }

    func testTimerDonationOnlyRepresentsExactMinuteDurations() {
        XCTAssertNil(RecipeIntentDonation.timerDonationMinutes(
            for: TimerSpec(seconds: 30, label: "Quick")
        ))
        XCTAssertNil(RecipeIntentDonation.timerDonationMinutes(
            for: TimerSpec(seconds: 90, label: "Rest")
        ))
        XCTAssertEqual(RecipeIntentDonation.timerDonationMinutes(
            for: TimerSpec(seconds: 300, label: "Simmer")
        ), 5)
    }

    func testRecipeDonationBoundaryDeletesOnlyRecipeScopedIntentKinds() async {
        let defaults = makeDonationDefaults()
        var deleted: [RecipeIntentDonationBoundaryCoordinator.RecipeScopedIntent] = []
        let coordinator = RecipeIntentDonationBoundaryCoordinator(
            defaults: defaults,
            deleteDonations: { deleted.append($0) }
        )

        let result = await coordinator.reconcile(currentOwnerID: UUID())

        XCTAssertEqual(result, .deleted)
        XCTAssertEqual(deleted, [.startCookingRecipe, .addRecipeIngredientsToGroceries])
    }

    func testRecipeDonationBoundarySkipsUnchangedOwnerAndDeletesOnAccountSwitchAndSignOut() async {
        let defaults = makeDonationDefaults()
        let ownerID = UUID()
        var deleted: [RecipeIntentDonationBoundaryCoordinator.RecipeScopedIntent] = []
        let coordinator = RecipeIntentDonationBoundaryCoordinator(
            defaults: defaults,
            deleteDonations: { deleted.append($0) }
        )

        let initialResult = await coordinator.reconcile(currentOwnerID: ownerID)
        XCTAssertEqual(initialResult, .deleted)
        deleted.removeAll()
        let unchangedResult = await coordinator.reconcile(currentOwnerID: ownerID)
        XCTAssertEqual(unchangedResult, .unchanged)
        XCTAssertTrue(deleted.isEmpty)

        let accountSwitchResult = await coordinator.reconcile(currentOwnerID: UUID())
        XCTAssertEqual(accountSwitchResult, .deleted)
        XCTAssertEqual(deleted, [.startCookingRecipe, .addRecipeIngredientsToGroceries])

        deleted.removeAll()
        let signOutResult = await coordinator.reconcile(currentOwnerID: nil)
        XCTAssertEqual(signOutResult, .deleted)
        XCTAssertEqual(deleted, [.startCookingRecipe, .addRecipeIngredientsToGroceries])
    }

    func testRecipeDonationBoundaryRetriesAllKindsAfterPartialFailure() async {
        struct TestError: Error {}

        let defaults = makeDonationDefaults()
        var attempts: [RecipeIntentDonationBoundaryCoordinator.RecipeScopedIntent] = []
        var shouldFail = true
        let coordinator = RecipeIntentDonationBoundaryCoordinator(
            defaults: defaults,
            deleteDonations: { intent in
                attempts.append(intent)
                if shouldFail, intent == .startCookingRecipe {
                    throw TestError()
                }
            }
        )

        let failedResult = await coordinator.reconcile(currentOwnerID: UUID())
        XCTAssertEqual(failedResult, .deletionFailed([.startCookingRecipe]))
        XCTAssertFalse(failedResult.allowsDonation)
        XCTAssertEqual(attempts, [.startCookingRecipe, .addRecipeIngredientsToGroceries])

        attempts.removeAll()
        shouldFail = false
        let retryResult = await coordinator.reconcile(currentOwnerID: UUID())
        XCTAssertEqual(retryResult, .deleted)
        XCTAssertTrue(retryResult.allowsDonation)
        XCTAssertEqual(attempts, [.startCookingRecipe, .addRecipeIngredientsToGroceries])
    }

    func testRecipeDonationBoundaryCoalescesSuspendedAccountSwitchToNewestOwner() async {
        let defaults = makeDonationDefaults()
        let firstOwnerID = UUID()
        let newestOwnerID = UUID()
        var deletionAttempts: [RecipeIntentDonationBoundaryCoordinator.RecipeScopedIntent] = []
        var requestedOwners: [UUID?] = []
        let firstDeleteStarted = AsyncGate()
        let allowFirstDeleteToFinish = AsyncGate()
        let coordinator = RecipeIntentDonationBoundaryCoordinator(
            defaults: defaults,
            deleteDonations: { intent in
                deletionAttempts.append(intent)
                if deletionAttempts.count == 1 {
                    await firstDeleteStarted.open()
                    await allowFirstDeleteToFinish.wait()
                }
            },
            reconciliationRequested: { ownerID in
                requestedOwners.append(ownerID)
            }
        )

        async let firstResult = coordinator.reconcile(currentOwnerID: firstOwnerID)
        await firstDeleteStarted.wait()

        let newestRequestCompletion = AsyncCompletionProbe()
        async let newestResult: RecipeIntentDonationBoundaryCoordinator.ReconciliationResult = {
            let result = await coordinator.reconcile(currentOwnerID: newestOwnerID)
            await newestRequestCompletion.markCompleted()
            return result
        }()
        await Task.yield()
        XCTAssertEqual(requestedOwners, [firstOwnerID, newestOwnerID])
        let completedBeforeCleanup = await newestRequestCompletion.isCompleted
        XCTAssertFalse(completedBeforeCleanup, "Donation callers must wait for boundary cleanup")
        await allowFirstDeleteToFinish.open()

        let resolvedFirstResult = await firstResult
        let resolvedNewestResult = await newestResult
        XCTAssertEqual(resolvedFirstResult, .deleted)
        XCTAssertEqual(resolvedNewestResult, .deleted)
        XCTAssertEqual(requestedOwners, [firstOwnerID, newestOwnerID])
        XCTAssertEqual(
            deletionAttempts,
            [.startCookingRecipe, .startCookingRecipe, .addRecipeIngredientsToGroceries]
        )

        deletionAttempts.removeAll()
        coordinator.recordDonation(ownerID: firstOwnerID)
        let unchangedResult = await coordinator.reconcile(currentOwnerID: newestOwnerID)
        XCTAssertEqual(unchangedResult, .unchanged)
        XCTAssertTrue(deletionAttempts.isEmpty)
        let switchedBackResult = await coordinator.reconcile(currentOwnerID: firstOwnerID)
        XCTAssertEqual(switchedBackResult, .deleted)
    }

    func testRecipeDonationBoundaryCoalescesSignOutAndRetriesNewestFailedCleanup() async {
        struct TestError: Error {}

        let defaults = makeDonationDefaults()
        let ownerID = UUID()
        var deletionAttempts: [RecipeIntentDonationBoundaryCoordinator.RecipeScopedIntent] = []
        var shouldFailNewestCleanup = true
        let firstDeleteStarted = AsyncGate()
        let allowFirstDeleteToFinish = AsyncGate()
        let secondRequestObserved = expectation(description: "Second reconciliation request observed")
        var requestCount = 0
        let coordinator = RecipeIntentDonationBoundaryCoordinator(
            defaults: defaults,
            deleteDonations: { intent in
                deletionAttempts.append(intent)
                if deletionAttempts.count == 1 {
                    await firstDeleteStarted.open()
                    await allowFirstDeleteToFinish.wait()
                } else if shouldFailNewestCleanup, intent == .startCookingRecipe {
                    throw TestError()
                }
            },
            reconciliationRequested: { _ in
                requestCount += 1
                if requestCount == 2 {
                    secondRequestObserved.fulfill()
                }
            }
        )

        async let ownerResult = coordinator.reconcile(currentOwnerID: ownerID)
        await firstDeleteStarted.wait()

        async let signOutResult = coordinator.reconcile(currentOwnerID: nil)
        await fulfillment(of: [secondRequestObserved], timeout: 1)
        XCTAssertEqual(requestCount, 2)
        await allowFirstDeleteToFinish.open()

        let expectedFailure = RecipeIntentDonationBoundaryCoordinator.ReconciliationResult
            .deletionFailed([.startCookingRecipe])
        let resolvedOwnerResult = await ownerResult
        let resolvedSignOutResult = await signOutResult
        XCTAssertEqual(resolvedOwnerResult, expectedFailure)
        XCTAssertEqual(resolvedSignOutResult, expectedFailure)

        shouldFailNewestCleanup = false
        deletionAttempts.removeAll()
        let retryResult = await coordinator.reconcile(currentOwnerID: nil)
        XCTAssertEqual(retryResult, .deleted)
        XCTAssertEqual(
            deletionAttempts,
            [.startCookingRecipe, .addRecipeIngredientsToGroceries]
        )
        deletionAttempts.removeAll()
        let unchangedResult = await coordinator.reconcile(currentOwnerID: nil)
        XCTAssertEqual(unchangedResult, .unchanged)
        XCTAssertTrue(deletionAttempts.isEmpty)
    }

    func testRecipeDonationBoundaryWaitsForSuspendedDonationThenCleansNewestOwner() async throws {
        let defaults = makeDonationDefaults()
        let firstOwnerID = UUID()
        let newestOwnerID = UUID()
        var currentOwnerID: UUID? = firstOwnerID
        var deletionAttempts: [RecipeIntentDonationBoundaryCoordinator.RecipeScopedIntent] = []
        let donationStarted = AsyncGate()
        let allowDonationToFinish = AsyncGate()
        let boundaryCompletion = AsyncCompletionProbe()
        let coordinator = RecipeIntentDonationBoundaryCoordinator(
            defaults: defaults,
            deleteDonations: { deletionAttempts.append($0) }
        )

        async let donationResult = coordinator.performDonation(
            ownerID: firstOwnerID,
            currentOwnerID: { currentOwnerID }
        ) {
            await donationStarted.open()
            await allowDonationToFinish.wait()
        }
        await donationStarted.wait()

        currentOwnerID = newestOwnerID
        async let boundaryResult: RecipeIntentDonationBoundaryCoordinator.ReconciliationResult = {
            let result = await coordinator.reconcile(currentOwnerID: newestOwnerID)
            await boundaryCompletion.markCompleted()
            return result
        }()
        await Task.yield()
        let completedBeforeDonation = await boundaryCompletion.isCompleted
        XCTAssertFalse(
            completedBeforeDonation,
            "Account cleanup must wait until an in-flight system donation finishes"
        )

        await allowDonationToFinish.open()
        let donated = try await donationResult
        let reconciled = await boundaryResult

        XCTAssertFalse(donated)
        XCTAssertEqual(reconciled, .deleted)
        XCTAssertEqual(
            deletionAttempts,
            [
                .startCookingRecipe,
                .addRecipeIngredientsToGroceries,
                .startCookingRecipe,
                .addRecipeIngredientsToGroceries
            ]
        )
        let unchanged = await coordinator.reconcile(currentOwnerID: newestOwnerID)
        XCTAssertEqual(unchanged, .unchanged)
    }

    func testRecipeDonationBoundaryRejectsStaleCallerBeforeReconciliation() async throws {
        let defaults = makeDonationDefaults()
        let staleOwnerID = UUID()
        let currentOwnerID = UUID()
        var deletionAttempts: [RecipeIntentDonationBoundaryCoordinator.RecipeScopedIntent] = []
        var operationRan = false
        let coordinator = RecipeIntentDonationBoundaryCoordinator(
            defaults: defaults,
            deleteDonations: { deletionAttempts.append($0) }
        )

        let donated = try await coordinator.performDonation(
            ownerID: staleOwnerID,
            currentOwnerID: { currentOwnerID }
        ) {
            operationRan = true
        }

        XCTAssertFalse(donated)
        XCTAssertFalse(operationRan)
        XCTAssertTrue(deletionAttempts.isEmpty)
    }

    func testRecipeDonationBoundarySerializesSameOwnerDonationsBeforeAccountCleanup() async throws {
        let defaults = makeDonationDefaults()
        let ownerID = UUID()
        let newestOwnerID = UUID()
        var currentOwnerID: UUID? = ownerID
        var deletionAttempts: [RecipeIntentDonationBoundaryCoordinator.RecipeScopedIntent] = []
        let firstStarted = AsyncGate()
        let finishFirst = AsyncGate()
        let secondStarted = AsyncCompletionProbe()
        let finishSecond = AsyncGate()
        let boundaryCompleted = AsyncCompletionProbe()
        let coordinator = RecipeIntentDonationBoundaryCoordinator(
            defaults: defaults,
            deleteDonations: { deletionAttempts.append($0) }
        )

        async let firstResult = coordinator.performDonation(
            ownerID: ownerID,
            currentOwnerID: { currentOwnerID }
        ) {
            await firstStarted.open()
            await finishFirst.wait()
        }
        await firstStarted.wait()

        async let secondResult = coordinator.performDonation(
            ownerID: ownerID,
            currentOwnerID: { currentOwnerID }
        ) {
            await secondStarted.markCompleted()
            await finishSecond.wait()
        }
        await Task.yield()
        let secondStartedTooEarly = await secondStarted.isCompleted
        XCTAssertFalse(secondStartedTooEarly)

        await finishFirst.open()
        let resolvedFirstResult = try await firstResult
        // The queued same-owner request advances the coordinator generation,
        // so the first caller conservatively reports that it was superseded.
        XCTAssertFalse(resolvedFirstResult)
        while !(await secondStarted.isCompleted) {
            await Task.yield()
        }

        currentOwnerID = newestOwnerID
        async let boundaryResult: RecipeIntentDonationBoundaryCoordinator.ReconciliationResult = {
            let result = await coordinator.reconcile(currentOwnerID: newestOwnerID)
            await boundaryCompleted.markCompleted()
            return result
        }()
        await Task.yield()
        let boundaryCompletedTooEarly = await boundaryCompleted.isCompleted
        XCTAssertFalse(boundaryCompletedTooEarly)

        await finishSecond.open()
        let resolvedSecondResult = try await secondResult
        let resolvedBoundaryResult = await boundaryResult
        XCTAssertFalse(resolvedSecondResult)
        XCTAssertEqual(resolvedBoundaryResult, .deleted)
        XCTAssertEqual(
            deletionAttempts,
            [
                .startCookingRecipe,
                .addRecipeIngredientsToGroceries,
                .startCookingRecipe,
                .addRecipeIngredientsToGroceries
            ]
        )
    }

    private func makeDonationDefaults() -> UserDefaults {
        let suiteName = "RecipeIntentEntityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeRecipe(
        title: String,
        ingredients: [String],
        tags: [String] = [],
        notes: String? = nil,
        totalMinutes: Int? = 30,
        isFavorite: Bool = false
    ) -> Recipe {
        Recipe(
            title: title,
            ingredients: ingredients.map { Ingredient(name: $0) },
            steps: [
                CookStep(index: 0, text: "Boil pasta"),
                CookStep(index: 1, text: "Finish the dish")
            ],
            yields: "2 servings",
            totalMinutes: totalMinutes,
            tags: tags.map { Tag(name: $0) },
            notes: notes,
            isFavorite: isFavorite,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor AsyncCompletionProbe {
    private(set) var isCompleted = false

    func markCompleted() {
        isCompleted = true
    }
}
