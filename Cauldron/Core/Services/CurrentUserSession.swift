//
//  CurrentUserSession.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import SwiftUI
import os
import Combine
import CloudKit

/// Captures the iCloud-account revision that an async local mutation began in.
nonisolated struct AccountIdentityMutationToken: Equatable, Sendable {
    fileprivate let revision: UInt64
}

/// Binds an account-scoped mutation to both the verified identity generation
/// and the user that owned the data when the work began.
nonisolated struct VerifiedAccountMutationContext: Equatable, Sendable {
    let ownerID: UUID
    fileprivate let token: AccountIdentityMutationToken

#if DEBUG
    static func testing(ownerID: UUID, revision: UInt64 = 0) -> Self {
        Self(ownerID: ownerID, token: AccountIdentityMutationToken(revision: revision))
    }
#endif
}

private struct PendingProfileSyncSnapshot: Codable, Sendable {
    let transactionID: UUID
    let user: User
    let requiresAvatarReconciliation: Bool
    let stagedImageURL: URL?
    let previousLocalRevision: UUID?

    init(
        transactionID: UUID,
        user: User,
        requiresAvatarReconciliation: Bool,
        stagedImageURL: URL?,
        previousLocalRevision: UUID?
    ) {
        self.transactionID = transactionID
        self.user = user
        self.requiresAvatarReconciliation = requiresAvatarReconciliation
        self.stagedImageURL = stagedImageURL
        self.previousLocalRevision = previousLocalRevision
    }

    private enum CodingKeys: String, CodingKey {
        case transactionID
        case user
        case requiresAvatarReconciliation
        case stagedImageURL
        case previousLocalRevision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transactionID = try container.decode(UUID.self, forKey: .transactionID)
        user = try container.decode(User.self, forKey: .user)
        requiresAvatarReconciliation = try container.decodeIfPresent(
            Bool.self,
            forKey: .requiresAvatarReconciliation
        ) ?? true
        stagedImageURL = try container.decodeIfPresent(URL.self, forKey: .stagedImageURL)
        previousLocalRevision = try container.decodeIfPresent(UUID.self, forKey: .previousLocalRevision)
    }
}

private struct LegacyPendingProfileSyncSnapshot: Codable {
    let transactionID: UUID
    let user: User
}

struct ProfileAvatarMutationToken: Equatable, Sendable {
    fileprivate let ownerID: UUID
    fileprivate let revision: UInt64
}

struct ProfileBasicInfoMutationToken: Equatable, Sendable {
    fileprivate let ownerID: UUID
    fileprivate let revision: UInt64
}

struct ProfileBasicInfoMutationGate {
    private var revision: UInt64 = 0

    mutating func reserve(ownerID: UUID) -> ProfileBasicInfoMutationToken {
        revision &+= 1
        return ProfileBasicInfoMutationToken(ownerID: ownerID, revision: revision)
    }

    func permits(_ token: ProfileBasicInfoMutationToken, ownerID: UUID) -> Bool {
        token.ownerID == ownerID && token.revision == revision
    }
}

enum ProfileBasicInfoMergePolicy {
    static func mergingCapturedBasicInfo(
        username: String,
        displayName: String,
        whenAuthorized isAuthorized: Bool,
        into latestUser: User
    ) -> User {
        guard isAuthorized else { return latestUser }
        return latestUser.updatedBasicInfo(username: username, displayName: displayName)
    }
}

enum PendingProfileSyncMergePolicy {
    static func mergingBasicInfo(
        username: String,
        displayName: String,
        inheritedPendingUser: User?,
        visibleUser: User
    ) -> User {
        (inheritedPendingUser ?? visibleUser).updatedBasicInfo(
            username: username,
            displayName: displayName
        )
    }
}

struct ProfileAvatarState: Equatable, Sendable {
    let ownerID: UUID
    let emoji: String?
    let color: String?
    let imageURL: URL?
    let cloudRecordName: String?
    let modifiedAt: Date?
    let localRevision: UUID?

    init(user: User) {
        ownerID = user.id
        emoji = user.profileEmoji
        color = user.profileColor
        imageURL = user.profileImageURL
        cloudRecordName = user.cloudProfileImageRecordName
        modifiedAt = user.profileImageModifiedAt
        localRevision = user.profileImageLocalRevision
    }
}

/// A small generation gate that prevents identity work started for one iCloud
/// account state from authorizing or mutating data after another account change.
struct AccountIdentityVerificationGate {
    private(set) var revision: UInt64 = 0
    private var verifiedRevision: UInt64?

    var token: UInt64 { revision }
    var mutationToken: AccountIdentityMutationToken {
        AccountIdentityMutationToken(revision: revision)
    }
    var isVerified: Bool { verifiedRevision == revision }

    func permitsInitializationCommit(token: UInt64) -> Bool {
        token == revision
    }

    mutating func invalidate() {
        revision &+= 1
        verifiedRevision = nil
    }

    mutating func complete(token: UInt64) -> Bool {
        guard token == revision else { return false }
        verifiedRevision = token
        return true
    }

    func permitsMutation(token: AccountIdentityMutationToken) -> Bool {
        token.revision == revision
    }

    func mutationContext(ownerID: UUID) -> VerifiedAccountMutationContext? {
        guard isVerified else { return nil }
        return VerifiedAccountMutationContext(ownerID: ownerID, token: mutationToken)
    }

    func permitsMutation(
        context: VerifiedAccountMutationContext,
        currentOwnerID: UUID?
    ) -> Bool {
        isVerified
            && currentOwnerID == context.ownerID
            && permitsMutation(token: context.token)
    }
}

/// Merges only the result of a suspended image download into the newest user
/// value. Profile edits that completed while the download was in flight must
/// not be overwritten by the stale user snapshot that started the download.
enum ProfileImageRefreshMergePolicy {
    static func mergingDownloadedImage(
        _ imageURL: URL,
        localRevision: UUID? = nil,
        cloudSnapshot: User,
        into latestUser: User?
    ) -> User? {
        guard let latestUser,
              latestUser.id == cloudSnapshot.id,
              latestUser.profileEmoji == cloudSnapshot.profileEmoji,
              latestUser.profileColor == cloudSnapshot.profileColor,
              latestUser.profileImageURL == cloudSnapshot.profileImageURL,
              latestUser.profileImageLocalRevision == cloudSnapshot.profileImageLocalRevision,
              latestUser.cloudProfileImageRecordName == cloudSnapshot.cloudProfileImageRecordName,
              latestUser.profileImageModifiedAt == cloudSnapshot.profileImageModifiedAt else {
            return nil
        }
        return latestUser.updatedProfile(
            profileEmoji: latestUser.profileEmoji,
            profileColor: latestUser.profileColor,
            profileImageURL: imageURL,
            cloudProfileImageRecordName: cloudSnapshot.cloudProfileImageRecordName,
            profileImageModifiedAt: cloudSnapshot.profileImageModifiedAt,
            profileImageLocalRevision: localRevision
        )
    }
}

/// Manages the current user's session and authentication state
@MainActor
class CurrentUserSession: ObservableObject {
    static let shared = CurrentUserSession()

