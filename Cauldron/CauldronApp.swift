//
//  CauldronApp.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import SwiftUI
import CloudKit
import os
import UIKit
import Combine
import UserNotifications

@main
struct CauldronApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            if RuntimeEnvironment.isRunningTests {
                // Keep unit-test host lightweight to avoid unrelated SwiftUI teardown crashes.
                Color.clear
            } else {
                ContentView()
                    .dependencies(DependencyContainer.shared)
            }
        }
    }
}


// App Delegate to handle CloudKit share acceptance
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        userActivityWillContinue userActivityType: String
    ) -> Bool {
        if RuntimeEnvironment.isRunningTests {
            return false
        }

        AppLogger.general.info("🔵 AppDelegate: userActivityWillContinue: \(userActivityType)")
        return true
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        if RuntimeEnvironment.isRunningTests {
            return false
        }

        AppLogger.general.info("🔵 AppDelegate: continue userActivity type: \(userActivity.activityType)")
        AppLogger.general.info("🔵 AppDelegate: webpageURL: \(userActivity.webpageURL?.absoluteString ?? "nil")")
        AppLogger.general.info("🔵 AppDelegate: userInfo: \(userActivity.userInfo ?? [:])")

        // Check for CloudKit share or external share
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
           let url = userActivity.webpageURL {
            AppLogger.general.info("🔵 AppDelegate: Got browsing web activity with URL: \(url)")

            // Check if it's an external share URL (from Firebase)
            if isExternalShareURL(url) {
                AppLogger.general.info("🔵 AppDelegate: Detected external share URL, storing for processing...")

                // Store URL for later processing when UI is ready
                Task {
                    await PendingShareManager.shared.setPendingURL(url)

                    // Post notification immediately in case UI is ready
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .openExternalShare,
                            object: url
                        )
                    }
                }

                return true
            }

            // Check if it's an iCloud share URL
            if url.host == "www.icloud.com" || url.host == "icloud.com" {
                AppLogger.general.info("🔵 AppDelegate: Detected iCloud share URL, fetching metadata...")

                Task {
                    guard RuntimeEnvironment.canUseCloudKit else {
                        AppLogger.general.error("🔵 AppDelegate: CloudKit unavailable in current runtime; skipping share metadata fetch")
                        return
                    }

                    // Store URL for later if UI not ready
                    await PendingShareManager.shared.setPendingURL(url)

                    do {
                        let container = CKContainer(identifier: "iCloud.Nadav.Cauldron")
                        let metadata = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKShare.Metadata, Error>) in
                            container.fetchShareMetadata(with: url) { metadata, error in
                                if let error = error {
                                    continuation.resume(throwing: error)
                                } else if let metadata = metadata {
                                    continuation.resume(returning: metadata)
                                } else {
                                    continuation.resume(throwing: CloudKitError.invalidRecord)
                                }
                            }
                        }

                        AppLogger.general.info("🔵 AppDelegate: Successfully fetched share metadata, posting notification")
                        await PendingShareManager.shared.setPendingMetadata(metadata)

                        await MainActor.run {
                            NotificationCenter.default.post(
                                name: .acceptCloudKitShare,
                                object: metadata
                            )
                        }
                    } catch {
                        AppLogger.general.error("🔵 AppDelegate: Failed to fetch share metadata: \(error.localizedDescription)")
                    }
                }

                return true
            }
        }

        AppLogger.general.warning("🔵 AppDelegate: Did not handle user activity")
        return false
    }

    /// Check if URL is an external share link (from Firebase)
    private func isExternalShareURL(_ url: URL) -> Bool {
        ExternalShareURLClassifier.isExternalShareURL(url)
    }

    /// Render navigation titles in the system serif (New York), matching the
    /// app's serif section headers, while keeping the default (Liquid Glass)
    /// nav-bar background.
    static func configureNavigationBarAppearance() {
        func serifFont(_ textStyle: UIFont.TextStyle) -> UIFont {
            let base = UIFont.preferredFont(forTextStyle: textStyle)
            var descriptor = base.fontDescriptor
            if let serif = descriptor.withDesign(.serif) { descriptor = serif }
            if let bold = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.traitBold)) {
                descriptor = bold
            }
            return UIFont(descriptor: descriptor, size: base.pointSize)
        }

        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.largeTitleTextAttributes = [.font: serifFont(.largeTitle)]
        appearance.titleTextAttributes = [.font: serifFont(.headline)]

        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance = appearance
        navBar.scrollEdgeAppearance = appearance
        navBar.compactAppearance = appearance
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Match navigation titles to the app's serif section headers.
        // Skipped under tests (no UI host); still applied in QA/preview + production.
        if !RuntimeEnvironment.isRunningTests {
            Self.configureNavigationBarAppearance()
        }

        if RuntimeEnvironment.isRunningTests || RuntimeEnvironment.isSimulatorQAMode {
            return true
        }

        // Set up notification center delegate
        UNUserNotificationCenter.current().delegate = self

        // Request notification permissions
        requestNotificationPermissions()

        // Register for remote notifications
        application.registerForRemoteNotifications()

        return true
    }

    /// Request permission to show notifications
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                AppLogger.general.error("Failed to request notification permissions: \(error.localizedDescription)")
            } else if !granted {
                AppLogger.general.warning("⚠️ Notification permissions denied")
            }
            // Don't log on success - it's routine
        }
    }

    // MARK: - Push Notification Handling

    /// Called when device successfully registers for remote notifications
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Registration successful - don't log routine operations
    }

    /// Called when registration for remote notifications fails
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        AppLogger.general.error("❌ Failed to register for remote notifications: \(error.localizedDescription)")
    }

    /// Called when a remote notification arrives while app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        AppLogger.general.info("📬 Received notification while app in foreground")
        handleNotification(notification.request.content.userInfo)

        // Show banner and play sound even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    /// Called when user taps on a notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        AppLogger.general.info("📬 User tapped notification")
        let userInfo = response.notification.request.content.userInfo
        let referralFriendUserId = extractReferralFriendUserId(from: userInfo)

        handleNotification(userInfo)

        // Route referral notifications directly to the joined friend's profile.
        // Keep existing behavior for all other notification types.
        DispatchQueue.main.async {
            if let referralFriendUserId {
                NotificationCenter.default.post(
                    name: .navigateToReferralProfile,
                    object: referralFriendUserId
                )
            } else {
                NotificationCenter.default.post(
                    name: .navigateToConnections,
                    object: nil
                )
            }
        }

        completionHandler()
    }

    /// Called when a silent remote notification arrives
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        AppLogger.general.info("📬 Received remote notification")
        handleNotification(userInfo)
        completionHandler(.newData)
    }

    /// Handle CloudKit notification and sync data
    private func handleNotification(_ userInfo: [AnyHashable: Any]) {
        guard !RuntimeEnvironment.isRunningTests else {
            return
        }

        AppLogger.general.info("Processing notification userInfo: \(userInfo)")

        // Check if this is a CloudKit notification
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            AppLogger.general.warning("Not a CloudKit notification")
            return
        }

        AppLogger.general.info("CloudKit notification type: \(notification.notificationType.rawValue)")

        // Handle query notification (for connection requests and acceptances)
        if notification.notificationType == .query {
            AppLogger.general.info("🔔 Connection notification received - syncing connections")

            // Post notification to trigger connection refresh
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .refreshConnections,
                    object: nil
                )
            }

            // Update badge count and sync referral count asynchronously
            Task { @MainActor in
                let dependencies = DependencyContainer.shared
                if let userId = CurrentUserSession.shared.userId {
                    await dependencies.connectionManager.loadConnections(forUserId: userId)
                    // Badge will be updated automatically in loadConnections

                    // Sync referral count from CloudKit (referrer may have gotten a new referral)
                    if let count = try? await dependencies.userCloudService.fetchReferralCount(for: userId) {
                        ReferralManager.shared.syncFromCloudKit(referralCount: count)
                        AppLogger.general.info("📊 Synced referral count from notification: \(count)")
                    }
                }
            }
        }
    }

    private func extractReferralFriendUserId(from userInfo: [AnyHashable: Any]) -> UUID? {
        let payload = referralPayload(from: userInfo)

        guard payload.isReferral else {
            return nil
        }

        guard let toUserIdString = payload.toUserIdString,
              let toUserId = UUID(uuidString: toUserIdString) else {
            return nil
        }

        // Safety guard: referral friend should never be the currently signed-in user.
        if let currentUserId = CurrentUserSession.shared.userId, toUserId == currentUserId {
            return nil
        }

        return toUserId
    }

    private func referralPayload(from userInfo: [AnyHashable: Any]) -> (isReferral: Bool, toUserIdString: String?) {
        let topLevelIsReferral = isReferralNotification(userInfo)
        let topLevelToUserId = stringValue(forKey: "toUserId", in: userInfo)

        guard let queryNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) as? CKQueryNotification else {
            return (topLevelIsReferral, topLevelToUserId)
        }

        let recordFields = queryNotification.recordFields ?? [:]
        let isReferral = boolValue(forKey: "isReferral", in: recordFields) ?? topLevelIsReferral
        let toUserIdString = stringValue(forKey: "toUserId", in: recordFields) ?? topLevelToUserId
        return (isReferral, toUserIdString)
    }

    private func isReferralNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        boolValue(forKey: "isReferral", in: userInfo) ?? false
    }

    private func boolValue(forKey key: String, in userInfo: [AnyHashable: Any]) -> Bool? {
        guard let value = userInfo[key] else {
            return nil
        }
        return boolValue(from: value)
    }

    private func boolValue(forKey key: String, in recordFields: [String: Any]) -> Bool? {
        guard let value = recordFields[key] else {
            return nil
        }
        return boolValue(from: value)
    }

    private func boolValue(from rawValue: Any) -> Bool? {
        if let value = rawValue as? Bool {
            return value
        }

        if let value = rawValue as? NSNumber {
            return value.intValue == 1
        }

        if let value = rawValue as? Int {
            return value == 1
        }

        if let value = rawValue as? String {
            return value == "1" || value.lowercased() == "true"
        }

        if let value = rawValue as? NSString {
            let normalized = (value as String).lowercased()
            return normalized == "1" || normalized == "true"
        }

        return nil
    }

    private func stringValue(forKey key: String, in userInfo: [AnyHashable: Any]) -> String? {
        if let value = userInfo[key] as? String {
            return value
        }

        if let value = userInfo[key] as? NSString {
            return value as String
        }

        return nil
    }

    private func stringValue(forKey key: String, in recordFields: [String: Any]) -> String? {
        if let value = recordFields[key] as? String {
            return value
        }

        if let value = recordFields[key] as? NSString {
            return value as String
        }

        return nil
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        if RuntimeEnvironment.isRunningTests {
            return
        }

        AppLogger.general.info("🔵 AppDelegate: applicationDidBecomeActive")

        // Check for pending share metadata
        Task {
            if let metadata = await PendingShareManager.shared.consumePendingMetadata() {
                AppLogger.general.info("🔵 AppDelegate: Processing pending share metadata")
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .acceptCloudKitShare,
                        object: metadata
                    )
                }
            }
        }

        // Update badge count when app becomes active
        Task { @MainActor in
            let dependencies = DependencyContainer.shared
            // Update badge count based on current pending requests
            dependencies.connectionManager.updateBadgeCount()
            AppLogger.general.info("📛 Badge count refreshed on app activation")
        }
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if RuntimeEnvironment.isRunningTests {
            return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        }

        // Only log if there's interesting activity (debugging share URLs)
        if let userActivity = options.userActivities.first {
            AppLogger.general.info("🔵 Scene connecting with user activity: \(userActivity.activityType)")
            AppLogger.general.info("🔵 User activity URL: \(userActivity.webpageURL?.absoluteString ?? "nil")")
        }

        for urlContext in options.urlContexts {
            AppLogger.general.info("🔵 Scene connecting with URL: \(urlContext.url.absoluteString)")
        }

        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

