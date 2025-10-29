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
                ProfileAvatar(user: user, size: 60)

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
                ProfileAvatar(user: user, size: 60)

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
                ProfileAvatar(user: user, size: 60)

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
        await loadUserDetails()
    }

    private func loadUserDetails() async {
        // Get all unique user IDs from connections
        var userIds = Set<UUID>()
        for connection in connections + receivedRequests + sentRequests {
            userIds.insert(connection.fromUserId)
            userIds.insert(connection.toUserId)
        }

        // Fetch users - try local cache first, then CloudKit
        for userId in userIds {
            // Skip if already loaded
            guard usersMap[userId] == nil else { continue }

            // Try to get from local cache first
            if let cachedUser = try? await dependencies.sharingRepository.fetchUser(id: userId) {
                usersMap[userId] = cachedUser
            } else {
                // If not cached, fetch from CloudKit and cache locally
                if let cloudUser = try? await dependencies.cloudKitService.fetchUser(byUserId: userId) {
                    usersMap[userId] = cloudUser
                    try? await dependencies.sharingRepository.save(cloudUser)
                    AppLogger.general.info("Fetched and cached user from CloudKit: \(cloudUser.username)")
                } else {
                    AppLogger.general.warning("Could not find user \(userId) in cache or CloudKit")
                }
            }
        }

        AppLogger.general.info("Loaded connections via ConnectionManager")
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