    @Published var currentUser: User?
    @Published var isInitialized = false
    @Published var needsOnboarding = false
    @Published var needsiCloudSignIn = false
    @Published var cloudKitAccountStatus: CloudKitAccountStatus?

    private let userIdKey = "currentUserId"
    private let usernameKey = "currentUsername"
    private let displayNameKey = "currentDisplayName"
    private let profileEmojiKey = "currentProfileEmoji"
    private let profileColorKey = "currentProfileColor"
    private let referralCodeKey = "currentReferralCode"
    private let cloudKitSystemRecordNameKey = "currentCloudKitSystemRecordName"
    private let hasCompletedLocalOnboardingKey = "hasCompletedLocalOnboarding"
    private let userSnapshotKey = "currentUserSnapshot.v1"
    private let pendingProfileSyncKey = "pendingProfileSync.v1"
    private let syncOperationAccountRevisionKey = "syncOperationAccountRevision.v1"
    private let logger = Logger(subsystem: "com.cauldron", category: "UserSession")
    private var refreshTask: Task<Void, Never>?
    private var initializationTask: Task<Void, Never>?
    private var accountReverificationTask: Task<Void, Never>?
    private var accountChangeObserver: NSObjectProtocol?
    private var identityVerificationGate = AccountIdentityVerificationGate()
    private var syncOperationAccountRevision: UUID
    private var profileAvatarMutationRevision: UInt64 = 0
    private var profileBasicInfoMutationGate = ProfileBasicInfoMutationGate()

    var userId: UUID? {
        currentUser?.id
    }

    var isCloudSyncAvailable: Bool {
        cloudKitAccountStatus?.isAvailable ?? false
    }

    /// Account-scoped consumers (including App Intents and Spotlight) must use
    /// this stronger gate instead of trusting a cached user ID alone.
    var isAccountIdentityVerified: Bool {
        isInitialized && identityVerificationGate.isVerified
    }

    func verifiedMutationContext(ownerID: UUID) -> VerifiedAccountMutationContext? {
        guard isInitialized, currentUser?.id == ownerID else { return nil }
        return identityVerificationGate.mutationContext(ownerID: ownerID)
    }

    /// Durable generation used by the offline operation queue. Unlike the
    /// in-memory verification token, this survives a relaunch and rotates at
    /// every observed account boundary.
    func syncOperationAccountScope(ownerID: UUID) -> SyncOperationAccountScope? {
        guard isAccountIdentityVerified,
              currentUser?.id == ownerID,
              let cloudKitIdentity = UserDefaults.standard.string(forKey: cloudKitSystemRecordNameKey),
              !cloudKitIdentity.isEmpty else { return nil }
        return SyncOperationAccountScope(
            ownerId: ownerID,
            revision: syncOperationAccountRevision,
            cloudKitIdentity: cloudKitIdentity
        )
    }

    func permitsMutation(_ context: VerifiedAccountMutationContext) -> Bool {
        isInitialized && identityVerificationGate.permitsMutation(
            context: context,
            currentOwnerID: currentUser?.id
        )
    }

    func permitsMutation(_ token: AccountIdentityMutationToken) -> Bool {
        isInitialized && identityVerificationGate.permitsMutation(token: token)
    }

    private func permitsPendingProfileMutation(
        token: AccountIdentityMutationToken,
        ownerID: UUID,
        transactionID: UUID
    ) -> Bool {
        permitsMutation(token)
            && currentUser?.id == ownerID
            && restorePendingProfileSync(transactionID: transactionID)?.user.id == ownerID
    }

    func permitsMutation(
        _ context: VerifiedAccountMutationContext,
        whileCurrentUserIs expectedUser: User
    ) -> Bool {
        permitsMutation(context) && currentUser == expectedUser
    }

    func reserveProfileAvatarMutation(
        context: VerifiedAccountMutationContext,
        replacing expectedUser: User
    ) -> ProfileAvatarMutationToken? {
        guard permitsMutation(context),
              let currentUser,
              Self.avatarStateMatches(currentUser, expectedUser) else {
            return nil
        }
        profileAvatarMutationRevision &+= 1
        return ProfileAvatarMutationToken(ownerID: context.ownerID, revision: profileAvatarMutationRevision)
    }

    func reserveProfileBasicInfoMutation(
        context: VerifiedAccountMutationContext,
        replacing expectedUser: User
    ) -> ProfileBasicInfoMutationToken? {
        guard permitsMutation(context, whileCurrentUserIs: expectedUser) else { return nil }
        return profileBasicInfoMutationGate.reserve(ownerID: context.ownerID)
    }

    func permitsProfileBasicInfoMutation(
        _ token: ProfileBasicInfoMutationToken,
        context: VerifiedAccountMutationContext
    ) -> Bool {
        profileBasicInfoMutationGate.permits(token, ownerID: context.ownerID)
            && permitsMutation(context)
    }

    func permitsProfileAvatarMutation(
        _ token: ProfileAvatarMutationToken,
        context: VerifiedAccountMutationContext,
        whileAvatarMatches expectedUser: User
    ) -> Bool {
        guard token.ownerID == context.ownerID,
              token.revision == profileAvatarMutationRevision,
              permitsMutation(context),
              let currentUser else {
            return false
        }
        return Self.avatarStateMatches(currentUser, expectedUser)
    }

    func userByMergingAuthorizedAvatar(
        context: VerifiedAccountMutationContext,
        token: ProfileAvatarMutationToken,
        whileAvatarMatches expectedUser: User,
        profileEmoji: String?,
        profileColor: String?,
        profileImageURL: URL?,
        cloudProfileImageRecordName: String?,
        profileImageModifiedAt: Date?,
        profileImageLocalRevision: UUID?,
        basicInfoToken: ProfileBasicInfoMutationToken? = nil,
        username: String? = nil,
        displayName: String? = nil
    ) -> User? {
        guard permitsProfileAvatarMutation(
            token,
            context: context,
            whileAvatarMatches: expectedUser
        ), let currentUser else {
            return nil
        }
        let avatarUser = currentUser.updatedProfile(
            profileEmoji: profileEmoji,
            profileColor: profileColor,
            profileImageURL: profileImageURL,
            cloudProfileImageRecordName: cloudProfileImageRecordName,
            profileImageModifiedAt: profileImageModifiedAt,
            profileImageLocalRevision: profileImageLocalRevision
        )
        guard let username, let displayName else { return avatarUser }
        let isAuthorized = basicInfoToken.map {
            permitsProfileBasicInfoMutation($0, context: context)
        } ?? false
        return ProfileBasicInfoMergePolicy.mergingCapturedBasicInfo(
            username: username,
            displayName: displayName,
            whenAuthorized: isAuthorized,
            into: avatarUser
        )
    }

