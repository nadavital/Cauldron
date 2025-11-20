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
            ContentView()
        }
    }
}


// App Delegate to handle CloudKit share acceptance
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static var pendingShareURL: URL?
    static var pendingShareMetadata: CKShare.Metadata?

    func application(
        _ application: UIApplication,
        userActivityWillContinue userActivityType: String
    ) -> Bool {
        AppLogger.general.info("🔵 AppDelegate: userActivityWillContinue: \(userActivityType)")
        return true
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        AppLogger.general.info("🔵 AppDelegate: continue userActivity type: \(userActivity.activityType)")
        AppLogger.general.info("🔵 AppDelegate: webpageURL: \(userActivity.webpageURL?.absoluteString ?? "nil")")
        AppLogger.general.info("🔵 AppDelegate: userInfo: \(userActivity.userInfo ?? [:])")

        // Check for CloudKit share
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
           let url = userActivity.webpageURL {
            AppLogger.general.info("🔵 AppDelegate: Got browsing web activity with URL: \(url)")

            // Check if it's an iCloud share URL
            if url.host == "www.icloud.com" || url.host == "icloud.com" {
                AppLogger.general.info("🔵 AppDelegate: Detected iCloud share URL, fetching metadata...")

                // Store URL for later if UI not ready
                AppDelegate.pendingShareURL = url

                Task {
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
                        AppDelegate.pendingShareMetadata = metadata

                        await MainActor.run {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("AcceptCloudKitShare"),
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

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Log only if launched with CloudKit activity (debugging share URLs)
        if let userActivityDictionary = launchOptions?[.userActivityDictionary] as? [AnyHashable: Any] {
            AppLogger.general.info("🔵 Launched with user activity: \(userActivityDictionary)")
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
        handleNotification(response.notification.request.content.userInfo)

        // Post notification to navigate to Connections view
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToConnections"),
                object: nil
            )
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
                    name: NSNotification.Name("RefreshConnections"),
                    object: nil
                )
            }

            // Update badge count asynchronously
            Task { @MainActor in
                // Access the default dependencies to get connection manager
                let dependencies = try? DependencyContainer.persistent()
                if let dependencies = dependencies,
                   let userId = CurrentUserSession.shared.userId {
                    await dependencies.connectionManager.loadConnections(forUserId: userId)
                    // Badge will be updated automatically in loadConnections
                }
            }
        }
    }

    func application(
        _ application: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        AppLogger.general.info("🔵 AppDelegate: open URL called with: \(url)")

        // Post notification to handle in SwiftUI
        NotificationCenter.default.post(
            name: NSNotification.Name("TestOpenURL"),
            object: url
        )

        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        AppLogger.general.info("🔵 AppDelegate: applicationDidBecomeActive")

        // Check for pending share metadata
        if let metadata = AppDelegate.pendingShareMetadata {
            AppLogger.general.info("🔵 AppDelegate: Processing pending share metadata")
            NotificationCenter.default.post(
                name: NSNotification.Name("AcceptCloudKitShare"),
                object: metadata
            )
            AppDelegate.pendingShareMetadata = nil
            AppDelegate.pendingShareURL = nil
        }

        // Update badge count when app becomes active
        Task { @MainActor in
            let dependencies = try? DependencyContainer.persistent()
            if let dependencies = dependencies {
                // Update badge count based on current pending requests
                dependencies.connectionManager.updateBadgeCount()
                AppLogger.general.info("📛 Badge count refreshed on app activation")
            }
        }
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
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
        AppLogger.general.info("🟣 SceneDelegate: continue userActivity: \(userActivity.activityType)")
        handleUserActivity(userActivity)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
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

            // Check if it's an external share URL (from Firebase)
            // Matches: https://YOUR-PROJECT.web.app/recipe/abc123
            // Or: https://cauldron.app/recipe/abc123
            if isExternalShareURL(url) {
                AppLogger.general.info("🟣 SceneDelegate: Detected external share URL, processing...")

                Task {
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("OpenExternalShare"),
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
                                name: NSNotification.Name("AcceptCloudKitShare"),
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
        // Check for Firebase hosting domain pattern
        // Matches: *.web.app, *.firebaseapp.com, or custom domain like cauldron.app
        guard let host = url.host else { return false }
        
        // Check for Firebase domains
        if host.contains("web.app") || host.contains("firebaseapp.com") || host == "cauldron.app" {
            // Continue to check path
        } else {
            return false
        }

        // Check if path matches share URL pattern: /recipe/*, /profile/*, /collection/*
        let pathComponents = url.pathComponents
        guard pathComponents.count >= 3 else { return false }

        let shareTypes = ["recipe", "profile", "collection"]
        return shareTypes.contains(pathComponents[1])
    }

    private func handleURL(_ url: URL) {
        AppLogger.general.info("🟣 SceneDelegate: handleURL: \(url.absoluteString)")

        // Check if it's an external share deep link (cauldron://import/...)
        if url.scheme == "cauldron" && url.host == "import" {
            AppLogger.general.info("🟣 SceneDelegate: Detected external share deep link")
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenExternalShare"),
                object: url
            )
            return
        }

        // Legacy URL handling for testing
        NotificationCenter.default.post(
            name: NSNotification.Name("TestOpenURL"),
            object: url
        )
    }
}
