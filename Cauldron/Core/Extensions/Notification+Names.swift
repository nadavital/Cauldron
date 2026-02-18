//
//  Notification+Names.swift
//  Cauldron
//
//  Type-safe notification names to prevent typos and improve maintainability
//

import Foundation

extension Notification.Name {
    // MARK: - External Share Notifications

    /// Posted when an external share URL should be opened (from Firebase/web)
    static let openExternalShare = Notification.Name("OpenExternalShare")

    /// Posted when navigating to shared content (recipe, profile, collection)
    static let navigateToSharedContent = Notification.Name("NavigateToSharedContent")

    /// Posted when recipe import URL arrives from Share Extension handoff
    static let openRecipeImportURL = Notification.Name("OpenRecipeImportURL")

    /// Posted when a referral invite link is opened and a code is extracted
    static let openReferralInvite = Notification.Name("OpenReferralInvite")

    // MARK: - CloudKit Share Notifications

    /// Posted when a CloudKit share should be accepted
    static let acceptCloudKitShare = Notification.Name("AcceptCloudKitShare")

    // MARK: - Recipe Notifications

    /// Posted when a new recipe is added to the library
    static let recipeAdded = Notification.Name("RecipeAdded")

    // MARK: - Connection Notifications

    /// Posted when connections should be refreshed (after push notification)
    static let refreshConnections = Notification.Name("RefreshConnections")

    /// Posted when navigating to the connections/friends view
    static let navigateToConnections = Notification.Name("NavigateToConnections")

    /// Posted when a referral notification should open the newly joined friend's profile
    static let navigateToReferralProfile = Notification.Name("NavigateToReferralProfile")

    // MARK: - Testing/Legacy Notifications

    /// Legacy test notification for URL handling
    static let testOpenURL = Notification.Name("TestOpenURL")
}