    @discardableResult
    func commitAuthorizedAvatar(
        context: VerifiedAccountMutationContext,
        token: ProfileAvatarMutationToken,
        whileAvatarMatches expectedUser: User,
        profileEmoji: String?,
        profileColor: String?,
        profileImageURL: URL?,
        cloudProfileImageRecordName: String?,
        profileImageModifiedAt: Date?,
        profileImageLocalRevision: UUID?,
        basicInfoToken: ProfileBasicInfoMutationToken? = nil,
        username: String? = nil,
        displayName: String? = nil
    ) -> User? {
        guard let updatedUser = userByMergingAuthorizedAvatar(
            context: context,
            token: token,
            whileAvatarMatches: expectedUser,
            profileEmoji: profileEmoji,
            profileColor: profileColor,
            profileImageURL: profileImageURL,
            cloudProfileImageRecordName: cloudProfileImageRecordName,
            profileImageModifiedAt: profileImageModifiedAt,
            profileImageLocalRevision: profileImageLocalRevision,
            basicInfoToken: basicInfoToken,
            username: username,
            displayName: displayName
        ) else { return nil }
        saveUserToDefaults(updatedUser)
        replaceCurrentUserIfChanged(updatedUser)
        return updatedUser
    }

    func commitAuthorizedAvatarWithPendingSync(
        context: VerifiedAccountMutationContext,
        token: ProfileAvatarMutationToken,
        whileAvatarMatches expectedUser: User,
        profileEmoji: String?,
        profileColor: String?,
        profileImageURL: URL?,
        cloudProfileImageRecordName: String?,
        profileImageModifiedAt: Date?,
        profileImageLocalRevision: UUID?,
        basicInfoToken: ProfileBasicInfoMutationToken? = nil,
        username: String? = nil,
        displayName: String? = nil
    ) -> (user: User, transactionID: UUID, supersededStagedImageURL: URL?)? {
        guard let updatedUser = userByMergingAuthorizedAvatar(
            context: context,
            token: token,
            whileAvatarMatches: expectedUser,
            profileEmoji: profileEmoji,
            profileColor: profileColor,
            profileImageURL: profileImageURL,
            cloudProfileImageRecordName: cloudProfileImageRecordName,
            profileImageModifiedAt: profileImageModifiedAt,
            profileImageLocalRevision: profileImageLocalRevision,
            basicInfoToken: basicInfoToken,
            username: username,
            displayName: displayName
        ) else { return nil }
        let supersededStagedImageURL = restorePendingProfileSync(ownerID: updatedUser.id)?.stagedImageURL
        let transactionID = beginPendingProfileSync(
            updatedUser,
            requiresAvatarReconciliation: true,
            stagedImageURL: nil,
            previousLocalRevision: expectedUser.profileImageLocalRevision
        )
        saveUserToDefaults(updatedUser)
        replaceCurrentUserIfChanged(updatedUser)
        return (updatedUser, transactionID, supersededStagedImageURL)
    }

    func prepareAuthorizedAvatarPendingSync(
        context: VerifiedAccountMutationContext,
        replacing expectedUser: User,
        profileImageURL: URL,
        profileImageLocalRevision: UUID,
        stagedImageURL: URL,
        username: String?,
        displayName: String?
    ) -> (user: User, transactionID: UUID, supersededStagedImageURL: URL?)? {
        guard permitsMutation(context, whileCurrentUserIs: expectedUser) else { return nil }
        let baseUser: User
        if let username, let displayName {
            baseUser = expectedUser.updatedBasicInfo(username: username, displayName: displayName)
        } else {
            baseUser = expectedUser
        }
        let updatedUser = baseUser.updatedProfile(
            profileEmoji: nil,
            profileColor: nil,
            profileImageURL: profileImageURL,
            // A newly authored local image must not inherit the previous
            // CloudKit revision. Keeping that metadata would reuse the old
            // cloud-derived cache key and briefly show stale pixels while the
            // replacement upload is still pending.
            cloudProfileImageRecordName: nil,
            profileImageModifiedAt: nil,
            profileImageLocalRevision: profileImageLocalRevision
        )
        let supersededStagedImageURL = restorePendingProfileSync(ownerID: updatedUser.id)?.stagedImageURL
        let transactionID = beginPendingProfileSync(
            updatedUser,
            requiresAvatarReconciliation: true,
            stagedImageURL: stagedImageURL,
            previousLocalRevision: expectedUser.profileImageLocalRevision
        )
        return (updatedUser, transactionID, supersededStagedImageURL)
    }

    func publishAuthorizedAvatarPendingSync(
        transactionID: UUID,
        context: VerifiedAccountMutationContext,
        token: ProfileAvatarMutationToken,
        whileAvatarMatches expectedUser: User,
        profileImageURL: URL,
        profileImageLocalRevision: UUID,
        basicInfoToken: ProfileBasicInfoMutationToken?,
        username: String?,
        displayName: String?
    ) -> User? {
        guard let updatedUser = userByMergingAuthorizedAvatar(
            context: context,
            token: token,
            whileAvatarMatches: expectedUser,
            profileEmoji: nil,
            profileColor: nil,
            profileImageURL: profileImageURL,
            cloudProfileImageRecordName: nil,
            profileImageModifiedAt: nil,
            profileImageLocalRevision: profileImageLocalRevision,
            basicInfoToken: basicInfoToken,
            username: username,
            displayName: displayName
        ), var pending = restorePendingProfileSync(transactionID: transactionID) else {
            return nil
        }
        pending = PendingProfileSyncSnapshot(
            transactionID: pending.transactionID,
            user: updatedUser,
            requiresAvatarReconciliation: true,
            stagedImageURL: pending.stagedImageURL,
            previousLocalRevision: pending.previousLocalRevision
        )
        var snapshots = restorePendingProfileSyncQueue()
        snapshots[updatedUser.id.uuidString] = pending
        persistPendingProfileSyncQueue(snapshots)
        saveUserToDefaults(updatedUser)
        replaceCurrentUserIfChanged(updatedUser)
        return updatedUser
    }

    func userByMergingAuthorizedBasicInfo(
        context: VerifiedAccountMutationContext,
        token: ProfileBasicInfoMutationToken,
        username: String,
        displayName: String
    ) -> User? {
        guard permitsProfileBasicInfoMutation(token, context: context),
              let currentUser else {
            return nil
        }
        return currentUser.updatedBasicInfo(
            username: username,
            displayName: displayName
        )
    }


    @discardableResult
    func commitAuthorizedBasicInfo(
        context: VerifiedAccountMutationContext,
        token: ProfileBasicInfoMutationToken,
        username: String,
        displayName: String
    ) -> User? {
        guard let updatedUser = userByMergingAuthorizedBasicInfo(
            context: context,
            token: token,
            username: username,
            displayName: displayName
        ) else { return nil }
        saveUserToDefaults(updatedUser)
        replaceCurrentUserIfChanged(updatedUser)
        return updatedUser
    }

