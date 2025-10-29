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
    @StateObject private var sharedRecipeHandler = SharedRecipeHandler()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sharedRecipeHandler)
                // URL handlers MUST come before sheet modifiers
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                    // Handle Universal Links and CloudKit shares
                    AppLogger.general.info("🟢 SwiftUI: onContinueUserActivity triggered")
                    guard let url = userActivity.webpageURL else {
                        AppLogger.general.warning("🟢 SwiftUI: No webpage URL in user activity")
                        return
                    }
                    AppLogger.general.info("🟢 SwiftUI: Handling URL from user activity: \(url)")
                    Task {
                        await sharedRecipeHandler.handleIncomingURL(url)
                    }
                }
                .onOpenURL { url in
                    // Handle custom URL schemes and CloudKit shares
                    AppLogger.general.info("🟢 SwiftUI: onOpenURL triggered with URL: \(url.absoluteString)")
                    AppLogger.general.info("🟢 SwiftUI: URL host: \(url.host ?? "nil"), scheme: \(url.scheme ?? "nil")")
                    Task {
                        await sharedRecipeHandler.handleIncomingURL(url)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AcceptCloudKitShare"))) { notification in
                    if let metadata = notification.object as? CKShare.Metadata {
                        AppLogger.general.info("📬 Received CloudKit share notification")
                        Task {
                            await sharedRecipeHandler.acceptCloudKitShareFromMetadata(metadata)
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TestOpenURL"))) { notification in
                    if let url = notification.object as? URL {
                        AppLogger.general.info("🧪 Test URL handler triggered with: \(url)")
                        Task {
                            await sharedRecipeHandler.handleIncomingURL(url)
                        }
                    }
                }
                // Sheets and alerts come after URL handlers
                .sheet(item: $sharedRecipeHandler.recipeToAccept) { recipeData in
                    NavigationStack {
                        SharedRecipeAcceptView(
                            recipe: recipeData.recipe,
                            existingRecipeId: recipeData.existingRecipeId
                        )
                        .environmentObject(sharedRecipeHandler)
                    }
                }
                .alert("Share Error", isPresented: $sharedRecipeHandler.showError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    if let errorMessage = sharedRecipeHandler.errorMessage {
                        Text(errorMessage)
                    }
                }
        }
    }
}

// Handler for shared recipes
@MainActor
class SharedRecipeHandler: ObservableObject {
    struct RecipeToAccept: Identifiable {
        let id = UUID()
        let recipe: Recipe
        let existingRecipeId: UUID?  // If recipe already exists locally
    }

    @Published var recipeToAccept: RecipeToAccept?
    @Published var showError = false
    @Published var errorMessage: String?
    @Published var isProcessing = false

    // Track processed URLs to prevent duplicates
    private var processedURLs = Set<String>()

    func handleIncomingURL(_ url: URL) async {
        AppLogger.general.info("🔗 Handling incoming URL: \(url.absoluteString)")
        AppLogger.general.info("🔗 URL scheme: \(url.scheme ?? "nil"), host: \(url.host ?? "nil")")

        // Prevent duplicate processing
        let urlString = url.absoluteString
        guard !processedURLs.contains(urlString) else {
            AppLogger.general.info("🔗 URL already processed, skipping: \(urlString)")
            return
        }
        processedURLs.insert(urlString)

        // Set processing state
        isProcessing = true
        defer { isProcessing = false }

        // Check if it's a custom deep link wrapper
        if url.scheme == "cauldron" && url.host == "share" {
            AppLogger.general.info("🔗 Detected custom deep link, extracting iCloud URL...")

            // Parse the URL parameter
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let queryItems = components.queryItems,
                  let urlParam = queryItems.first(where: { $0.name == "url" })?.value,
                  let iCloudURL = URL(string: urlParam) else {
                AppLogger.general.error("🔗 Failed to extract iCloud URL from custom deep link")
                showErrorAlert("Invalid share link format")
                processedURLs.remove(urlString)
                return
            }

            AppLogger.general.info("🔗 Extracted iCloud URL: \(iCloudURL.absoluteString)")
            await acceptCloudKitShare(iCloudURL)
        }
        // Check if it's a direct CloudKit share URL
        else if url.scheme == "https" && (url.host == "www.icloud.com" || url.host == "icloud.com") {
            AppLogger.general.info("🔗 Detected iCloud share URL, accepting...")
            await acceptCloudKitShare(url)
        } else {
            AppLogger.general.warning("🔗 URL is not a recognized share URL format")
            showErrorAlert("Unrecognized link format")
            processedURLs.remove(urlString)
        }
    }

