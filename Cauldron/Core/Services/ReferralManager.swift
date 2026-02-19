//
//  ReferralManager.swift
//  Cauldron
//
//  Manages referral codes and tracks successful referrals for icon unlocks
//  Now integrated with CloudKit for persistence and tracking
//

import Foundation
import SwiftUI
import Combine

/// Icon unlock thresholds - each icon unlocks at a specific referral count
struct IconUnlock {
    let iconId: String
    let requiredReferrals: Int

    /// All icon unlocks in order
    static let all: [IconUnlock] = [
        IconUnlock(iconId: "default", requiredReferrals: 0),
        IconUnlock(iconId: "wicked", requiredReferrals: 1),
        IconUnlock(iconId: "goodwitch", requiredReferrals: 2),
        IconUnlock(iconId: "maleficent", requiredReferrals: 3),
        IconUnlock(iconId: "ursula", requiredReferrals: 5),
        IconUnlock(iconId: "agatha", requiredReferrals: 7),
        IconUnlock(iconId: "scarletwitch", requiredReferrals: 10),
        IconUnlock(iconId: "lion", requiredReferrals: 15),
        IconUnlock(iconId: "serpent", requiredReferrals: 20),
        IconUnlock(iconId: "badger", requiredReferrals: 30),
        IconUnlock(iconId: "eagle", requiredReferrals: 50),
    ]

    /// Get unlock info for a specific icon
    static func unlock(for iconId: String) -> IconUnlock? {
        all.first { $0.iconId == iconId }
    }
}

/// Manages referral tracking and code generation with CloudKit persistence
@MainActor
final class ReferralManager: ObservableObject {
    static let shared = ReferralManager()

    @Published private(set) var referralCount: Int = 0
    @Published private(set) var referralCode: String = ""
    @Published private(set) var isSyncing: Bool = false

    private let referralCountKey = "cauldron_referral_count"
    private let referralCodeKey = "cauldron_referral_code"
    private let usedReferralCodeKey = "cauldron_used_referral_code"

    // CloudKit service references (set during app initialization)
    private var userCloudService: UserCloudService?
    private var connectionCloudService: ConnectionCloudService?

    /// Number of unlocked icons
    var unlockedIconCount: Int {
        IconUnlock.all.filter { $0.requiredReferrals <= referralCount }.count
    }

    /// Total available icons
    var totalIconCount: Int {
        IconUnlock.all.count
    }

    /// Next icon to unlock, if any
    var nextIconToUnlock: IconUnlock? {
        IconUnlock.all.first { $0.requiredReferrals > referralCount }
    }

    /// Referrals needed for next icon
    var referralsToNextIcon: Int? {
        guard let next = nextIconToUnlock else { return nil }
        return next.requiredReferrals - referralCount
    }

    private init() {
        loadFromDefaults()
    }

    /// Configure the CloudKit services (called during app initialization)
    func configure(userCloudService: UserCloudService, connectionCloudService: ConnectionCloudService) {
        self.userCloudService = userCloudService
        self.connectionCloudService = connectionCloudService
    }

    /// Generate or retrieve the user's referral code
    /// Uses the user's CloudKit record name for uniqueness
    func generateReferralCode(for user: User) -> String {
        if let userCode = user.referralCode, !userCode.isEmpty {
            let normalizedCode = userCode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if isReferralCodeFormatValid(normalizedCode) {
                if referralCode != normalizedCode {
                    referralCode = normalizedCode
                    UserDefaults.standard.set(normalizedCode, forKey: referralCodeKey)
                }
                return normalizedCode
            }
        }

        if !referralCode.isEmpty, isReferralCodeFormatValid(referralCode) {
            return referralCode
        }

        // Generate a unique code based on CloudKit record name or user ID
        let baseId: String
        if let cloudRecordName = user.cloudRecordName {
            // Extract the unique part from "user_<systemId>"
            baseId = cloudRecordName.replacingOccurrences(of: "user_", with: "")
        } else {
            baseId = user.id.uuidString
        }

        // Create a short, shareable code from the ID
        // Take first 6 alphanumeric characters (uppercase)
        let cleanId = baseId.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
        let prefix = String(cleanId.prefix(6)).uppercased()

        // Ensure we have exactly 6 characters
        let code = prefix.padding(toLength: 6, withPad: "X", startingAt: 0)

        referralCode = code
        UserDefaults.standard.set(code, forKey: referralCodeKey)

        return code
    }

    /// Universal invite link base (must match AASA allowed paths)
    private let inviteBaseURL = URL(string: "https://cauldron-f900a.web.app")!

