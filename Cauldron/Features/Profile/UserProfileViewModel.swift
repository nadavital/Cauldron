//
//  UserProfileViewModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import SwiftUI
import Combine
import os

/// View model for user profile view - handles connection management and user info
@MainActor
class UserProfileViewModel: ObservableObject {
    @Published var connectionState: ConnectionState = .loading
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var isProcessing = false

    let user: User
    let dependencies: DependencyContainer
    private var cancellables = Set<AnyCancellable>()

    enum ConnectionState: Equatable {
        case notConnected
        case pendingSent
        case pendingReceived
        case connected
        case loading
    }

    var currentUserId: UUID {
        CurrentUserSession.shared.userId ?? UUID()
    }

    var isCurrentUser: Bool {
        user.id == currentUserId
    }

    init(user: User, dependencies: DependencyContainer) {
        self.user = user
        self.dependencies = dependencies

        // Subscribe to connection manager updates for real-time state changes
        dependencies.connectionManager.$connections
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    await self.updateConnectionState()
                }
            }
            .store(in: &cancellables)
    }

    func loadConnectionStatus() async {
        await updateConnectionState()
    }

    private func updateConnectionState() async {
        // Don't show connection state for current user
        if isCurrentUser {
            connectionState = .notConnected
            return
        }

        connectionState = .loading

        // Get connection status from ConnectionManager
        if let managedConnection = dependencies.connectionManager.connectionStatus(with: user.id) {
            let connection = managedConnection.connection

            if connection.isAccepted {
                connectionState = .connected
            } else if connection.fromUserId == currentUserId {
                connectionState = .pendingSent
            } else {
                connectionState = .pendingReceived
            }
        } else {
            connectionState = .notConnected
        }
    }

    func sendConnectionRequest() async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            try await dependencies.connectionManager.sendConnectionRequest(to: user.id, user: user)
            AppLogger.general.info("✅ Connection request sent to \(self.user.username)")
        } catch {
            AppLogger.general.error("❌ Failed to send connection request: \(error.localizedDescription)")
            errorMessage = "Failed to send request: \(error.localizedDescription)"
            showError = true
        }
    }

    func acceptConnection() async {
        guard let managedConnection = dependencies.connectionManager.connectionStatus(with: user.id) else {
            AppLogger.general.error("No connection found to accept")
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            try await dependencies.connectionManager.acceptConnection(managedConnection.connection)
            AppLogger.general.info("✅ Connection accepted from \(self.user.username)")
        } catch {
            AppLogger.general.error("❌ Failed to accept connection: \(error.localizedDescription)")
            errorMessage = "Failed to accept: \(error.localizedDescription)"
            showError = true
        }
    }

    func rejectConnection() async {
        guard let managedConnection = dependencies.connectionManager.connectionStatus(with: user.id) else {
            AppLogger.general.error("No connection found to reject")
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            try await dependencies.connectionManager.rejectConnection(managedConnection.connection)
            AppLogger.general.info("✅ Connection rejected from \(self.user.username)")
        } catch {
            AppLogger.general.error("❌ Failed to reject connection: \(error.localizedDescription)")
            errorMessage = "Failed to reject: \(error.localizedDescription)"
            showError = true
        }
    }

    func removeConnection() async {
        guard let managedConnection = dependencies.connectionManager.connectionStatus(with: user.id) else {
            AppLogger.general.error("No connection found to remove")
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            try await dependencies.connectionManager.deleteConnection(managedConnection.connection)
            AppLogger.general.info("✅ Connection removed with \(self.user.username)")
        } catch {
            AppLogger.general.error("❌ Failed to remove connection: \(error.localizedDescription)")
            errorMessage = "Failed to remove connection: \(error.localizedDescription)"
            showError = true
        }
    }

    func cancelConnectionRequest() async {
        guard let managedConnection = dependencies.connectionManager.connectionStatus(with: user.id) else {
            AppLogger.general.error("No connection found to cancel")
            return
        }

        // Verify it's a pending request sent by current user
        guard managedConnection.connection.fromUserId == currentUserId &&
              managedConnection.connection.status == .pending else {
            AppLogger.general.error("Connection is not a pending sent request")
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            try await dependencies.connectionManager.deleteConnection(managedConnection.connection)
            AppLogger.general.info("✅ Connection request canceled to \(self.user.username)")
        } catch {
            AppLogger.general.error("❌ Failed to cancel connection request: \(error.localizedDescription)")
            errorMessage = "Failed to cancel request: \(error.localizedDescription)"
            showError = true
        }
    }
}
