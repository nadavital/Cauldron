//
//  PeopleSearchSheet.swift
//  Cauldron
//
//  Dedicated sheet for finding friends and managing requests
//

import SwiftUI
import Combine

struct PeopleSearchSheet: View {
    let dependencies: DependencyContainer
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PeopleSearchViewModel

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: PeopleSearchViewModel(dependencies: dependencies))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Pending requests section (most important)
                    if !viewModel.receivedRequests.isEmpty {
                        pendingRequestsSection
                    }

                    // Sent requests section
                    if !viewModel.sentRequests.isEmpty {
                        sentRequestsSection
                    }

                    // Search results or suggestions
                    if viewModel.searchText.isEmpty {
                        suggestionsSection
                    } else {
                        searchResultsSection
                    }
                }
                .padding()
            }
            .navigationTitle("Find Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search people...")
            .task {
                await viewModel.loadData()
            }
            .refreshable {
                await viewModel.loadData()
            }
            .alert("Error", isPresented: $viewModel.showErrorAlert) {
                Button("OK") { }
            } message: {
                Text(viewModel.alertMessage)
            }
        }
    }

    // MARK: - Pending Requests Section

    private var pendingRequestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bell.badge.fill")
                    .foregroundColor(.cauldronOrange)
                Text("Pending Requests")
                    .font(.headline)
                Text("(\(viewModel.receivedRequests.count))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }

            ForEach(viewModel.receivedRequests, id: \.id) { connection in
                if let user = viewModel.usersMap[connection.fromUserId] {
                    PeopleSearchRequestCard(
                        user: user,
                        connection: connection,
                        dependencies: dependencies,
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
        .padding()
        .background(Color.cauldronSecondaryBackground)
        .cornerRadius(16)
    }

    // MARK: - Sent Requests Section

    private var sentRequestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "paperplane.fill")
                    .foregroundColor(.blue)
                Text("Sent Requests")
                    .font(.headline)
                Text("(\(viewModel.sentRequests.count))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }

            ForEach(viewModel.sentRequests, id: \.id) { connection in
                if let user = viewModel.usersMap[connection.toUserId] {
                    HStack(spacing: 12) {
                        ProfileAvatar(user: user, size: 44, dependencies: dependencies)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("@\(user.username)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text("Pending")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color.cauldronSecondaryBackground)
        .cornerRadius(16)
    }

    // MARK: - Suggestions Section

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !viewModel.recommendedUsers.isEmpty {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.cauldronOrange)
                    Text("Suggested for You")
                        .font(.headline)
                    Spacer()
                }

                ForEach(viewModel.recommendedUsers) { user in
                    PeopleSearchUserRow(
                        user: user,
                        dependencies: dependencies,
                        connectionState: viewModel.connectionState(for: user),
                        onConnect: {
                            await viewModel.sendConnectionRequest(to: user)
                        }
                    )
                }
            } else if !viewModel.isLoading {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "person.2.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("Search for People")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("Find friends to share recipes with")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
    }

    // MARK: - Search Results Section

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView("Searching...")
                    Spacer()
                }
                .padding(.vertical, 40)
            } else if viewModel.searchResults.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No matching users")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("Try searching for a different name")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                HStack {
                    Text("\(viewModel.searchResults.count) people found")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(.leading, 8)
                    }

                    Spacer()
                }

                ForEach(viewModel.searchResults) { user in
                    PeopleSearchUserRow(
                        user: user,
                        dependencies: dependencies,
                        connectionState: viewModel.connectionState(for: user),
                        onConnect: {
                            await viewModel.sendConnectionRequest(to: user)
                        }
                    )
                }
            }
        }
    }
}

// MARK: - People Search User Row

struct PeopleSearchUserRow: View {
    let user: User
    let dependencies: DependencyContainer
    let connectionState: PeopleSearchConnectionState
    let onConnect: () async -> Void

    @State private var isProcessing = false

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatar(user: user, size: 50, dependencies: dependencies)

            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.headline)

                Text("@\(user.username)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            connectionButton
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var connectionButton: some View {
        switch connectionState {
        case .none:
            Button {
                Task {
                    isProcessing = true
                    await onConnect()
                    isProcessing = false
                }
            } label: {
                if isProcessing {
                    ProgressView()
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.cauldronOrange)
                }
            }
            .disabled(isProcessing)

        case .pending:
            Text("Pending")
                .font(.caption)
                .foregroundColor(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)

        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.green)

        case .currentUser:
            Text("You")
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
        }
    }
}

// MARK: - People Search Request Card