    /// Get the invite URL for sharing.
    /// The referral code is embedded so recipients can join without manual entry.
    func getShareURL(for user: User) -> URL {
        let code = generateReferralCode(for: user)
        var components = URLComponents(url: inviteBaseURL, resolvingAgainstBaseURL: false)
        components?.path = "/invite/\(code)"
        return components?.url ?? inviteBaseURL
    }

    /// Get share text with the referral code
    func getShareText(for user: User) -> String {
        let code = generateReferralCode(for: user)
        return "Join me on Cauldron! Tap my invite link to join instantly. If prompted, enter code \(code) to unlock rewards and auto-connect as friends."
    }

    /// Check if a referral code is valid (not the user's own code)
    func isValidReferralCode(_ code: String, currentUserCode: String) -> Bool {
        let normalizedCode = code.uppercased().trimmingCharacters(in: .whitespaces)
        let normalizedUserCode = currentUserCode.uppercased()

        // Can't use your own code
        if normalizedCode == normalizedUserCode {
            return false
        }

        return isReferralCodeFormatValid(normalizedCode)
    }

    /// Record that this user used a referral code during signup
    func recordUsedReferralCode(_ code: String) {
        UserDefaults.standard.set(code.uppercased(), forKey: usedReferralCodeKey)
    }

    /// Get the referral code this user used to sign up (if any)
    func getUsedReferralCode() -> String? {
        UserDefaults.standard.string(forKey: usedReferralCodeKey)
    }

    /// Increment the referral count locally
    func incrementReferralCount() {
        referralCount += 1
        UserDefaults.standard.set(referralCount, forKey: referralCountKey)
        AppLogger.general.info("🎉 Referral count increased to \(referralCount)")
    }

    /// Sync referral count from CloudKit
    func syncFromCloudKit(referralCount: Int) {
        // Only update if CloudKit has a higher count (don't lose local progress)
        if referralCount > self.referralCount {
            self.referralCount = referralCount
            UserDefaults.standard.set(referralCount, forKey: referralCountKey)
            AppLogger.general.info("📥 Synced referral count from CloudKit: \(referralCount)")
        }
    }

    /// Redeem a referral code and apply CloudKit updates.
    /// Returns the referrer if the code is successfully applied, nil otherwise.
    func redeemReferralCode(_ code: String, currentUser: User, displayName: String) async -> User? {
        guard let userCloudService = userCloudService,
              let connectionCloudService = connectionCloudService else {
            AppLogger.general.warning("CloudKit services not configured for referral processing")
            return nil
        }

        isSyncing = true
        defer { Task { @MainActor in self.isSyncing = false } }

        let normalizedCode = code.uppercased().trimmingCharacters(in: .whitespaces)
        let currentUserCode = generateReferralCode(for: currentUser)

        if normalizedCode.isEmpty || !isReferralCodeFormatValid(normalizedCode) {
            AppLogger.general.warning("Invalid referral code submitted (format): \(normalizedCode)")
            return nil
        }

        if let usedCode = getUsedReferralCode() {
            AppLogger.general.info("Referral already used: \(usedCode)")
            return nil
        }

        if !isValidReferralCode(normalizedCode, currentUserCode: currentUserCode) {
            AppLogger.general.warning("Invalid referral code submitted (self/format): \(normalizedCode)")
            return nil
        }

        // Look up the referrer by code
        let referrer: User?
        do {
            referrer = try await userCloudService.lookupUserByReferralCode(normalizedCode)
        } catch {
            AppLogger.general.error("Referral lookup failed: \(error.localizedDescription)")
            return nil
        }

        guard let referrer = referrer else {
            AppLogger.general.warning("Referral code not found: \(normalizedCode)")
            return nil
        }

        if referrer.id == currentUser.id {
            AppLogger.general.warning("User attempted to use their own referral code")
            return nil
        }

        if referrer.id != currentUser.id {
            let connectionExists = (try? await connectionCloudService.connectionExists(between: referrer.id, and: currentUser.id)) ?? false
            if !connectionExists {
                do {
                    try await connectionCloudService.createAutoFriendConnection(
                        referrerId: referrer.id,
                        newUserId: currentUser.id,
                        referrerUsername: referrer.username,
                        referrerDisplayName: referrer.displayName,
                        newUserUsername: currentUser.username,
                        newUserDisplayName: displayName
                    )

                    // Trigger connection refresh so the new user sees the connection immediately
                    NotificationCenter.default.post(name: .refreshConnections, object: nil)
                    AppLogger.general.info("🔄 Posted connection refresh notification after auto-friend creation")
                } catch {
                    AppLogger.general.error("Failed to create auto-friend connection: \(error.localizedDescription)")
                    return nil
                }
            } else {
                AppLogger.general.info("Referral connection already exists between \(referrer.id) and \(currentUser.id)")
            }
        }

        // Record the referral signup in CloudKit
        // The new user creates this record (so they have permission)
        // The referrer's count is computed by counting these records
        do {
            try await userCloudService.recordReferralSignup(referrerId: referrer.id, newUserId: currentUser.id)
        } catch {
            AppLogger.general.error("Failed to record referral signup: \(error.localizedDescription)")
            return nil
        }

        // Grant the new user one referral credit locally
        incrementReferralCount()
        recordUsedReferralCode(normalizedCode)

        AppLogger.general.info("Referral processed for \(referrer.displayName)")
        return referrer
    }