// Scene Delegate for handling URLs in SwiftUI lifecycle
class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard !RuntimeEnvironment.isRunningTests else {
            return
        }

        // Handle user activity (Universal Links)
        if let userActivity = connectionOptions.userActivities.first {
            AppLogger.general.info("🟣 SceneDelegate: Got user activity: \(userActivity.activityType)")
            handleUserActivity(userActivity)
        }

        // Handle URL contexts
        for urlContext in connectionOptions.urlContexts {
            AppLogger.general.info("🟣 SceneDelegate: Got URL context: \(urlContext.url.absoluteString)")
            handleURL(urlContext.url)
        }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard !RuntimeEnvironment.isRunningTests else {
            return
        }

        AppLogger.general.info("🟣 SceneDelegate: continue userActivity: \(userActivity.activityType)")
        handleUserActivity(userActivity)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard !RuntimeEnvironment.isRunningTests else {
            return
        }

        AppLogger.general.info("🟣 SceneDelegate: openURLContexts called with \(URLContexts.count) URLs")
        for context in URLContexts {
            AppLogger.general.info("🟣 SceneDelegate: Opening URL: \(context.url.absoluteString)")
            handleURL(context.url)
        }
    }

    private func handleUserActivity(_ userActivity: NSUserActivity) {
        AppLogger.general.info("🟣 SceneDelegate: handleUserActivity type: \(userActivity.activityType)")

        if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
           let url = userActivity.webpageURL {
            AppLogger.general.info("🟣 SceneDelegate: Got web URL: \(url.absoluteString)")

            if routeReferralInviteIfNeeded(url) {
                AppLogger.general.info("🟣 SceneDelegate: Detected referral invite URL")
                return
            }

            // Check if it's an external share URL (from Firebase)
            // Matches: https://YOUR-PROJECT.web.app/recipe/abc123
            // Or: https://cauldron.app/recipe/abc123
            if isExternalShareURL(url) {
                AppLogger.general.info("🟣 SceneDelegate: Detected external share URL, processing...")

                Task {
                    await PendingShareManager.shared.setPendingURL(url)
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .openExternalShare,
                            object: url
                        )
                    }
                }
                return
            }

            // Check if it's an iCloud share URL
            if url.host == "www.icloud.com" || url.host == "icloud.com" {
                AppLogger.general.info("🟣 SceneDelegate: Detected iCloud share URL, processing...")

                Task {
                    guard RuntimeEnvironment.canUseCloudKit else {
                        AppLogger.general.error("🟣 SceneDelegate: CloudKit unavailable in current runtime; skipping share metadata fetch")
                        return
                    }

                    do {
                        let container = CKContainer(identifier: "iCloud.Nadav.Cauldron")
                        let metadata = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKShare.Metadata, Error>) in
                            container.fetchShareMetadata(with: url) { metadata, error in
                                if let error = error {
                                    continuation.resume(throwing: error)
                                } else if let metadata = metadata {
                                    continuation.resume(returning: metadata)
                                } else {
                                    continuation.resume(throwing: CloudKitError.invalidRecord)
                                }
                            }
                        }

                        AppLogger.general.info("🟣 SceneDelegate: Successfully fetched share metadata")
                        await MainActor.run {
                            NotificationCenter.default.post(
                                name: .acceptCloudKitShare,
                                object: metadata
                            )
                        }
                    } catch {
                        AppLogger.general.error("🟣 SceneDelegate: Failed to fetch share metadata: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Check if URL is an external share link (from Firebase)
    private func isExternalShareURL(_ url: URL) -> Bool {
        ExternalShareURLClassifier.isExternalShareURL(url)
    }

    private func handleURL(_ url: URL) {
        AppLogger.general.info("🟣 SceneDelegate: handleURL: \(url.absoluteString)")

        if routeReferralInviteIfNeeded(url) {
            AppLogger.general.info("🟣 SceneDelegate: Detected referral invite deep link")
            return
        }

        // Share Extension handoff for recipe import URLs from Safari.
        if url.scheme == "cauldron" && url.host == "import-recipe" {
            if let pendingURL = ShareExtensionImportStore.pendingRecipeURL() {
                NotificationCenter.default.post(
                    name: .openRecipeImportURL,
                    object: pendingURL
                )
            } else {
                AppLogger.general.warning("⚠️ No pending recipe URL found for Share Extension handoff")
            }
            return
        }

        // Check if it's an external share deep link (cauldron://import/...)
        if url.scheme == "cauldron" && url.host == "import" {
            AppLogger.general.info("🟣 SceneDelegate: Detected external share deep link")
            Task {
                await PendingShareManager.shared.setPendingURL(url)
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .openExternalShare,
                        object: url
                    )
                }
            }
            return
        }

        // Legacy URL handling for testing
        NotificationCenter.default.post(
            name: .testOpenURL,
            object: url
        )
    }

    /// Parse referral invite links and post them into the app flow.
    /// Returns true when the URL was recognized as an invite link.
    private func routeReferralInviteIfNeeded(_ url: URL) -> Bool {
        guard let referralCode = ReferralInviteLink.referralCode(from: url) else {
            return false
        }

        Task {
            await PendingReferralManager.shared.setPendingCode(referralCode)
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .openReferralInvite,
                    object: referralCode
                )
            }
        }
        return true
    }
}
