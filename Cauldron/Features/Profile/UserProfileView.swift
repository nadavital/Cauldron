//
//  UserProfileView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import SwiftUI

/// User profile view - displays user information and manages connections
struct UserProfileView: View {
    let user: User
    @StateObject private var viewModel: UserProfileViewModel
    @Environment(\.dismiss) private var dismiss

    init(user: User, dependencies: DependencyContainer) {
        self.user = user
        _viewModel = StateObject(wrappedValue: UserProfileViewModel(
            user: user,
            dependencies: dependencies
        ))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Profile Header
                profileHeader

                // Connection Management Section
                if !viewModel.isCurrentUser {
                    connectionSection
                }

                Spacer()
            }
            .padding()
        }
        .navigationTitle(user.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadConnectionStatus()
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 16) {
            // Avatar
            Circle()
                .fill(Color.cauldronOrange.opacity(0.3))
                .frame(width: 100, height: 100)
                .overlay(
                    Text(user.displayName.prefix(2).uppercased())
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.cauldronOrange)
                )

            // Display Name
            Text(user.displayName)
                .font(.title2)
                .fontWeight(.bold)

            // Username
            Text("@\(user.username)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top)
    }

    @ViewBuilder
    private var connectionSection: some View {
        VStack(spacing: 12) {
            if viewModel.isProcessing {
                ProgressView()
                    .padding()
            } else {
                switch viewModel.connectionState {
                case .notConnected:
                    connectButton
                case .pendingSent:
                    pendingText
                case .pendingReceived:
                    pendingReceivedButtons
                case .connected:
                    connectedSection
                case .loading:
                    ProgressView()
                }
            }
        }
        .padding(.horizontal)
    }

    private var connectButton: some View {
        Button {
            Task {
                await viewModel.sendConnectionRequest()
            }
        } label: {
            Label("Connect", systemImage: "person.badge.plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.cauldronOrange)
                .foregroundColor(.white)
                .cornerRadius(12)
        }
        .disabled(viewModel.isProcessing)
    }

    private var pendingReceivedButtons: some View {
        VStack(spacing: 12) {
            Text("Connection Request")
                .font(.headline)
                .padding(.bottom, 4)

            HStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.acceptConnection()
                    }
                } label: {
                    Label("Accept", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(viewModel.isProcessing)

                Button {
                    Task {
                        await viewModel.rejectConnection()
                    }
                } label: {
                    Label("Reject", systemImage: "xmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(viewModel.isProcessing)
            }
        }
    }

    private var connectedSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
                Text("Connected")
                    .font(.headline)
            }
            .padding(.bottom, 8)

            Button(role: .destructive) {
                Task {
                    await viewModel.removeConnection()
                }
            } label: {
                Label("Remove Connection", systemImage: "person.badge.minus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(12)
            }
            .disabled(viewModel.isProcessing)
        }
    }

    private var pendingText: some View {
        VStack(spacing: 12) {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Request Sent")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            Text("Waiting for \(user.displayName) to respond")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

            Button(role: .destructive) {
                Task {
                    await viewModel.cancelConnectionRequest()
                }
            } label: {
                Label("Cancel Request", systemImage: "xmark.circle")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(8)
            }
            .disabled(viewModel.isProcessing)
        }
        .padding()
    }
}

#Preview {
    NavigationStack {
        UserProfileView(
            user: User(username: "chef_julia", displayName: "Julia Child"),
            dependencies: .preview()
        )
    }
}