    /// Check if an icon is unlocked based on current referral count
    func isIconUnlocked(_ iconId: String) -> Bool {
        guard let unlock = IconUnlock.unlock(for: iconId) else {
            return false // Unknown icon
        }
        return referralCount >= unlock.requiredReferrals
    }

    /// Referrals needed to unlock a specific icon (0 if already unlocked)
    func referralsNeeded(for iconId: String) -> Int? {
        guard let unlock = IconUnlock.unlock(for: iconId) else {
            return nil
        }
        if isIconUnlocked(iconId) { return 0 }
        return unlock.requiredReferrals - referralCount
    }

    // MARK: - Persistence

    private func loadFromDefaults() {
        referralCount = UserDefaults.standard.integer(forKey: referralCountKey)
        let storedCode = UserDefaults.standard.string(forKey: referralCodeKey) ?? ""
        if isReferralCodeFormatValid(storedCode) {
            referralCode = storedCode
        } else {
            referralCode = ""
            UserDefaults.standard.removeObject(forKey: referralCodeKey)
        }
    }

    private func isReferralCodeFormatValid(_ code: String) -> Bool {
        let normalizedCode = code.uppercased().trimmingCharacters(in: .whitespaces)
        let regex = try? NSRegularExpression(pattern: "^[A-Z0-9]{6}$")
        let range = NSRange(normalizedCode.startIndex..., in: normalizedCode)
        return regex?.firstMatch(in: normalizedCode, range: range) != nil
    }

    /// Reset for testing
    func reset() {
        referralCount = 0
        referralCode = ""
        UserDefaults.standard.removeObject(forKey: referralCountKey)
        UserDefaults.standard.removeObject(forKey: referralCodeKey)
        UserDefaults.standard.removeObject(forKey: usedReferralCodeKey)
    }

    #if DEBUG
    /// For testing: set a specific referral count
    func setReferralCount(_ count: Int) {
        referralCount = count
        UserDefaults.standard.set(count, forKey: referralCountKey)
    }
    #endif
}

/// Helpers for parsing referral invite links.
enum ReferralInviteLink {
    static func referralCode(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        let isSupportedHost = host.contains("web.app") || host.contains("firebaseapp.com") || host == "cauldron.app"

        if url.scheme?.lowercased() == "cauldron" {
            // Supports: cauldron://invite?code=ABC123 and cauldron://invite/ABC123
            if url.host?.lowercased() == "invite" {
                if let queryCode = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name.lowercased() == "code" })?
                    .value {
                    return normalizedReferralCode(from: queryCode)
                }

                let pathCode = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                return normalizedReferralCode(from: pathCode)
            }
            return nil
        }

        guard isSupportedHost else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let queryCode = components?
            .queryItems?
            .first(where: { $0.name.lowercased() == "code" })?
            .value {
            return normalizedReferralCode(from: queryCode)
        }

        // Supports: https://.../invite/ABC123
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 2, pathComponents[0].lowercased() == "invite" else { return nil }
        return normalizedReferralCode(from: pathComponents[1])
    }

    private static func normalizedReferralCode(from rawCode: String) -> String? {
        let normalized = rawCode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "^[A-Z0-9]{6}$"
        guard normalized.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return normalized
    }
}

/// Thread-safe handoff store for referral codes extracted from invite links.
actor PendingReferralManager {
    static let shared = PendingReferralManager()
    private var pendingCode: String?

    private init() {}

    func setPendingCode(_ code: String) {
        pendingCode = code
    }

    func consumePendingCode() -> String? {
        defer { pendingCode = nil }
        return pendingCode
    }
}
