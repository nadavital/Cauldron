//
//  ConnectionsView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import SwiftUI
import os
import Combine

/// View for managing connections/friends
struct ConnectionsView: View {
    @StateObject private var viewModel: ConnectionsViewModel
    
    init(dependencies: DependencyContainer) {
        _viewModel = StateObject(wrappedValue: ConnectionsViewModel(dependencies: dependencies))
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Pending requests received
                if !viewModel.receivedRequests.isEmpty {
                    sectionHeader(title: "Pending Requests", icon: "bell.badge.fill", color: .cauldronOrange)

                    ForEach(viewModel.receivedRequests, id: \.id) { connection in
                        if let user = viewModel.usersMap[connection.fromUserId] {
                            ConnectionRequestCard(
                                user: user,
                                connection: connection,
                                dependencies: viewModel.dependencies,
                                onAccept: {
                                    await viewModel.acceptRequest(connection)
                                },
                                onReject: {
                                    await viewModel.rejectRequest(connection)
                                }
                            )
                        }
                    }
                }

                // Active friends
                if !viewModel.connections.isEmpty {
                    sectionHeader(title: "Friends", icon: "person.2.fill", color: .green)

                    ForEach(viewModel.connections, id: \.id) { connection in
                        if let otherUserId = connection.otherUserId(currentUserId: viewModel.currentUserId),
                           let user = viewModel.usersMap[otherUserId] {
                            ConnectionCard(user: user, dependencies: viewModel.dependencies)
                        }
                    }
                }

                // Sent requests (pending)
                if !viewModel.sentRequests.isEmpty {
                    sectionHeader(title: "Sent Requests", icon: "paperplane.fill", color: .blue)

                    ForEach(viewModel.sentRequests, id: \.id) { connection in
                        if let user = viewModel.usersMap[connection.toUserId] {
                            SentRequestCard(user: user, dependencies: viewModel.dependencies)
                        }
                    }
                }

                // Empty state
                if viewModel.connections.isEmpty && viewModel.receivedRequests.isEmpty && viewModel.sentRequests.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "person.2.circle")
                            .font(.system(size: 72))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.cauldronOrange, Color.cauldronOrange.opacity(0.6)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        VStack(spacing: 8) {
                            Text("No Friends Yet")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("Search for users in the Search tab to start adding friends!")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 80)
                }
            }
            .padding(.vertical, 12)
        }
        .background(Color.cauldronBackground.ignoresSafeArea())
        .navigationTitle("Friends")
        .task {
            await viewModel.loadConnections()
        }
        .refreshable {
            await viewModel.loadConnections(forceRefresh: true)
        }
        .onAppear {
            // Clear badge when user views the connections (they've seen the pending requests)
            viewModel.dependencies.connectionManager.clearBadge()
        }
        .alert("Error", isPresented: $viewModel.showErrorAlert) {
            Button("OK") { }
        } message: {
            Text(viewModel.alertMessage)
        }
    }

    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)

            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .padding(.top, 8)
    }
}

// MARK: - Connection Request Card

struct ConnectionRequestCard: View {
    let user: User
    let connection: Connection
    let dependencies: DependencyContainer
    let onAccept: () async -> Void
    let onReject: () async -> Void

    @State private var isProcessing = false

