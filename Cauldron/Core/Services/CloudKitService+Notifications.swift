//
//  CloudKitService+Notifications.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import CloudKit
import os

extension CloudKitService {
    // MARK: - Push Notifications & Subscriptions

    /// Subscribe to connection requests for push notifications
    /// This sets up a CloudKit subscription so the user gets notified when someone sends them a connection request
    func subscribeToConnectionRequests(forUserId userId: UUID) async throws {
        let subscriptionID = "connection-requests-\(userId.uuidString)"

        // Delete existing subscription first (if any) to ensure we use the latest notification format
        let db = try getPublicDatabase()
        do {
            try await db.deleteSubscription(withID: subscriptionID)
        } catch {
            // Subscription doesn't exist yet, that's fine (routine)
        }

        // Create predicate: toUserId == current user AND status == pending
        let predicate = NSPredicate(format: "toUserId == %@ AND status == %@", userId.uuidString, "pending")

        // Create query subscription
        let subscription = CKQuerySubscription(
            recordType: connectionRecordType,
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation]
        )

        // Configure notification with personalized message
        let notification = CKSubscription.NotificationInfo()

        // Use localization with field substitution to show sender's display name
        // This requires a Localizable.strings file with the key "CONNECTION_REQUEST_ALERT"
        // The %@ placeholder will be replaced with the value from the fromDisplayName field
        notification.alertLocalizationKey = "CONNECTION_REQUEST_ALERT"
        notification.alertLocalizationArgs = ["fromDisplayName"]

        // Fallback message if localization fails (shouldn't happen if Localizable.strings exists)
        notification.alertBody = "You have a new friend request!"

        notification.soundName = "default"
        notification.shouldBadge = true
        notification.shouldSendContentAvailable = true

        // Include connection data in userInfo for navigation
        notification.desiredKeys = ["connectionId", "fromUserId", "fromUsername", "fromDisplayName"]

        subscription.notificationInfo = notification

        // Save subscription
        do {
            _ = try await db.save(subscription)
        } catch {
            logger.error("Failed to save connection request subscription: \(error.localizedDescription)")
            throw error
        }
    }

    /// Unsubscribe from connection request notifications
    func unsubscribeFromConnectionRequests(forUserId userId: UUID) async throws {
        let subscriptionID = "connection-requests-\(userId.uuidString)"
        let db = try getPublicDatabase()

        do {
            try await db.deleteSubscription(withID: subscriptionID)
            logger.info("Unsubscribed from connection requests")
        } catch {
            logger.warning("Failed to unsubscribe: \(error.localizedDescription)")
        }
    }

    /// Subscribe to connection acceptances for push notifications
    /// This sets up a CloudKit subscription so the user gets notified when someone accepts their friend request
    func subscribeToConnectionAcceptances(forUserId userId: UUID) async throws {
        let subscriptionID = "connection-acceptances-\(userId.uuidString)"

        // Delete existing subscription first (if any) to ensure we use the latest notification format
        let db = try getPublicDatabase()
        do {
            try await db.deleteSubscription(withID: subscriptionID)
        } catch {
            // Subscription doesn't exist yet, that's fine (routine)
        }

        // Create predicate: fromUserId == current user AND status == accepted
        let predicate = NSPredicate(format: "fromUserId == %@ AND status == %@", userId.uuidString, "accepted")

        // Create query subscription
        let subscription = CKQuerySubscription(
            recordType: connectionRecordType,
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordUpdate]  // Fires when status changes to accepted
        )

        // Configure notification with personalized message
        let notification = CKSubscription.NotificationInfo()

        // Use simple alert body (field substitution doesn't work reliably with optional fields)
        // The app will fetch the actual user details when the notification is received
        notification.alertBody = "Your friend request was accepted!"

        notification.soundName = "default"
        notification.shouldBadge = false  // Don't badge for acceptances, only for incoming requests
        notification.shouldSendContentAvailable = true

        // Include connection data in userInfo for navigation
        // Don't include toDisplayName in desiredKeys since it might not exist on all records
        notification.desiredKeys = ["connectionId", "fromUserId", "toUserId", "status"]

        subscription.notificationInfo = notification

        // Save subscription
        do {
            _ = try await db.save(subscription)
        } catch {
            logger.error("Failed to save connection acceptance subscription: \(error.localizedDescription)")
            throw error
        }
    }

    /// Unsubscribe from connection acceptance notifications
    func unsubscribeFromConnectionAcceptances(forUserId userId: UUID) async throws {
        let subscriptionID = "connection-acceptances-\(userId.uuidString)"
        let db = try getPublicDatabase()

        do {
            try await db.deleteSubscription(withID: subscriptionID)
            logger.info("Unsubscribed from connection acceptances")
        } catch {
            logger.warning("Failed to unsubscribe from acceptances: \(error.localizedDescription)")
        }
    }

    /// Subscribe to referral signup notifications
    /// This sets up a CloudKit subscription so the user gets notified when someone uses their referral code
    func subscribeToReferralSignups(forUserId userId: UUID) async throws {
        let subscriptionID = "referral-signups-\(userId.uuidString)"

        // Delete existing subscription first (if any) to ensure we use the latest notification format
        let db = try getPublicDatabase()
        do {
            try await db.deleteSubscription(withID: subscriptionID)
        } catch {
            // Subscription doesn't exist yet, that's fine (routine)
        }

        // Create predicate: fromUserId == current user (referrer) AND isReferral == 1
        let predicate = NSPredicate(format: "fromUserId == %@ AND isReferral == %d", userId.uuidString, 1)

        // Create query subscription
        let subscription = CKQuerySubscription(
            recordType: connectionRecordType,
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation]
        )

        // Configure notification with personalized message
        let notification = CKSubscription.NotificationInfo()

        // Use localization with field substitution to show new user's display name
        notification.alertLocalizationKey = "REFERRAL_SIGNUP_ALERT"
        notification.alertLocalizationArgs = ["toDisplayName"]

        // Fallback message if localization fails
        notification.alertBody = "Someone joined Cauldron using your referral code! You're now friends."

        notification.soundName = "default"
        notification.shouldBadge = false
        notification.shouldSendContentAvailable = true

        // Include connection data in userInfo
        notification.desiredKeys = ["connectionId", "toUserId", "toDisplayName"]

        subscription.notificationInfo = notification

        // Save subscription
        do {
            _ = try await db.save(subscription)
        } catch {
            logger.error("Failed to save referral signup subscription: \(error.localizedDescription)")
            throw error
        }
    }

    /// Unsubscribe from referral signup notifications
    func unsubscribeFromReferralSignups(forUserId userId: UUID) async throws {
        let subscriptionID = "referral-signups-\(userId.uuidString)"
        let db = try getPublicDatabase()

        do {
            try await db.deleteSubscription(withID: subscriptionID)
            logger.info("Unsubscribed from referral signups")
        } catch {
            logger.warning("Failed to unsubscribe from referral signups: \(error.localizedDescription)")
        }
    }
}
