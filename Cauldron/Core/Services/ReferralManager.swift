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
    private let referralTestingEnabledKey = "ReferralTestingEnabled"
    private let referralTestCodeKey = "ReferralTestCode"
    private let referralTestTargetKey = "ReferralTestTargetCode"

    // CloudKit service reference (set during app initialization)
    private var cloudKitService: CloudKitService?

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

    /// Configure the CloudKit service (called during app initialization)
    func configure(with cloudKitService: CloudKitService) {
        self.cloudKitService = cloudKitService
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

    /// App Store URL for Cauldron
    private let appStoreURL = URL(string: "https://apps.apple.com/us/app/cauldron-magical-recipes/id6754004943")!

    /// Get the App Store URL for sharing
    func getShareURL(for user: User) -> URL {
        return appStoreURL
    }

    /// Get share text with the referral code
    func getShareText(for user: User) -> String {
        let code = generateReferralCode(for: user)
        return "Join me on Cauldron! 🧙‍♀️✨ Use my referral code \(code) when you sign up to unlock an exclusive app icon and we'll be connected as friends instantly!"
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
        guard let cloudKitService = cloudKitService else {
            AppLogger.general.warning("CloudKit service not configured for referral processing")
            return nil
        }

        isSyncing = true
        defer { Task { @MainActor in self.isSyncing = false } }

        let normalizedCode = code.uppercased().trimmingCharacters(in: .whitespaces)
        let currentUserCode = generateReferralCode(for: currentUser)
        let testConfig = referralTestConfig()
        let fallbackTestCode = "CAULDRONMASTERCODE"
        let isTestCode = normalizedCode == fallbackTestCode
            || (testConfig.enabled && !testConfig.code.isEmpty && normalizedCode == testConfig.code)
        let resolvedCode = isTestCode
            ? (testConfig.targetCode.isEmpty ? currentUserCode : testConfig.targetCode)
            : normalizedCode

        if isTestCode && testConfig.targetCode.isEmpty {
            do {
                try await cloudKitService.incrementReferralCount(for: currentUser.id)
                incrementReferralCount()
                return currentUser
            } catch {
                AppLogger.general.error("Failed to increment test referral count: \(error.localizedDescription)")
                return nil
            }
        }

        if resolvedCode.isEmpty || !isReferralCodeFormatValid(resolvedCode) {
            AppLogger.general.warning("Invalid referral code submitted (format): \(normalizedCode), resolved: \(resolvedCode)")
            return nil
        }

        if !isTestCode, let usedCode = getUsedReferralCode() {
            AppLogger.general.info("Referral already used: \(usedCode)")
            return nil
        }

        if !isTestCode, !isValidReferralCode(resolvedCode, currentUserCode: currentUserCode) {
            AppLogger.general.warning("Invalid referral code submitted (self/format): \(normalizedCode), resolved: \(resolvedCode)")
            return nil
        }

        // Look up the referrer by code
        let referrer = try? await cloudKitService.lookupUserByReferralCode(resolvedCode)
        guard let referrer = referrer else {
            AppLogger.general.warning("Referral code not found: \(normalizedCode)")
            return nil
        }

        if referrer.id == currentUser.id, !isTestCode {
            AppLogger.general.warning("User attempted to use their own referral code")
            return nil
        }

        if referrer.id != currentUser.id {
            let connectionExists = (try? await cloudKitService.connectionExists(between: referrer.id, and: currentUser.id)) ?? false
            if !connectionExists {
                do {
                    try await cloudKitService.createAutoFriendConnection(
                        referrerId: referrer.id,
                        newUserId: currentUser.id,
                        referrerDisplayName: referrer.displayName,
                        newUserDisplayName: displayName
                    )
                } catch {
                    AppLogger.general.error("Failed to create auto-friend connection: \(error.localizedDescription)")
                    return nil
                }
            } else {
                AppLogger.general.info("Referral connection already exists between \(referrer.id) and \(currentUser.id)")
            }
        }

        do {
            try await cloudKitService.incrementReferralCount(for: referrer.id)
        } catch {
            AppLogger.general.error("Failed to increment referrer count: \(error.localizedDescription)")
            return nil
        }

        if referrer.id != currentUser.id {
            do {
                try await cloudKitService.incrementReferralCount(for: currentUser.id)
            } catch {
                AppLogger.general.error("Failed to increment new user referral count: \(error.localizedDescription)")
                return nil
            }
        }

        // Bonus: grant the new user one referral credit locally after CloudKit succeeds
        incrementReferralCount()
        if !isTestCode {
            recordUsedReferralCode(resolvedCode)
        }

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

    private func referralTestConfig() -> (enabled: Bool, code: String, targetCode: String) {
        let enabled = Bundle.main.object(forInfoDictionaryKey: referralTestingEnabledKey) as? Bool == true
        guard enabled else {
            return (false, "", "")
        }

        let code = (Bundle.main.object(forInfoDictionaryKey: referralTestCodeKey) as? String ?? "")
            .uppercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let target = (Bundle.main.object(forInfoDictionaryKey: referralTestTargetKey) as? String ?? "")
            .uppercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let resolvedCode = code.isEmpty ? "CAULDRONMASTERCODE" : code
        return (enabled, resolvedCode, target)
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