    var body: some View {
        NavigationLink {
            UserProfileView(user: user, dependencies: dependencies)
        } label: {
            HStack(spacing: 16) {
                // Avatar
                ProfileAvatar(user: user, size: 60, dependencies: dependencies)

                VStack(alignment: .leading, spacing: 6) {
                    Text(user.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("@\(user.username)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                        Text("wants to be friends")
                            .font(.caption)
                    }
                    .foregroundColor(.cauldronOrange)
                }

                Spacer()

                // Action buttons
                if isProcessing {
                    ProgressView()
                        .padding(.trailing, 8)
                } else {
                    VStack(spacing: 8) {
                        Button {
                            Task {
                                isProcessing = true
                                await onAccept()
                                isProcessing = false
                            }
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(
                                    Circle()
                                        .fill(Color.green)
                                )
                                .shadow(color: Color.green.opacity(0.3), radius: 3, x: 0, y: 2)
                        }

                        Button {
                            Task {
                                isProcessing = true
                                await onReject()
                                isProcessing = false
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(
                                    Circle()
                                        .fill(Color.red)
                                )
                                .shadow(color: Color.red.opacity(0.3), radius: 3, x: 0, y: 2)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color.cauldronSecondaryBackground)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Connection Card

struct ConnectionCard: View {
    let user: User
    let dependencies: DependencyContainer

    var body: some View {
        NavigationLink {
            UserProfileView(user: user, dependencies: dependencies)
        } label: {
            HStack(spacing: 16) {
                // Avatar
                ProfileAvatar(user: user, size: 60, dependencies: dependencies)

                VStack(alignment: .leading, spacing: 6) {
                    Text(user.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("@\(user.username)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(16)
            .background(Color.cauldronSecondaryBackground)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sent Request Card

struct SentRequestCard: View {
    let user: User
    let dependencies: DependencyContainer

    var body: some View {
        NavigationLink {
            UserProfileView(user: user, dependencies: dependencies)
        } label: {
            HStack(spacing: 16) {
                // Avatar
                ProfileAvatar(user: user, size: 60, dependencies: dependencies)

                VStack(alignment: .leading, spacing: 6) {
                    Text(user.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("@\(user.username)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text("Pending")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(16)
            .background(Color.cauldronSecondaryBackground)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

@MainActor
class ConnectionsViewModel: ObservableObject {
    @Published var connections: [Connection] = []
    @Published var receivedRequests: [Connection] = []
    @Published var sentRequests: [Connection] = []
    @Published var usersMap: [UUID: User] = [:]
    @Published var showErrorAlert = false
    @Published var alertMessage = ""

    let dependencies: DependencyContainer
    private var cancellables = Set<AnyCancellable>()
    private let cacheValidityDuration: TimeInterval = 1800 // 30 minutes

    // CRITICAL: Use a shared timestamp across all ConnectionsViewModel instances
    // This ensures that if one instance loaded user details, other instances won't reload unnecessarily
    private static var sharedUserDetailsCacheTimestamp: Date?

    private var userDetailsCacheTimestamp: Date? {
        get { ConnectionsViewModel.sharedUserDetailsCacheTimestamp }
        set { ConnectionsViewModel.sharedUserDetailsCacheTimestamp = newValue }
    }

    var currentUserId: UUID {
        CurrentUserSession.shared.userId ?? UUID()
    }

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies

        // Subscribe to connection manager updates
        dependencies.connectionManager.$connections
            .map { managedConnections in
                // Filter and categorize connections
                let all = Array(managedConnections.values)
                let accepted = all.filter { $0.connection.isAccepted }.map { $0.connection }
                let received = all.filter {
                    $0.connection.toUserId == (CurrentUserSession.shared.userId ?? UUID()) &&
                    $0.connection.status == .pending
                }.map { $0.connection }
                let sent = all.filter {
                    $0.connection.fromUserId == (CurrentUserSession.shared.userId ?? UUID()) &&
                    $0.connection.status == .pending
                }.map { $0.connection }

                return (accepted, received, sent)
            }
            .sink { [weak self] (accepted, received, sent) in
                self?.connections = accepted
                self?.receivedRequests = received
                self?.sentRequests = sent
            }
            .store(in: &cancellables)
    }
    
    func loadConnections(forceRefresh: Bool = false) async {
        // Use ConnectionManager - it handles caching and sync automatically
        await dependencies.connectionManager.loadConnections(forUserId: currentUserId, forceRefresh: forceRefresh)

        // Load user details for all connections
        await loadUserDetails(forceRefresh: forceRefresh)
    }

    /// Public method to preload user details (called from ContentView)
    func preloadUserDetails() async {
        await loadUserDetails(forceRefresh: false)
    }

    private func loadUserDetails(forceRefresh: Bool = false) async {
        // Check if cache is still valid
        if !forceRefresh, let timestamp = userDetailsCacheTimestamp {
            let timeSinceLastSync = Date().timeIntervalSince(timestamp)
            if timeSinceLastSync < cacheValidityDuration {
                AppLogger.general.info("📦 Using cached user details (synced \(Int(timeSinceLastSync))s ago)")

                // CRITICAL: Even when using cached data, we need to populate usersMap
                // This handles the case where ConnectionsInlineView creates a new ViewModel instance
                await loadUsersFromLocalCache()

                // Also ensure profile images are in memory cache
                await ensureProfileImagesInCache()
                return
            }
        }

        // Get all unique user IDs from connections
        var userIds = Set<UUID>()
        for connection in connections + receivedRequests + sentRequests {
            userIds.insert(connection.fromUserId)
            userIds.insert(connection.toUserId)
        }

        // FIRST: Load from local cache instantly (for immediate display)
        for userId in userIds {
            if let cachedUser = try? await dependencies.sharingRepository.fetchUser(id: userId) {
                usersMap[userId] = cachedUser
            }
        }

        // Only fetch from CloudKit if forcing refresh or cache expired
        if forceRefresh || userDetailsCacheTimestamp == nil ||
           (Date().timeIntervalSince(userDetailsCacheTimestamp!) >= cacheValidityDuration) {
            // If force refreshing, clear the in-memory image cache so images will reload
            if forceRefresh {
                await ImageCache.shared.clearProfileImages()
            }

            // Fetch users from CloudKit in background
            for userId in userIds {
                if let cloudUser = try? await dependencies.cloudKitService.fetchUser(byUserId: userId) {
                    usersMap[userId] = cloudUser
                    try? await dependencies.sharingRepository.save(cloudUser)
                    // Fetched and cached user from CloudKit (don't log routine operations)
                }
            }

            // Update cache timestamp
            userDetailsCacheTimestamp = Date()
            // Loaded user details via CloudKit (don't log routine operations)
        } else {
            // Using cached user details from repository (don't log routine operations)
        }

        // Preload profile images for all users (NOT in background - wait for them)
        // This ensures images are ready when ProfileAvatar views appear
        await preloadProfileImages(forceRefresh: forceRefresh)
    }

    /// Load users from local cache into usersMap
    /// Used when cache is valid but usersMap is empty (new ViewModel instance)
    private func loadUsersFromLocalCache() async {
        // If usersMap is already populated, skip
        if !usersMap.isEmpty {
            return
        }

        // Get all unique user IDs from connections
        var userIds = Set<UUID>()
        for connection in connections + receivedRequests + sentRequests {
            userIds.insert(connection.fromUserId)
            userIds.insert(connection.toUserId)
        }

        // Load from local repository
        for userId in userIds {
            if let cachedUser = try? await dependencies.sharingRepository.fetchUser(id: userId) {
                usersMap[userId] = cachedUser
            }
        }
    }

    /// Ensure profile images are loaded into memory cache
    /// Called when using cached data to make sure images are ready for display
    private func ensureProfileImagesInCache() async {
        for user in usersMap.values {
            // Skip if already in memory cache
            let cacheKey = ImageCache.profileImageKey(userId: user.id)
            if ImageCache.shared.get(cacheKey) != nil {
                continue
            }

            // Load from local file into memory cache
            if let imageURL = user.profileImageURL,
               let imageData = try? Data(contentsOf: imageURL),
               let image = UIImage(data: imageData) {
                ImageCache.shared.set(cacheKey, image: image)
            }
        }
    }

    /// Preload profile images for all connected users
    private func preloadProfileImages(forceRefresh: Bool = false) async {
        // Preloading profile images (don't log routine operations)

        // Download images in parallel for better performance
        await withTaskGroup(of: (UUID, UIImage?).self) { group in
            for user in usersMap.values {
                // Skip if user doesn't have a cloud profile image and no local image
                guard user.cloudProfileImageRecordName != nil || user.profileImageURL != nil else {
                    continue
                }

                group.addTask { @MainActor in
                    let cacheKey = ImageCache.profileImageKey(userId: user.id)

                    // If already in memory cache and not force refreshing, skip
                    if !forceRefresh, ImageCache.shared.get(cacheKey) != nil {
                        return (user.id, nil)
                    }

                    // Try to load from local file first
                    if let imageURL = user.profileImageURL,
                       let imageData = try? Data(contentsOf: imageURL),
                       let image = UIImage(data: imageData) {
                        return (user.id, image)
                    }

                    // If no local file or force refreshing, download from CloudKit
                    if forceRefresh || user.profileImageURL == nil {
                        do {
                            if let downloadedURL = try await self.dependencies.profileImageManager.downloadImageFromCloud(userId: user.id),
                               let imageData = try? Data(contentsOf: downloadedURL),
                               let image = UIImage(data: imageData) {
                                // Downloaded profile image (don't log routine operations)
                                return (user.id, image)
                            }
                        } catch {
                            AppLogger.general.warning("⚠️ Failed to download profile image for \(user.username): \(error.localizedDescription)")
                        }
                    }

                    return (user.id, nil)
                }
            }

            // Collect results and load into memory cache
            for await (userId, image) in group {
                if let image = image {
                    let cacheKey = ImageCache.profileImageKey(userId: userId)
                    ImageCache.shared.set(cacheKey, image: image)
                }
            }
        }

        // Finished preloading profile images (don't log routine operations)
    }

    func acceptRequest(_ connection: Connection) async {
        do {
            try await dependencies.connectionManager.acceptConnection(connection)
            AppLogger.general.info("✅ Connection accepted successfully")
        } catch {
            alertMessage = "Failed to accept request: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    func rejectRequest(_ connection: Connection) async {
        do {
            try await dependencies.connectionManager.rejectConnection(connection)
            AppLogger.general.info("✅ Connection rejected successfully")
        } catch {
            alertMessage = "Failed to reject request: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
}

#Preview {
    NavigationStack {
        ConnectionsView(dependencies: .preview())
    }
}
