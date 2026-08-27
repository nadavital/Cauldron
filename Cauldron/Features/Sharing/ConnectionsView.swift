//
//  ConnectionsView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import SwiftUI
import os

/// View for managing connections/friends
struct ConnectionsView: View {
    @State private var viewModel: ConnectionsViewModel

    init(dependencies: DependencyContainer) {
        _viewModel = State(initialValue: ConnectionsViewModel(dependencies: dependencies))
    }
    
    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 2) {
                LazyVStack(spacing: 0) {
                if RuntimeEnvironment.forceSkeletonLoading || viewModel.isColdLoading {
                    UserRowSkeletonList()
                        .padding(.horizontal, Theme.Spacing.md)
                }
                // Pending requests received
                if !viewModel.isColdLoading && !RuntimeEnvironment.forceSkeletonLoading && !viewModel.receivedRequests.isEmpty {
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
                if !viewModel.isColdLoading && !RuntimeEnvironment.forceSkeletonLoading && !viewModel.connections.isEmpty {
                    sectionHeader(title: "Friends", icon: "person.2.fill", color: .green)

                    ForEach(viewModel.connections, id: \.id) { connection in
                        if let otherUserId = connection.otherUserId(currentUserId: viewModel.currentUserId),
                           let user = viewModel.usersMap[otherUserId] {
                            ConnectionCard(user: user, dependencies: viewModel.dependencies)
                        }
                    }
                }

                // Sent requests (pending)
                if !viewModel.isColdLoading && !RuntimeEnvironment.forceSkeletonLoading && !viewModel.sentRequests.isEmpty {
                    sectionHeader(title: "Sent Requests", icon: "paperplane.fill", color: .blue)

                    ForEach(viewModel.sentRequests, id: \.id) { connection in
                        if let user = viewModel.usersMap[connection.toUserId] {
                            SentRequestCard(user: user, dependencies: viewModel.dependencies)
                        }
                    }
                }

                // Empty state
                if !viewModel.isColdLoading && !RuntimeEnvironment.forceSkeletonLoading && viewModel.connections.isEmpty && viewModel.receivedRequests.isEmpty && viewModel.sentRequests.isEmpty {
                    AppStateView(
                        kind: .empty(systemImage: "person.2.circle"),
                        title: "No Friends Yet",
                        message: "Find people to start sharing recipes and collections."
                    )
                    .frame(minHeight: 360)
                    .padding(.horizontal, Theme.Spacing.md)
                }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .appPageChrome()
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
        HStack {
            SectionHeaderLabel(title: title, systemImage: icon, iconColor: color)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.top, Theme.Spacing.xs)
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
        HStack(spacing: Theme.Spacing.sm) {
            // Avatar - smaller and more compact
            NavigationLink {
                UserProfileView(user: user, dependencies: dependencies)
            } label: {
                ProfileAvatar(user: user, size: 40, dependencies: dependencies)
                    .frame(
                        minWidth: Theme.HitTarget.minimum,
                        minHeight: Theme.HitTarget.minimum
                    )
            }
            .buttonStyle(.plain)

            // User info - more compact
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("@\(user.username)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isProcessing {
                ProgressView()
                    .controlSize(.small)
                    .frame(
                        minWidth: Theme.HitTarget.minimum,
                        minHeight: Theme.HitTarget.minimum
                    )
            } else {
                HStack(spacing: Theme.Spacing.xs) {
                    IconActionButton(
                        "Accept friend request",
                        systemImage: "checkmark",
                        style: .tinted,
                        tint: .green
                    ) {
                        guard !isProcessing else { return }
                        isProcessing = true
                        Task {
                            await onAccept()
                            isProcessing = false
                        }
                    }

                    IconActionButton(
                        "Decline friend request",
                        systemImage: "xmark",
                        style: .tinted,
                        tint: .red
                    ) {
                        guard !isProcessing else { return }
                        isProcessing = true
                        Task {
                            await onReject()
                            isProcessing = false
                        }
                    }
                }
            }
        }
        .padding(Theme.Spacing.sm)
        .appSurface(.glass)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xxs)
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
            ConnectionPersonRow(user: user, dependencies: dependencies)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
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
            ConnectionPersonRow(
                user: user,
                dependencies: dependencies,
                status: "Pending"
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
    }
}

private struct ConnectionPersonRow: View {
    let user: User
    let dependencies: DependencyContainer
    var status: String? = nil

    var body: some View {
        AppCard(style: .glass) {
            HStack(spacing: Theme.Spacing.md) {
                ProfileAvatar(user: user, size: 60, dependencies: dependencies)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(user.displayName)
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(.primary)

                    Text("@\(user.username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let status {
                        Label(status, systemImage: "clock")
                            .font(Theme.Typography.metadata)
                            .foregroundStyle(.blue)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

@MainActor
@Observable
final class ConnectionsViewModel {
    var connections: [Connection] = []
    var receivedRequests: [Connection] = []
    var sentRequests: [Connection] = []
    var usersMap: [UUID: User] = [:]
    var showErrorAlert = false
    var alertMessage = ""
    private(set) var isLoading = true
    private(set) var hasLoadedOnce = false

    var isColdLoading: Bool {
        SkeletonPresentationPolicy.shouldShow(
            isLoading: isLoading,
            hasResolvedOnce: hasLoadedOnce,
            hasContent: !connections.isEmpty || !receivedRequests.isEmpty || !sentRequests.isEmpty
        )
    }

    let dependencies: DependencyContainer
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
    }

    // Required to prevent crashes in XCTest due to Swift bug #85221
    nonisolated deinit {}

    func loadConnections(forceRefresh: Bool = false) async {
        isLoading = true
        defer {
            isLoading = false
            hasLoadedOnce = true
        }
        // Use ConnectionManager - it handles caching and sync automatically
        await dependencies.connectionManager.loadConnections(forUserId: currentUserId, forceRefresh: forceRefresh)

        // Update connections from manager
        updateConnectionsFromManager()

        // Load user details for all connections
        await loadUserDetails(forceRefresh: forceRefresh)
    }

    /// Update local connection arrays from ConnectionManager
    private func updateConnectionsFromManager() {
        let managedConnections = dependencies.connectionManager.connections
        let all = Array(managedConnections.values)

        connections = all.filter { $0.connection.isAccepted }.map { $0.connection }
        receivedRequests = all.filter {
            $0.connection.toUserId == currentUserId &&
            $0.connection.status == .pending
        }.map { $0.connection }
        sentRequests = all.filter {
            $0.connection.fromUserId == currentUserId &&
            $0.connection.status == .pending
        }.map { $0.connection }
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
                ImageCache.shared.clearProfileImages()
            }

            // Batch fetch users from CloudKit (single query instead of N queries)
            if let cloudUsers = try? await dependencies.userCloudService.fetchUsers(byUserIds: Array(userIds)) {
                for cloudUser in cloudUsers {
                    usersMap[cloudUser.id] = cloudUser
                    await bestEffort("Cache connection user") {
                        try await dependencies.sharingRepository.save(cloudUser)
                    }
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
        await dependencies.entityImageLoader.ensureProfileImagesInCache(users: Array(usersMap.values))
    }

    /// Preload profile images for all connected users
    private func preloadProfileImages(forceRefresh: Bool = false) async {
        await dependencies.entityImageLoader.preloadProfileImages(
            users: Array(usersMap.values),
            dependencies: dependencies,
            forceRefresh: forceRefresh
        )
    }

    func acceptRequest(_ connection: Connection) async {
        do {
            try await dependencies.connectionManager.acceptConnection(connection)
            updateConnectionsFromManager()
            AppLogger.general.info("✅ Connection accepted successfully")
        } catch {
            alertMessage = "Failed to accept request: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    func rejectRequest(_ connection: Connection) async {
        do {
            try await dependencies.connectionManager.rejectConnection(connection)
            updateConnectionsFromManager()
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
