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

                // Recipes Section
                recipesSection
            }
            .padding()
        }
        .navigationTitle(user.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadConnectionStatus()
            await viewModel.loadUserRecipes()
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

            // Username and Connection Status Badge
            HStack(spacing: 8) {
                Text("@\(user.username)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if !viewModel.isCurrentUser {
                    connectionStatusBadge
                }
            }
        }
        .padding(.top)
    }

    @ViewBuilder
    private var connectionStatusBadge: some View {
        switch viewModel.connectionState {
        case .connected:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                Text("Connected")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.15))
            .cornerRadius(8)

        case .pendingSent:
            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(.caption)
                Text("Pending")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.15))
            .cornerRadius(8)

        case .pendingReceived:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption)
                Text("Wants to Connect")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.15))
            .cornerRadius(8)

        case .notConnected, .loading:
            EmptyView()
        }
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
            Label("Request Sent", systemImage: "clock")
                .font(.headline)
                .foregroundColor(.secondary)
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

    private var recipesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            Label("Recipes", systemImage: "book")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)

            // Content
            if viewModel.isLoadingRecipes {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 40)
            } else if viewModel.filteredRecipes.isEmpty {
                emptyRecipesState
            } else {
                recipesGrid
            }
        }
    }

    private var emptyRecipesState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text(emptyStateMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyStateMessage: String {
        if viewModel.connectionState == .connected {
            return "\(user.displayName) hasn't shared any recipes yet"
        } else {
            return "\(user.displayName) hasn't made any recipes public yet"
        }
    }

    private var recipesGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ], spacing: 16) {
            ForEach(viewModel.filteredRecipes, id: \.id) { sharedRecipe in
                NavigationLink(destination: SharedRecipeDetailView(
                    sharedRecipe: sharedRecipe,
                    dependencies: viewModel.dependencies,
                    onCopy: {
                        // Reload recipes after copying
                        await viewModel.loadUserRecipes()
                    },
                    onRemove: {
                        // Reload recipes after removing
                        await viewModel.loadUserRecipes()
                    }
                )) {
                    RecipeCard(sharedRecipe: sharedRecipe)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Recipe Card

struct RecipeCard: View {
    let sharedRecipe: SharedRecipe

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image
            if let imageURL = sharedRecipe.recipe.imageURL {
                RecipeImageView(previewImageURL: imageURL, showPlaceholderText: false)
                    .frame(height: 120)
                    .clipped()
            } else {
                placeholderImage
            }

            // Title
            Text(sharedRecipe.recipe.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(2)
                .foregroundColor(.primary)

            // Meta info
            HStack(spacing: 8) {
                if let time = sharedRecipe.recipe.displayTime {
                    Label(time, systemImage: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Visibility indicator
                Image(systemName: sharedRecipe.recipe.visibility.icon)
                    .font(.caption2)
                    .foregroundColor(sharedRecipe.recipe.visibility == .publicRecipe ? .green : .cauldronOrange)
            }
        }
        .padding(12)
        .background(Color.cauldronSecondaryBackground)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    private var placeholderImage: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.cauldronOrange.opacity(0.08),
                    Color.cauldronOrange.opacity(0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "fork.knife")
                .font(.system(size: 36))
                .foregroundStyle(Color.cauldronOrange.opacity(0.3))
        }
        .frame(height: 120)
        .clipped()
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