    func commitAuthorizedBasicInfoWithPendingSync(
        context: VerifiedAccountMutationContext,
        token: ProfileBasicInfoMutationToken,
        username: String,
        displayName: String
    ) -> (user: User, transactionID: UUID)? {
        guard let updatedUser = userByMergingAuthorizedBasicInfo(
            context: context,
            token: token,
            username: username,
            displayName: displayName
        ) else { return nil }
        let inheritedPending = restorePendingProfileSync(ownerID: updatedUser.id)
        let pendingUser = PendingProfileSyncMergePolicy.mergingBasicInfo(
            username: username,
            displayName: displayName,
            inheritedPendingUser: inheritedPending?.user,
            visibleUser: updatedUser
        )
        let transactionID = beginPendingProfileSync(
            pendingUser,
            requiresAvatarReconciliation: inheritedPending?.requiresAvatarReconciliation ?? false,
            stagedImageURL: inheritedPending?.stagedImageURL,
            previousLocalRevision: inheritedPending?.previousLocalRevision
        )
        saveUserToDefaults(updatedUser)
        replaceCurrentUserIfChanged(updatedUser)
        return (updatedUser, transactionID)
    }

    private static func avatarStateMatches(_ lhs: User, _ rhs: User) -> Bool {
        ProfileAvatarState(user: lhs) == ProfileAvatarState(user: rhs)
    }