struct PeopleSearchRequestCard: View {
    let user: User
    let connection: Connection
    let dependencies: DependencyContainer
    let onAccept: () async -> Void
    let onReject: () async -> Void

    @State private var isProcessing = false

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatar(user: user, size: 48, dependencies: dependencies)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("@\(user.username)")
                    .font(.caption)
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
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.green)
                            .clipShape(Circle())
                    }

                    Button {
                        Task {
                            isProcessing = true
                            await onReject()
                            isProcessing = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Connection State Enum

enum PeopleSearchConnectionState {
    case none
    case pending
    case connected
    case currentUser
}

// MARK: - View Model

@MainActor
class PeopleSearchViewModel: ObservableObject {
    @Published var searchText = "" {
        didSet {
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
                guard !Task.isCancelled else { return }
                await performSearch()
            }
        }
    }
    @Published var searchResults: [User] = []
    @Published var recommendedUsers: [User] = []
    @Published var receivedRequests: [Connection] = []
    @Published var sentRequests: [Connection] = []
    @Published var usersMap: [UUID: User] = [:]
    @Published var isLoading = false
    @Published var showErrorAlert = false
    @Published var alertMessage = ""

    let dependencies: DependencyContainer
    private var searchDebounceTask: Task<Void, Never>?

    var currentUserId: UUID {
        CurrentUserSession.shared.userId ?? UUID()
    }

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }

    func loadData() async {
        isLoading = true
        defer { isLoading = false }

        await loadConnections()
        await loadRecommendedUsers()
    }

    func loadConnections() async {
        let managedConnections = Array(dependencies.connectionManager.connections.values)

        receivedRequests = managedConnections
            .filter { $0.connection.toUserId == currentUserId && $0.connection.status == .pending }
            .map { $0.connection }

        sentRequests = managedConnections
            .filter { $0.connection.fromUserId == currentUserId && $0.connection.status == .pending }
            .map { $0.connection }

        // Load user details for all connections
        var userIds = Set<UUID>()
        for connection in receivedRequests {
            userIds.insert(connection.fromUserId)
        }
        for connection in sentRequests {
            userIds.insert(connection.toUserId)
        }

        for userId in userIds {
            if usersMap[userId] == nil {
                if let user = try? await dependencies.cloudKitService.fetchUser(byUserId: userId) {
                    usersMap[userId] = user
                }
            }
        }
    }

    func loadRecommendedUsers() async {
        do {
            // Get friends of friends as recommendations
            let friends = try await dependencies.connectionRepository.fetchAcceptedConnections(forUserId: currentUserId)
            var friendIds = Set<UUID>()
            for connection in friends {
                if let otherId = connection.otherUserId(currentUserId: currentUserId) {
                    friendIds.insert(otherId)
                }
            }

            // For now, just show some recent users as suggestions (could be improved with friend-of-friend logic)
            let allUsers = try await dependencies.cloudKitService.searchUsers(query: "")
            recommendedUsers = allUsers
                .filter { $0.id != currentUserId && !friendIds.contains($0.id) }
                .prefix(5)
                .map { $0 }
        } catch {
            AppLogger.general.error("Failed to load recommended users: \(error.localizedDescription)")
        }
    }

    func performSearch() async {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let users = try await dependencies.cloudKitService.searchUsers(query: searchText)
            searchResults = users.filter { $0.id != currentUserId }
        } catch {
            AppLogger.general.error("Failed to search users: \(error.localizedDescription)")
            searchResults = []
        }
    }

    func connectionState(for user: User) -> PeopleSearchConnectionState {
        if user.id == currentUserId {
            return .currentUser
        }

        if let managedConnection = dependencies.connectionManager.connectionStatus(with: user.id) {
            if managedConnection.connection.isAccepted {
                return .connected
            } else {
                return .pending
            }
        }

        return .none
    }

    func sendConnectionRequest(to user: User) async {
        do {
            try await dependencies.connectionManager.sendConnectionRequest(to: user.id, user: user)
            await loadConnections()
        } catch {
            alertMessage = "Failed to send connection request: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    func acceptRequest(_ connection: Connection) async {
        do {
            try await dependencies.connectionManager.acceptConnection(connection)
            await loadConnections()
        } catch {
            alertMessage = "Failed to accept request: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    func rejectRequest(_ connection: Connection) async {
        do {
            try await dependencies.connectionManager.rejectConnection(connection)
            await loadConnections()
        } catch {
            alertMessage = "Failed to reject request: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
}

#Preview {
    PeopleSearchSheet(dependencies: .preview())
}