    private func showErrorAlert(_ message: String) {
        errorMessage = message
        showError = true
    }

    private func acceptCloudKitShare(_ url: URL) async {
        do {
            let container = CKContainer.default()

            // Fetch share metadata
            AppLogger.general.info("☁️ Fetching share metadata from URL...")
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
            AppLogger.general.info("☁️ Successfully fetched share metadata")

            await acceptCloudKitShareFromMetadata(metadata)
        } catch let error as CKError {
            AppLogger.general.error("☁️ CloudKit error accepting share: \(error.localizedDescription)")

            // Provide user-friendly error messages
            switch error.code {
            case .notAuthenticated:
                showErrorAlert("Please sign in to iCloud in Settings to view shared recipes")
            case .networkFailure, .networkUnavailable:
                showErrorAlert("Network error. Please check your internet connection and try again")
            case .participantMayNeedVerification:
                showErrorAlert("Please verify your iCloud account to view shared recipes")
            case .serverRecordChanged:
                showErrorAlert("This share link has been updated. Please try again")
            default:
                showErrorAlert("Failed to load shared recipe: \(error.localizedDescription)")
            }
        } catch {
            AppLogger.general.error("☁️ Failed to accept shared recipe: \(error.localizedDescription)")
            showErrorAlert("Failed to load shared recipe. Please try again")
        }
    }

    func acceptCloudKitShareFromMetadata(_ metadata: CKShare.Metadata) async {
        // NOTE: CKShare link sharing has been intentionally replaced with visibility-based sharing.
        //
        // New sharing model:
        // - Private recipes: Only owner can see (syncs to iCloud for backup)
        // - Friends-only recipes: Connected friends auto-discover in Shared tab
        // - Public recipes: Everyone can discover in Shared tab
        //
        // Users save recipes via:
        // - "Add to My Recipes": Creates synced reference (stays updated with original)
        // - "Save a Copy": Creates independent editable copy
        //
        // This approach avoids CKShare zone complexity and provides automatic discovery.
        // If direct link sharing is needed in the future, consider simple deep links
        // (cauldron://recipe/UUID) that fall back to PUBLIC database lookup.

        AppLogger.general.info("⚠️ CKShare link sharing disabled - using visibility-based sharing")
        showErrorAlert("Recipe link sharing has been updated! Ask your friend to set the recipe to 'Friends Only' or 'Public' visibility, and you'll see it in your Sharing tab.")
    }

    private func findExistingRecipe(recipe: Recipe, dependencies: DependencyContainer) async throws -> UUID? {
        guard let currentUserId = CurrentUserSession.shared.userId else {
            return nil
        }

        // Check if recipe with same CloudKit record name exists
        if let cloudRecordName = recipe.cloudRecordName {
            let allRecipes = try await dependencies.recipeRepository.fetchAll()
            if let existing = allRecipes.first(where: { $0.cloudRecordName == cloudRecordName && $0.ownerId == currentUserId }) {
                return existing.id
            }
        }

        // Check if recipe with same title and similar content exists (for copies)
        let allRecipes = try await dependencies.recipeRepository.fetchAll()
        if let existing = allRecipes.first(where: {
            $0.title == recipe.title &&
            $0.ownerId == currentUserId &&
            $0.ingredients.count == recipe.ingredients.count
        }) {
            return existing.id
        }

        return nil
    }
}

// View for accepting a shared recipe
struct SharedRecipeAcceptView: View {
    let recipe: Recipe
    let existingRecipeId: UUID?

    @Environment(\.dependencies) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sharedRecipeHandler: SharedRecipeHandler
    @State private var isSaving = false
    @State private var showSuccessAlert = false

