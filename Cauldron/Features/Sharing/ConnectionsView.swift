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
        List {
            // Pending requests received
            if !viewModel.receivedRequests.isEmpty {
                Section("Pending Requests") {
                    ForEach(viewModel.receivedRequests, id: \.id) { connection in
                        if let user = viewModel.usersMap[connection.fromUserId] {
                            NavigationLink {
                                UserProfileView(user: user, dependencies: viewModel.dependencies)
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color.cauldronOrange.opacity(0.3))
                                        .frame(width: 50, height: 50)
                                        .overlay(
                                            Text(user.displayName.prefix(2).uppercased())
                                                .font(.headline)
                                                .foregroundColor(.cauldronOrange)
                                        )

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(user.displayName)
                                            .font(.headline)

                                        Text("@\(user.username)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    // Visual indicator for pending request
                                    Text("New Request")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.cauldronOrange.opacity(0.2))
                                        .foregroundColor(.cauldronOrange)
                                        .cornerRadius(8)
                                }
                                .padding(.vertical, 8)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task {
                                        await viewModel.rejectRequest(connection)
                                    }
                                } label: {
                                    Label("Reject", systemImage: "xmark")
                                }

                                Button {
                                    Task {
                                        await viewModel.acceptRequest(connection)
                                    }
                                } label: {
                                    Label("Accept", systemImage: "checkmark")
                                }
                                .tint(.green)
                            }
                        }
                    }
                }
            }

            // Active connections
            if !viewModel.connections.isEmpty {
                Section("Connections") {
                    ForEach(viewModel.connections, id: \.id) { connection in
                        if let otherUserId = connection.otherUserId(currentUserId: viewModel.currentUserId),
                           let user = viewModel.usersMap[otherUserId] {
                            NavigationLink {
                                UserProfileView(user: user, dependencies: viewModel.dependencies)
                            } label: {
                                UserRowView(user: user)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Sent requests (pending)
            if !viewModel.sentRequests.isEmpty {
                Section("Sent Requests") {
                    ForEach(viewModel.sentRequests, id: \.id) { connection in
                        if let user = viewModel.usersMap[connection.toUserId] {
                            NavigationLink {
                                UserProfileView(user: user, dependencies: viewModel.dependencies)
                            } label: {
                                HStack {
                                    UserRowView(user: user)
                                    Spacer()
                                    Text("Pending")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            if viewModel.connections.isEmpty && viewModel.receivedRequests.isEmpty && viewModel.sentRequests.isEmpty {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Connections Yet")
                            .font(.headline)
                        Text("Search for users in the Search tab to connect")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
        }
        .navigationTitle("Connections")
        .task {
            await viewModel.loadConnections()
        }
        .refreshable {
            await viewModel.loadConnections()
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
}

/// Row view for a connection request
struct ConnectionRequestRowView: View {
    let user: User
    let connection: Connection
    let onAccept: () async -> Void
    let onReject: () async -> Void

    @State private var isProcessing = false

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.cauldronOrange.opacity(0.3))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(user.displayName.prefix(2).uppercased())
                        .font(.headline)
                        .foregroundColor(.cauldronOrange)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.headline)

                Text("@\(user.username)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isProcessing {
                ProgressView()
            } else {
                HStack(spacing: 8) {
                    Button {
                        Task {
                            isProcessing = true
                            await onAccept()
                            isProcessing = false
                        }
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.green)
                    }
                    .disabled(isProcessing)

                    Button {
                        Task {
                            isProcessing = true
                            await onReject()
                            isProcessing = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.red)
                    }
                    .disabled(isProcessing)
                }
            }
        }
        .padding(.vertical, 8)
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
    
    func loadConnections() async {
        // Use ConnectionManager - it handles caching and sync automatically
        await dependencies.connectionManager.loadConnections(forUserId: currentUserId)

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
