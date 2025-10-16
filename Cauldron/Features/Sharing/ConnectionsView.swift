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
                            ConnectionRequestRowView(
                                user: user,
                                connection: connection,
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
            }
            
            // Active connections
            if !viewModel.connections.isEmpty {
                Section("Connections") {
                    ForEach(viewModel.connections, id: \.id) { connection in
                        if let otherUserId = connection.otherUserId(currentUserId: viewModel.currentUserId),
                           let user = viewModel.usersMap[otherUserId] {
                            UserRowView(user: user)
                        }
                    }
                }
            }
            
            // Sent requests (pending)
            if !viewModel.sentRequests.isEmpty {
                Section("Sent Requests") {
                    ForEach(viewModel.sentRequests, id: \.id) { connection in
                        if let user = viewModel.usersMap[connection.toUserId] {
                            HStack {
                                UserRowView(user: user)
                                Spacer()
                                Text("Pending")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
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
        VStack(alignment: .leading, spacing: 12) {
            UserRowView(user: user)
            
            HStack(spacing: 12) {
                Button {
                    Task {
                        isProcessing = true
                        await onAccept()
                        isProcessing = false
                    }
                } label: {
                    Text("Accept")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.cauldronOrange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(isProcessing)
                
                Button {
                    Task {
                        isProcessing = true
                        await onReject()
                        isProcessing = false
                    }
                } label: {
                    Text("Reject")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                }
                .disabled(isProcessing)
            }
        }
        .padding(.vertical, 4)
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
    
    var currentUserId: UUID {
        CurrentUserSession.shared.userId ?? UUID()
    }
    
    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }
    
    func loadConnections() async {
        do {
            // Fetch connections from CloudKit PUBLIC database
            let allConnections = try await dependencies.cloudKitService.fetchConnections(forUserId: currentUserId)

            // Also cache locally for offline access
            for connection in allConnections {
                try? await dependencies.connectionRepository.save(connection)
            }

            connections = allConnections.filter { $0.isAccepted }
            receivedRequests = allConnections.filter { $0.toUserId == currentUserId && $0.status == .pending }
            sentRequests = allConnections.filter { $0.fromUserId == currentUserId && $0.status == .pending }

            // Load user details for all connections from CloudKit
            var userIds = Set<UUID>()
            for connection in allConnections {
                userIds.insert(connection.fromUserId)
                userIds.insert(connection.toUserId)
            }

            // Fetch users from CloudKit by searching
            for userId in userIds {
                // Try to get from local cache first
                if let cachedUser = try? await dependencies.sharingRepository.fetchUser(id: userId) {
                    usersMap[userId] = cachedUser
                }
                // Note: If user not in cache, they won't show. This is okay because
                // users should be cached when connection was created
            }

            AppLogger.general.info("Loaded \(allConnections.count) connections from CloudKit (\(self.receivedRequests.count) pending)")
        } catch {
            AppLogger.general.error("Failed to load connections: \(error.localizedDescription)")
            alertMessage = error.localizedDescription
            showErrorAlert = true
        }
    }
    
    func acceptRequest(_ connection: Connection) async {
        do {
            // Accept via CloudKit (updates PUBLIC database)
            try await dependencies.cloudKitService.acceptConnectionRequest(connection)

            // Also update local cache
            let accepted = Connection(
                id: connection.id,
                fromUserId: connection.fromUserId,
                toUserId: connection.toUserId,
                status: .accepted,
                createdAt: connection.createdAt,
                updatedAt: Date()
            )
            try? await dependencies.connectionRepository.save(accepted)

            await loadConnections()
        } catch {
            alertMessage = "Failed to accept request: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    func rejectRequest(_ connection: Connection) async {
        do {
            // Delete from CloudKit PUBLIC database
            try await dependencies.cloudKitService.deleteConnection(connection)

            // Also delete from local cache
            try? await dependencies.connectionRepository.delete(connection)

            await loadConnections()
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