    private var isOwnRecipe: Bool {
        guard let currentUserId = CurrentUserSession.shared.userId else { return false }
        return recipe.ownerId == currentUserId
    }

    private var alreadyExists: Bool {
        existingRecipeId != nil
    }

    private var buttonText: String {
        if isOwnRecipe {
            return "Done"
        } else if alreadyExists {
            return "Done"
        } else {
            return "Close"
        }
    }

    private var headerText: String? {
        if isOwnRecipe {
            return "Your Recipe"
        } else if alreadyExists {
            return "Already in Your Recipes"
        } else {
            return nil
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if let header = headerText {
                    HStack {
                        Image(systemName: alreadyExists ? "checkmark.circle.fill" : "person.fill")
                            .foregroundColor(.cauldronOrange)
                        Text(header)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding()
                    .background(Color.cauldronOrange.opacity(0.1))
                }

                RecipeDetailView(recipe: recipe, dependencies: dependencies)
            }

            // Loading overlay when processing share
            if sharedRecipeHandler.isProcessing {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.cauldronOrange)

                    Text("Loading recipe...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .padding(32)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(radius: 20)
            }
        }
        .toolbar {
            if !isOwnRecipe && !alreadyExists {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await saveRecipe()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Label("Save to My Recipes", systemImage: "square.and.arrow.down")
                        }
                    }
                    .disabled(isSaving)
                }
            }

            ToolbarItem(placement: .navigationBarLeading) {
                Button(buttonText) {
                    dismiss()
                }
            }
        }
        .alert("Success", isPresented: $showSuccessAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Recipe saved to your collection!")
        }
    }

    private func saveRecipe() async {
        isSaving = true
        defer { isSaving = false }

        do {
            // Create a copy of the recipe for the current user
            guard let currentUserId = CurrentUserSession.shared.userId else {
                AppLogger.general.error("No current user")
                return
            }

            let savedRecipe = recipe.withOwner(currentUserId)
            try await dependencies.recipeRepository.create(savedRecipe)

            await MainActor.run {
                showSuccessAlert = true
            }

            AppLogger.general.info("Saved shared recipe to local collection")
        } catch {
            AppLogger.general.error("Failed to save recipe: \(error.localizedDescription)")
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
                        let container = CKContainer.default()
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
        AppLogger.general.info("🔵 App did finish launching")
        AppLogger.general.info("🔵 Launch options: \(launchOptions ?? [:])")

        // Log if launched with CloudKit activity
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
            } else if granted {
                AppLogger.general.info("✅ Notification permissions granted")
            } else {
                AppLogger.general.warning("⚠️ Notification permissions denied")
            }
        }
    }

    // MARK: - Push Notification Handling

    /// Called when device successfully registers for remote notifications
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        AppLogger.general.info("📱 Registered for remote notifications with token: \(tokenString)")
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

        // Handle query notification (for connection requests)
        if notification.notificationType == .query {
            AppLogger.general.info("🔔 Connection request notification received - syncing connections")

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
        AppLogger.general.info("🔵 AppDelegate: configurationForConnecting scene")

        // Log if there's a user activity
        if let userActivity = options.userActivities.first {
            AppLogger.general.info("🔵 Scene connecting with user activity: \(userActivity.activityType)")
            AppLogger.general.info("🔵 User activity URL: \(userActivity.webpageURL?.absoluteString ?? "nil")")
        }

        // Log if there's a URL context
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
        AppLogger.general.info("🟣 SceneDelegate: willConnectTo")

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

            // Check if it's an iCloud share URL
            if url.host == "www.icloud.com" || url.host == "icloud.com" {
                AppLogger.general.info("🟣 SceneDelegate: Detected iCloud share URL, processing...")

                Task {
                    do {
                        let container = CKContainer.default()
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

    private func handleURL(_ url: URL) {
        AppLogger.general.info("🟣 SceneDelegate: handleURL: \(url.absoluteString)")
        NotificationCenter.default.post(
            name: NSNotification.Name("TestOpenURL"),
            object: url
        )
    }
}