    private init() {
        if let rawRevision = UserDefaults.standard.string(forKey: syncOperationAccountRevisionKey),
           let revision = UUID(uuidString: rawRevision) {
            syncOperationAccountRevision = revision
        } else {
            let revision = UUID()
            syncOperationAccountRevision = revision
            UserDefaults.standard.set(revision.uuidString, forKey: syncOperationAccountRevisionKey)
        }
        accountChangeObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleCloudAccountChanged()
            }
        }
    }

    /// Fetch CloudKit user with retry logic for network reliability
    private func fetchCloudUserWithRetry(dependencies: DependencyContainer, maxAttempts: Int = 3) async throws -> User? {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                // Only log on retries (not first attempt)
                if attempt > 1 {
                    logger.info("Retrying CloudKit user profile fetch (attempt \(attempt)/\(maxAttempts))")
                }
                let user = try await dependencies.userCloudService.fetchCurrentUserProfile()
                return user
            } catch {
                lastError = error
                logger.warning("Failed to fetch CloudKit user (attempt \(attempt)/\(maxAttempts)): \(error.localizedDescription)")

                // Don't retry if it's a definitive "no account" error
                if let cloudKitError = error as? CloudKitError,
                   case .accountNotAvailable = cloudKitError {
                    logger.info("Account not available - no need to retry")
                    return nil
                }

                // Wait before retrying (exponential backoff)
                if attempt < maxAttempts {
                    let delay = UInt64(pow(2.0, Double(attempt - 1)) * 500_000_000) // 0.5s, 1s, 2s
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }

        // All retries failed
        if let error = lastError {
            logger.error("All CloudKit fetch attempts failed: \(error.localizedDescription)")
            throw error
        }

        return nil
    }

    /// Initialize user session on app launch
    func initialize(dependencies: DependencyContainer) async {
        if let initializationTask {
            await initializationTask.value
            return
        }

        let identityToken = identityVerificationGate.token
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performInitialization(
                dependencies: dependencies,
                identityToken: identityToken
            )
        }
        initializationTask = task
        await task.value
        if identityVerificationGate.token == identityToken {
            initializationTask = nil
        }
    }

    /// App Intents may launch before the SwiftUI scene. This provides the same
    /// verified CloudKit identity gate without starting duplicate initialization.
    func ensureInitialized(dependencies: DependencyContainer) async {
        guard !isAccountIdentityVerified else { return }
        await initialize(dependencies: dependencies)
    }

    private func performInitialization(
        dependencies: DependencyContainer,
        identityToken: UInt64
    ) async {
        let mutationToken = AccountIdentityMutationToken(revision: identityToken)
        #if DEBUG
        if RuntimeEnvironment.isSimulatorQAMode {
            SimulatorQASeed.configureUserSession(self)
            completeInitialization(identityToken: identityToken)
            return
        }
        #endif

        ReferralManager.shared.configure(userCloudService: dependencies.userCloudService, connectionCloudService: dependencies.connectionCloudService)

        // Verify the active iCloud identity before exposing account-scoped local
        // data. Only the identity lookup is on the readiness path; images,
        // subscriptions, and referral counts remain background work.
        if let localUser = restoreUserFromDefaults() {
            let accountStatus = await dependencies.cloudKitCore.checkAccountStatus()
            guard identityVerificationGate.token == identityToken else { return }
            cloudKitAccountStatus = accountStatus

            if accountStatus.isAvailable {
                var verifiedSystemRecordName: String?
                do {
                    let systemRecordID = try await dependencies.cloudKitCore.getCurrentUserRecordID()
                    let systemRecordName = systemRecordID.recordName
                    guard identityVerificationGate.token == identityToken else { return }
                    verifiedSystemRecordName = systemRecordName
                    if let cloudUser = try await dependencies.userCloudService.fetchCurrentUserProfile(
                        verifiedSystemRecordID: systemRecordID
                    ) {
                        guard identityVerificationGate.token == identityToken else { return }
                        let pendingProfile = restorePendingProfileSync(ownerID: cloudUser.id)
                        let effectiveUser = pendingProfile?.user ?? cloudUser
                        currentUser = effectiveUser
                        saveUserToDefaults(effectiveUser)
                        UserDefaults.standard.set(systemRecordName, forKey: cloudKitSystemRecordNameKey)
                        guard completeInitialization(identityToken: identityToken) else { return }
                        needsOnboarding = false
                        needsiCloudSignIn = false

                        refreshTask?.cancel()
                        refreshTask = Task { [weak self] in
                            if let pendingProfile {
                                await self?.reconcilePendingProfileSync(
                                    pendingProfile,
                                    cloudUser: cloudUser,
                                    dependencies: dependencies,
                                    mutationToken: mutationToken
                                )
                            }
                            await self?.finishVerifiedUserRefresh(effectiveUser, dependencies: dependencies)
                        }
                        return
                    }

                    // The active iCloud account has no Cauldron profile. Do not
                    // reveal the previous account's locally cached library.
                    currentUser = nil
                    guard completeInitialization(identityToken: identityToken) else { return }
                    needsOnboarding = true
                    needsiCloudSignIn = false
                    return
                } catch {
                    // Cancellation is delivered as an error. An initialization
                    // started for the previous iCloud generation must not mutate
                    // the newly verified session before completeInitialization
                    // gets a chance to reject its stale token.
                    guard identityVerificationGate.permitsInitializationCommit(token: identityToken) else {
                        return
                    }
                    let storedRecordName = UserDefaults.standard.string(forKey: cloudKitSystemRecordNameKey)
                    guard let verifiedSystemRecordName,
                          storedRecordName == verifiedSystemRecordName else {
                        logger.error("Could not safely verify iCloud identity: \(error.localizedDescription)")
                        currentUser = nil
                        guard completeInitialization(identityToken: identityToken) else { return }
                        needsOnboarding = false
                        needsiCloudSignIn = true
                        return
                    }
                    logger.warning("Verified cached iCloud identity; using offline local session: \(error.localizedDescription)")
                    currentUser = localUser
                    guard completeInitialization(identityToken: identityToken) else { return }
                    needsOnboarding = false
                    needsiCloudSignIn = false
                    return
                }
            }

            // Account-scoped local data remains locked until the active CloudKit
            // identity is positively verified. Ambiguous availability cannot prove
            // that the device has not switched iCloud accounts since last launch.
            currentUser = nil
            guard completeInitialization(identityToken: identityToken) else { return }
            needsOnboarding = false
            needsiCloudSignIn = true
            return
        }

        // Step 1: Check iCloud account status
        let accountStatus = await dependencies.cloudKitCore.checkAccountStatus()
        guard identityVerificationGate.token == identityToken else { return }
        cloudKitAccountStatus = accountStatus

        // Step 2: Try to fetch existing user from CloudKit if available (with retries)
        if accountStatus.isAvailable {
            if let cloudUser = try? await fetchCloudUserWithRetry(dependencies: dependencies) {
                guard identityVerificationGate.token == identityToken else { return }
                // Found existing user in CloudKit - use it
                currentUser = cloudUser
                saveUserToDefaults(cloudUser)
                await persistCurrentCloudIdentity(
                    dependencies: dependencies,
                    mutationToken: mutationToken
                )
                guard identityVerificationGate.token == identityToken else { return }

                // Download profile image from CloudKit if it exists and local copy is missing
                await downloadProfileImageIfNeeded(
                    for: cloudUser,
                    dependencies: dependencies,
                    mutationToken: mutationToken
                )
                guard identityVerificationGate.token == identityToken else { return }

                // Set up push notification subscription for connection requests
                await setupNotificationSubscription(for: cloudUser.id, dependencies: dependencies)
                guard identityVerificationGate.token == identityToken else { return }

                await syncReferralCountIfNeeded(
                    for: cloudUser,
                    dependencies: dependencies,
                    mutationToken: mutationToken
                )
                guard identityVerificationGate.token == identityToken else { return }

                guard completeInitialization(identityToken: identityToken) else { return }
                needsOnboarding = false
                needsiCloudSignIn = false
                return
            }
        }

        // Step 3: Check local storage for existing user
        if let localUser = restoreUserFromDefaults() {
            currentUser = localUser

            // If iCloud is available, try to sync
            if accountStatus.isAvailable {
                do {
                    let cloudUser = try await dependencies.userCloudService.fetchOrCreateCurrentUser(
                        username: localUser.username,
                        displayName: localUser.displayName,
                        profileEmoji: localUser.profileEmoji,
                        profileColor: localUser.profileColor
                    )
                    guard identityVerificationGate.token == identityToken else { return }
                    currentUser = cloudUser
                    saveUserToDefaults(cloudUser)
                    await persistCurrentCloudIdentity(
                        dependencies: dependencies,
                        mutationToken: mutationToken
                    )
                    guard identityVerificationGate.token == identityToken else { return }

                    // Download profile image from CloudKit if it exists and local copy is missing
                    await downloadProfileImageIfNeeded(
                        for: cloudUser,
                        dependencies: dependencies,
                        mutationToken: mutationToken
                    )
                    guard identityVerificationGate.token == identityToken else { return }

                    // Set up push notification subscription
                    await setupNotificationSubscription(for: cloudUser.id, dependencies: dependencies)
                    guard identityVerificationGate.token == identityToken else { return }

                    logger.info("Synced local user to CloudKit successfully")
                } catch {
                    logger.warning("CloudKit sync failed: \(error.localizedDescription)")
                    // Continue with local user
                }
            }

            if let currentUser = currentUser {
                await syncReferralCountIfNeeded(
                    for: currentUser,
                    dependencies: dependencies,
                    mutationToken: mutationToken
                )
                guard identityVerificationGate.token == identityToken else { return }
            }

            guard completeInitialization(identityToken: identityToken) else { return }
            needsOnboarding = false
            needsiCloudSignIn = false
        } else {
            // Step 4: No existing user - determine what to show
            if accountStatus.isAvailable {
                // iCloud available but no user profile - show onboarding
                logger.info("No existing user - showing onboarding")
                guard completeInitialization(identityToken: identityToken) else { return }
                needsOnboarding = true
                needsiCloudSignIn = false
            } else {
                // iCloud not available - show iCloud sign-in prompt (required for Cauldron)
                logger.info("iCloud not available - showing sign-in prompt (status: \(String(describing: accountStatus)))")
                guard completeInitialization(identityToken: identityToken) else { return }
                needsOnboarding = false
                needsiCloudSignIn = true
            }
        }
    }

    @discardableResult
    private func completeInitialization(identityToken: UInt64) -> Bool {
        guard identityVerificationGate.complete(token: identityToken) else { return false }
        isInitialized = true
        return true
    }

    /// CloudKit posts this notification for live sign-in, sign-out, and account
    /// switches. Invalidate synchronously before starting network verification so
    /// no recipe query can use the prior account's cached identity in the gap.
    private func handleCloudAccountChanged() {
        logger.notice("CloudKit account changed; locking account-scoped data pending verification")

        identityVerificationGate.invalidate()
        rotateSyncOperationAccountRevision()
        profileAvatarMutationRevision &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        initializationTask?.cancel()
        initializationTask = nil
        accountReverificationTask?.cancel()

        currentUser = nil
        isInitialized = false
        needsOnboarding = false
        needsiCloudSignIn = false
        cloudKitAccountStatus = nil

        accountReverificationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.initialize(dependencies: .shared)
        }
    }

    private func rotateSyncOperationAccountRevision() {
        let revision = UUID()
        syncOperationAccountRevision = revision
        UserDefaults.standard.set(revision.uuidString, forKey: syncOperationAccountRevisionKey)
    }

    private func restoreUserFromDefaults() -> User? {
        guard let userIdString = UserDefaults.standard.string(forKey: userIdKey),
              let userId = UUID(uuidString: userIdString),
              let username = UserDefaults.standard.string(forKey: usernameKey),
              let displayName = UserDefaults.standard.string(forKey: displayNameKey) else {
            return nil
        }

        if let data = UserDefaults.standard.data(forKey: userSnapshotKey),
           let snapshot = try? JSONDecoder().decode(User.self, from: data),
           snapshot.id == userId {
            return snapshot
        }

        return User(
            id: userId,
            username: username,
            displayName: displayName,
            referralCode: UserDefaults.standard.string(forKey: referralCodeKey),
            profileEmoji: UserDefaults.standard.string(forKey: profileEmojiKey),
            profileColor: UserDefaults.standard.string(forKey: profileColorKey)
        )
    }

    private func finishVerifiedUserRefresh(_ cloudUser: User, dependencies: DependencyContainer) async {
        guard !Task.isCancelled, currentUser?.id == cloudUser.id else { return }
        let mutationToken = identityVerificationGate.mutationToken

        async let profileImage: Void = downloadProfileImageIfNeeded(
            for: cloudUser,
            dependencies: dependencies,
            mutationToken: mutationToken
        )
        async let subscriptions: Void = setupNotificationSubscription(for: cloudUser.id, dependencies: dependencies)
        async let referralCount: Void = syncReferralCountIfNeeded(
            for: cloudUser,
            dependencies: dependencies,
            mutationToken: mutationToken
        )
        _ = await (profileImage, subscriptions, referralCount)
    }

    /// Save user data to UserDefaults
    private func saveUserToDefaults(_ user: User) {
        UserDefaults.standard.set(user.id.uuidString, forKey: userIdKey)
        UserDefaults.standard.set(user.username, forKey: usernameKey)
        UserDefaults.standard.set(user.displayName, forKey: displayNameKey)
        UserDefaults.standard.set(user.profileEmoji, forKey: profileEmojiKey)
        UserDefaults.standard.set(user.profileColor, forKey: profileColorKey)
        UserDefaults.standard.set(user.referralCode, forKey: referralCodeKey)
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userSnapshotKey)
        }
    }

    func persistPendingProfileSync(_ user: User) -> UUID {
        let transactionID = beginPendingProfileSync(
            user,
            requiresAvatarReconciliation: true,
            stagedImageURL: nil,
            previousLocalRevision: user.profileImageLocalRevision
        )
        saveUserToDefaults(user)
        return transactionID
    }

    private func beginPendingProfileSync(
        _ user: User,
        requiresAvatarReconciliation: Bool,
        stagedImageURL: URL?,
        previousLocalRevision: UUID?
    ) -> UUID {
        let transactionID = UUID()
        let snapshot = PendingProfileSyncSnapshot(
            transactionID: transactionID,
            user: user,
            requiresAvatarReconciliation: requiresAvatarReconciliation,
            stagedImageURL: stagedImageURL,
            previousLocalRevision: previousLocalRevision
        )
        var snapshots = restorePendingProfileSyncQueue()
        snapshots[user.id.uuidString] = snapshot
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: pendingProfileSyncKey)
        }
        return transactionID
    }

    func clearPendingProfileSync(transactionID: UUID) {
        var snapshots = restorePendingProfileSyncQueue()
        guard let entry = snapshots.first(where: { $0.value.transactionID == transactionID }) else { return }
        snapshots.removeValue(forKey: entry.key)
        persistPendingProfileSyncQueue(snapshots)
    }

    func reconcilePendingProfileSync(
        transactionID: UUID,
        dependencies: DependencyContainer
    ) async {
        guard isAccountIdentityVerified,
              let pending = restorePendingProfileSync(transactionID: transactionID) else { return }
        let mutationToken = identityVerificationGate.mutationToken
        do {
            guard let cloudUser = try await dependencies.userCloudService.fetchCurrentUserProfile(),
                  cloudUser.id == pending.user.id,
                  identityVerificationGate.permitsMutation(token: mutationToken) else { return }
            await reconcilePendingProfileSync(
                pending,
                cloudUser: cloudUser,
                dependencies: dependencies,
                mutationToken: mutationToken
            )
        } catch {
            logger.warning("Pending profile sync remains queued: \(error.localizedDescription)")
        }
    }

    private func restorePendingProfileSyncQueue() -> [String: PendingProfileSyncSnapshot] {
        guard let data = UserDefaults.standard.data(forKey: pendingProfileSyncKey) else { return [:] }
        if let snapshots = try? JSONDecoder().decode(
                [String: PendingProfileSyncSnapshot].self,
                from: data
        ) {
            return snapshots
        }
        if let legacy = try? JSONDecoder().decode(LegacyPendingProfileSyncSnapshot.self, from: data) {
            return [
                legacy.user.id.uuidString: PendingProfileSyncSnapshot(
                    transactionID: legacy.transactionID,
                    user: legacy.user,
                    requiresAvatarReconciliation: true,
                    stagedImageURL: nil,
                    previousLocalRevision: legacy.user.profileImageLocalRevision
                )
            ]
        }
        return [:]
    }

    private func persistPendingProfileSyncQueue(
        _ snapshots: [String: PendingProfileSyncSnapshot]
    ) {
        guard !snapshots.isEmpty else {
            UserDefaults.standard.removeObject(forKey: pendingProfileSyncKey)
            return
        }
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: pendingProfileSyncKey)
        }
    }

    private func removePendingProfileSync(ownerID: UUID) {
        var snapshots = restorePendingProfileSyncQueue()
        snapshots.removeValue(forKey: ownerID.uuidString)
        persistPendingProfileSyncQueue(snapshots)
    }

    private func restorePendingProfileSync(
        ownerID: UUID? = nil,
        transactionID: UUID? = nil
    ) -> PendingProfileSyncSnapshot? {
        restorePendingProfileSyncQueue().values.first {
            (ownerID == nil || $0.user.id == ownerID)
                && (transactionID == nil || $0.transactionID == transactionID)
        }
    }

    private func reconcilePendingProfileSync(
        _ pending: PendingProfileSyncSnapshot,
        cloudUser: User,
        dependencies: DependencyContainer,
        mutationToken: AccountIdentityMutationToken
    ) async {
        guard identityVerificationGate.permitsMutation(token: mutationToken),
              restorePendingProfileSync(transactionID: pending.transactionID) != nil,
              cloudUser.id == pending.user.id,
              currentUser?.id == pending.user.id else { return }

        do {
            var synchronizedUser = pending.user
            if pending.requiresAvatarReconciliation,
               let localRevision = pending.user.profileImageLocalRevision,
               pending.user.profileImageURL != nil {
                if let stagedImageURL = pending.stagedImageURL {
                    let stagedImage = StagedImageReplacement(
                        url: stagedImageURL,
                        generation: localRevision
                    )
                    if FileManager.default.fileExists(atPath: stagedImageURL.path) {
                        _ = try await dependencies.profileImageManager.promoteStagedImage(
                            stagedImage,
                            userId: pending.user.id,
                            knownPreviousGeneration: pending.previousLocalRevision
                        )
                    }
                }
                let imageExists = await dependencies.profileImageManager.imageExists(userId: pending.user.id)
                guard imageExists else { return }
                await dependencies.profileImageManager.registerKnownLocalGeneration(
                    localRevision,
                    userId: pending.user.id
                )
                let outcome = try await dependencies.profileImageManager.uploadImageToCloud(
                    userId: pending.user.id,
                    expectedGeneration: localRevision,
                    authorization: { [weak self] in
                        await self?.permitsPendingProfileMutation(
                            token: mutationToken,
                            ownerID: pending.user.id,
                            transactionID: pending.transactionID
                        ) ?? false
                    }
                )
                guard case .uploaded(let recordName) = outcome else { return }
                synchronizedUser = pending.user.updatedProfile(
                    profileEmoji: nil,
                    profileColor: nil,
                    profileImageURL: pending.user.profileImageURL,
                    cloudProfileImageRecordName: recordName,
                    profileImageModifiedAt: Date(),
                    profileImageLocalRevision: localRevision
                )
            } else if pending.requiresAvatarReconciliation,
                      cloudUser.cloudProfileImageRecordName != nil {
                try await dependencies.profileImageManager.deleteImageFromCloud(
                    userId: pending.user.id,
                    authorization: { [weak self] in
                        await self?.permitsPendingProfileMutation(
                            token: mutationToken,
                            ownerID: pending.user.id,
                            transactionID: pending.transactionID
                        ) ?? false
                    }
                )
            }

            guard identityVerificationGate.permitsMutation(token: mutationToken),
                  restorePendingProfileSync(transactionID: pending.transactionID) != nil else { return }
            try await dependencies.userCloudService.saveUser(synchronizedUser)
            guard identityVerificationGate.permitsMutation(token: mutationToken),
                  restorePendingProfileSync(transactionID: pending.transactionID) != nil else { return }
            if let latestUser = currentUser,
               latestUser.id == pending.user.id {
                synchronizedUser = synchronizedUser.updatedBasicInfo(
                    username: latestUser.username,
                    displayName: latestUser.displayName
                )
            }
            saveUserToDefaults(synchronizedUser)
            replaceCurrentUserIfChanged(synchronizedUser)
            let didUpdateWebSnapshot = await dependencies.externalShareService.updateProfileShareMetadata(
                for: synchronizedUser
            )
            guard didUpdateWebSnapshot else { return }
            clearPendingProfileSync(transactionID: pending.transactionID)
            if let stagedImageURL = pending.stagedImageURL {
                await dependencies.profileImageManager.deleteStagedImage(
                    at: stagedImageURL,
                    userId: pending.user.id
                )
            }
        } catch {
            logger.warning("Pending profile sync remains queued for next launch: \(error.localizedDescription)")
        }
    }

    private func persistCurrentCloudIdentity(
        dependencies: DependencyContainer,
        mutationToken: AccountIdentityMutationToken
    ) async {
        guard let recordID = try? await dependencies.cloudKitCore.getCurrentUserRecordID() else { return }
        guard identityVerificationGate.permitsMutation(token: mutationToken) else { return }
        UserDefaults.standard.set(recordID.recordName, forKey: cloudKitSystemRecordNameKey)
    }

    private func requireCurrentMutation(_ token: AccountIdentityMutationToken) throws {
        guard identityVerificationGate.permitsMutation(token: token) else {
            throw UserSessionError.accountChanged
        }
    }

    func replaceCurrentUserIfChanged(_ updatedUser: User) {
        guard currentUser != updatedUser else { return }
        currentUser = updatedUser
    }

    /// Atomically commits an optimistic account-scoped profile mutation only
    /// while its verified owner and identity generation are still current.
    /// `expectedUser` also prevents an older background sync from overwriting a
    /// newer edit made in the same account generation.
    @discardableResult
    func commitCurrentUserIfAuthorized(
        _ updatedUser: User,
        context: VerifiedAccountMutationContext,
        replacing expectedUser: User? = nil
    ) -> Bool {
        guard permitsMutation(context),
              updatedUser.id == context.ownerID,
              expectedUser == nil || currentUser == expectedUser else {
            return false
        }
        saveUserToDefaults(updatedUser)
        replaceCurrentUserIfChanged(updatedUser)
        return true
    }

    /// Sync referral count from CloudKit for the current user when available
    private func syncReferralCountIfNeeded(
        for user: User,
        dependencies: DependencyContainer,
        mutationToken: AccountIdentityMutationToken
    ) async {
        guard cloudKitAccountStatus?.isAvailable == true else { return }

        do {
            let count = try await dependencies.userCloudService.fetchReferralCount(for: user.id)
            guard identityVerificationGate.permitsMutation(token: mutationToken),
                  currentUser?.id == user.id else { return }
            ReferralManager.shared.syncFromCloudKit(referralCount: count)
        } catch {
            logger.warning("Failed to sync referral count: \(error.localizedDescription)")
        }
    }

    /// Download profile image from CloudKit if it exists in cloud but not locally
    private func downloadProfileImageIfNeeded(
        for user: User,
        dependencies: DependencyContainer,
        mutationToken: AccountIdentityMutationToken
    ) async {
        // Only download if:
        // 1. User has a cloud profile image record
        // 2. Local image file doesn't exist
        guard user.cloudProfileImageRecordName != nil else {
            return
        }

        let imageExists = await dependencies.profileImageManager.imageExists(userId: user.id)
        guard !imageExists else {
            logger.info("Profile image already exists locally - skipping download")
            return
        }

        logger.info("Downloading profile image from CloudKit for user \(user.username)")

        do {
            if let downloaded = try await dependencies.profileImageManager.downloadImageFromCloudWithToken(userId: user.id) {
                guard identityVerificationGate.permitsMutation(token: mutationToken),
                      currentUser?.id == user.id else {
                    await dependencies.profileImageManager.deleteImageIfUnchanged(
                        userId: user.id,
                        savedFile: downloaded.file
                    )
                    return
                }
                guard let updatedUser = ProfileImageRefreshMergePolicy.mergingDownloadedImage(
                    downloaded.url,
                    localRevision: downloaded.file.generation,
                    cloudSnapshot: user,
                    into: currentUser
                ) else {
                    await dependencies.profileImageManager.deleteImageIfUnchanged(
                        userId: user.id,
                        savedFile: downloaded.file
                    )
                    return
                }
                replaceCurrentUserIfChanged(updatedUser)
                logger.info("✅ Downloaded and set profile image")
            } else {
                logger.info("No profile image found in CloudKit (record may be stale)")
            }
        } catch {
            logger.warning("Failed to download profile image: \(error.localizedDescription)")
            // Don't block user session if image download fails
        }
    }
    
    /// Create and save a new user during onboarding
    func createUser(
        username: String,
        displayName: String,
        profileEmoji: String? = nil,
        profileColor: String? = nil,
        profileImage: UIImage? = nil,
        dependencies: DependencyContainer
    ) async throws {
        logger.info("Creating new user: \(username)")
        let mutationToken = identityVerificationGate.mutationToken

        let userId = UUID()

        // Try to create in CloudKit first
        var cloudUser: User?
        do {
            cloudUser = try await dependencies.userCloudService.fetchOrCreateCurrentUser(
                username: username,
                displayName: displayName,
                profileEmoji: profileImage == nil ? profileEmoji : nil,  // Clear emoji if using photo
                profileColor: profileColor
            )
            logger.info("User created in CloudKit")
        } catch CloudKitError.usernameUnavailable {
            logger.warning("Username is already reserved by another iCloud account")
            throw CloudKitError.usernameUnavailable
        } catch {
            logger.warning("CloudKit user creation failed (ok if not enabled): \(error.localizedDescription)")
            // Continue with local user
        }
        try requireCurrentMutation(mutationToken)

        // Use CloudKit user if available, otherwise create local
        let baseUser = cloudUser ?? User(
            id: userId,
            username: username,
            displayName: displayName,
            profileEmoji: profileImage == nil ? profileEmoji : nil,  // Clear emoji if using photo
            profileColor: profileColor,
            profileImageURL: nil
        )
        var user = baseUser

        if let profileImage {
            let profileImageURL = try await dependencies.profileImageManager.saveImage(profileImage, userId: baseUser.id)
            try requireCurrentMutation(mutationToken)
            logger.info("Saved profile image locally")

            var cloudProfileImageRecordName = baseUser.cloudProfileImageRecordName
            var profileImageModifiedAt = baseUser.profileImageModifiedAt

            if cloudUser != nil {
                do {
                    cloudProfileImageRecordName = try await dependencies.profileImageManager.uploadImageToCloud(
                        userId: baseUser.id,
                        authorization: { [weak self] in
                            await self?.permitsMutation(mutationToken) ?? false
                        }
                    )
                    try requireCurrentMutation(mutationToken)
                    profileImageModifiedAt = Date()
                    logger.info("Uploaded profile image to CloudKit: \(cloudProfileImageRecordName ?? "")")
                } catch UserSessionError.accountChanged {
                    throw UserSessionError.accountChanged
                } catch {
                    logger.warning("Failed to upload profile image to CloudKit: \(error.localizedDescription)")
                    // Continue - local image is still available
                }
            }

            user = baseUser.updatedProfile(
                profileEmoji: nil,
                profileColor: profileColor,
                profileImageURL: profileImageURL,
                cloudProfileImageRecordName: cloudProfileImageRecordName,
                profileImageModifiedAt: profileImageModifiedAt
            )

            if cloudUser != nil, cloudProfileImageRecordName != nil {
                do {
                    try await dependencies.userCloudService.saveUser(user)
                    try requireCurrentMutation(mutationToken)
                } catch UserSessionError.accountChanged {
                    throw UserSessionError.accountChanged
                } catch {
                    logger.warning("Failed to update CloudKit user profile image metadata: \(error.localizedDescription)")
                }
            }
        }

        // Resolve the active CloudKit identity before committing account-scoped
        // local state. A CKAccountChanged received during this await invalidates
        // the token and leaves the previous defaults untouched.
        await persistCurrentCloudIdentity(
            dependencies: dependencies,
            mutationToken: mutationToken
        )
        try requireCurrentMutation(mutationToken)
        guard identityVerificationGate.complete(token: mutationToken.revision) else {
            throw UserSessionError.accountChanged
        }
        saveUserToDefaults(user)

        currentUser = user
        isInitialized = true
        needsOnboarding = false
        needsiCloudSignIn = false

        // Set up push notification subscription for new user
        await setupNotificationSubscription(for: user.id, dependencies: dependencies)

        logger.info("User session created successfully")
    }

    /// Set up CloudKit push notification subscriptions for connection requests and shared recipes
    private func setupNotificationSubscription(for userId: UUID, dependencies: DependencyContainer) async {
        // Subscribe to connection requests
        do {
            try await dependencies.connectionCloudService.subscribeToConnectionRequests(forUserId: userId)
        } catch {
            logger.warning("Failed to set up connection request notifications: \(error.localizedDescription)")
            // Don't block user flow if subscription fails
        }

        // Subscribe to connection acceptances
        do {
            try await dependencies.connectionCloudService.subscribeToConnectionAcceptances(forUserId: userId)
        } catch {
            logger.warning("Failed to set up connection acceptance notifications: \(error.localizedDescription)")
            // Don't block user flow if subscription fails
        }

        // Subscribe to referral signups (when someone uses your referral code)
        do {
            try await dependencies.connectionCloudService.subscribeToReferralSignups(forUserId: userId)
        } catch {
            logger.warning("Failed to set up referral signup notifications: \(error.localizedDescription)")
            // Don't block user flow if subscription fails
        }
    }
    
    /// Update user profile
    func updateUser(
        username: String,
        displayName: String,
        profileEmoji: String? = nil,
        profileColor: String? = nil,
        dependencies: DependencyContainer
    ) async throws {
        guard let currentUser = currentUser else {
            throw UserSessionError.notAuthenticated
        }
        let mutationToken = identityVerificationGate.mutationToken

        logger.info("Updating user profile: \(username)")

        let updatedUser = User(
            id: currentUser.id,
            username: username,
            displayName: displayName,
            email: currentUser.email,
            cloudRecordName: currentUser.cloudRecordName,
            referralCode: currentUser.referralCode,
            createdAt: currentUser.createdAt,
            profileEmoji: profileEmoji,
            profileColor: profileColor
        )

        // Try to update in CloudKit
        do {
            try await dependencies.userCloudService.saveUser(updatedUser)
            logger.info("User updated in CloudKit")
        } catch {
            logger.warning("CloudKit update failed (ok if not enabled): \(error.localizedDescription)")
        }

        // Save to UserDefaults
        try requireCurrentMutation(mutationToken)
        saveUserToDefaults(updatedUser)

        self.currentUser = updatedUser

        logger.info("User profile updated successfully")
    }
    
    /// Perform initial recipe sync after user authentication
    func performInitialSync(dependencies: DependencyContainer) async {
        guard let userId = userId, isCloudSyncAvailable else {
            logger.info("Skipping initial sync - user not authenticated or CloudKit unavailable")
            return
        }

        logger.info("Performing initial recipe sync...")

        do {
            try await dependencies.recipeSyncService.performFullSync(for: userId)
            logger.info("Initial sync completed successfully")
        } catch {
            logger.error("Initial sync failed: \(error.localizedDescription)")
            // Don't throw - sync failure shouldn't block app usage
        }
    }

    /// Sign out and clear user session
    func signOut() {
        logger.info("Signing out user")
        let signingOutOwnerID = currentUser?.id

        // Sign-out is an identity boundary just like CKAccountChanged. Invalidate
        // synchronously so any suspended profile/onboarding mutation fails its
        // post-await authorization check before it can restore local session data.
        identityVerificationGate.invalidate()
        rotateSyncOperationAccountRevision()
        profileAvatarMutationRevision &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        initializationTask?.cancel()
        initializationTask = nil
        accountReverificationTask?.cancel()
        accountReverificationTask = nil

        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: usernameKey)
        UserDefaults.standard.removeObject(forKey: displayNameKey)
        UserDefaults.standard.removeObject(forKey: profileEmojiKey)
        UserDefaults.standard.removeObject(forKey: profileColorKey)
        UserDefaults.standard.removeObject(forKey: referralCodeKey)
        UserDefaults.standard.removeObject(forKey: cloudKitSystemRecordNameKey)
        UserDefaults.standard.removeObject(forKey: userSnapshotKey)
        if let signingOutOwnerID {
            removePendingProfileSync(ownerID: signingOutOwnerID)
        }

        currentUser = nil
        // Explicit sign-out is a settled session state, not an in-progress
        // verification state. Keep the root renderable so onboarding appears;
        // the invalidated gate still blocks every account-scoped mutation.
        isInitialized = true
        needsOnboarding = true
        needsiCloudSignIn = false
        cloudKitAccountStatus = nil

        logger.info("User signed out")
    }
}

enum UserSessionError: LocalizedError {
    case notAuthenticated
    case accountChanged
    case invalidUsername
    case invalidDisplayName
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "No user is currently signed in"
        case .accountChanged:
            return "Your iCloud account changed while saving. Please try again."
        case .invalidUsername:
            return "Username must be between 3 and 20 characters"
        case .invalidDisplayName:
            return "Display name cannot be empty"
        }
    }
}
