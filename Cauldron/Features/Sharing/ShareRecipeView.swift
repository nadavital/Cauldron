//
//  ShareRecipeView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import SwiftUI
import CloudKit
import os
import Combine

/// View for sharing a recipe with other users
struct ShareRecipeView: View {
    let recipe: Recipe
    let dependencies: DependencyContainer
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ShareRecipeViewModel
    
    init(recipe: Recipe, dependencies: DependencyContainer) {
        self.recipe = recipe
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: ShareRecipeViewModel(
            recipe: recipe,
            dependencies: dependencies
        ))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Share Link Button
                shareLinkSection

                Divider()
                    .padding(.vertical, 8)

                if viewModel.isLoading {
                    ProgressView("Loading users...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.availableUsers.isEmpty {
                    emptyState
                } else {
                    usersList
                }
            }
            .navigationTitle("Share Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadUsers()
            }
            .alert("Success", isPresented: $viewModel.showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text(viewModel.alertMessage)
            }
            .alert("Error", isPresented: $viewModel.showErrorAlert) {
                Button("OK") { }
            } message: {
                Text(viewModel.alertMessage)
            }
            .sheet(item: $viewModel.shareURL) { url in
                ShareSheet(items: [url.value])
            }
        }
    }

    private var shareLinkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Share via Link")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)

            Button {
                Task {
                    await viewModel.generateShareLink()
                }
            } label: {
                HStack {
                    Image(systemName: "link.circle.fill")
                        .font(.title2)
                        .foregroundColor(.cauldronOrange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Generate iCloud Share Link")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("Works with anyone who has iCloud")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if viewModel.isGeneratingLink {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.cauldronOrange.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            .disabled(viewModel.isGeneratingLink)

            #if DEBUG
            if viewModel.generatedURL != nil {
                VStack(spacing: 12) {
                    Button {
                        Task {
                            await viewModel.testAcceptShare()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Test Accept Share (iCloud URL)")
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                Text("Tests the iCloud share URL")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    if viewModel.deepLinkURL != nil {
                        Button {
                            Task {
                                await viewModel.testAcceptCustomDeepLink()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "link.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.purple)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Test Custom Deep Link")
                                        .font(.headline)
                                        .foregroundColor(.primary)

                                    Text("For local development testing")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                            .padding()
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }

                        Button {
                            if let deepLink = viewModel.deepLinkURL {
                                UIPasteboard.general.string = deepLink.absoluteString
                                AppLogger.general.info("📋 Copied custom deep link to clipboard")
                            }
                        } label: {
                            HStack {
                                Image(systemName: "doc.on.clipboard.fill")
                                    .font(.title2)
                                    .foregroundColor(.green)

                                Text("Copy Deep Link for Messages")
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                Spacer()
                            }
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                    }
                }
            }
            #endif
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Users Found")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Create demo users from the Sharing tab to test recipe sharing")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var usersList: some View {
        List {
            Section {
                Text("Share '\(recipe.title)' with:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Section {
                ForEach(viewModel.availableUsers) { user in
                    Button {
                        Task {
                            await viewModel.shareRecipe(with: user)
                        }
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color.cauldronOrange.opacity(0.3))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Text(user.displayName.prefix(2).uppercased())
                                        .font(.subheadline)
                                        .foregroundColor(.cauldronOrange)
                                )
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.displayName)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("@\(user.username)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if viewModel.sharingInProgress {
                                ProgressView()
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundColor(.cauldronOrange)
                            }
                        }
                    }
                    .disabled(viewModel.sharingInProgress)
                }
            }
        }
    }
}

// Identifiable wrapper for URL
struct IdentifiableURL: Identifiable {
    let id = UUID()
    let value: URL
}

@MainActor
class ShareRecipeViewModel: ObservableObject {
    @Published var availableUsers: [User] = []
    @Published var isLoading = false
    @Published var sharingInProgress = false
    @Published var isGeneratingLink = false
    @Published var shareURL: IdentifiableURL?
    @Published var showSuccessAlert = false
    @Published var showErrorAlert = false
    @Published var alertMessage = ""
    @Published var generatedURL: URL?  // Store the URL for testing
    @Published var deepLinkURL: URL?  // Custom deep link for testing

    let recipe: Recipe
    let dependencies: DependencyContainer

    var currentUser: User? {
        CurrentUserSession.shared.currentUser
    }

    init(recipe: Recipe, dependencies: DependencyContainer) {
        self.recipe = recipe
        self.dependencies = dependencies
    }
    
    func loadUsers() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            availableUsers = try await dependencies.sharingService.getAllUsers()
            AppLogger.general.info("Loaded \(self.availableUsers.count) users for sharing")
        } catch {
            AppLogger.general.error("Failed to load users: \(error.localizedDescription)")
            alertMessage = "Failed to load users: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
    
    func shareRecipe(with user: User) async {
        sharingInProgress = true
        defer { sharingInProgress = false }

        guard let currentUser = currentUser else {
            alertMessage = "You must be signed in to share recipes"
            showErrorAlert = true
            return
        }

        do {
            try await dependencies.sharingService.shareRecipe(
                recipe,
                with: user,
                from: currentUser
            )

            alertMessage = "Recipe shared with \(user.displayName)!"
            showSuccessAlert = true
            AppLogger.general.info("Successfully shared recipe with \(user.username)")
        } catch {
            AppLogger.general.error("Failed to share recipe: \(error.localizedDescription)")
            alertMessage = "Failed to share recipe: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    func generateShareLink() async {
        isGeneratingLink = true
        defer { isGeneratingLink = false }

        guard let currentUser = currentUser else {
            alertMessage = "You must be signed in to share recipes"
            showErrorAlert = true
            return
        }

        // Check iCloud availability first
        let isAvailable = await dependencies.cloudKitService.isCloudKitAvailable()
        if !isAvailable {
            alertMessage = "Please sign in to iCloud in Settings to share recipes"
            showErrorAlert = true
            return
        }

        do {
            let iCloudURL = try await dependencies.cloudKitService.createShareLink(
                for: recipe,
                ownerId: currentUser.id
            )
            generatedURL = iCloudURL

            // Generate custom deep link for local testing
            // Format: cauldron://share?url={encoded_icloud_url}
            if let encodedURL = iCloudURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let customDeepLink = URL(string: "cauldron://share?url=\(encodedURL)") {
                deepLinkURL = customDeepLink
                AppLogger.general.info("🔗 Generated custom deep link: \(customDeepLink.absoluteString)")
            }

            // For now, share the iCloud URL (will work in TestFlight/production)
            // Users can manually test with custom deep link via debug button
            shareURL = IdentifiableURL(value: iCloudURL)
            AppLogger.general.info("☁️ Generated iCloud share link: \(iCloudURL)")
        } catch let error as CKError {
            AppLogger.general.error("☁️ CloudKit error generating share link: \(error.localizedDescription)")

            switch error.code {
            case .notAuthenticated:
                alertMessage = "Please sign in to iCloud in Settings to share recipes"
            case .networkFailure, .networkUnavailable:
                alertMessage = "Network error. Please check your internet connection"
            case .quotaExceeded:
                alertMessage = "iCloud storage is full. Please free up space in Settings"
            default:
                alertMessage = "Failed to generate share link: \(error.localizedDescription)"
            }
            showErrorAlert = true
        } catch {
            AppLogger.general.error("❌ Failed to generate share link: \(error.localizedDescription)")
            alertMessage = "Failed to generate share link: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    #if DEBUG
    func testAcceptShare() async {
        guard let url = generatedURL else {
            AppLogger.general.warning("No URL to test with")
            return
        }

        AppLogger.general.info("🧪 Testing share acceptance with iCloud URL: \(url)")

        // Manually trigger the URL handling
        await MainActor.run {
            NotificationCenter.default.post(
                name: NSNotification.Name("TestOpenURL"),
                object: url
            )
        }
    }

    func testAcceptCustomDeepLink() async {
        guard let url = deepLinkURL else {
            AppLogger.general.warning("No custom deep link to test with")
            return
        }

        AppLogger.general.info("🧪 Testing share acceptance with custom deep link: \(url)")

        // Manually trigger the URL handling
        await MainActor.run {
            NotificationCenter.default.post(
                name: NSNotification.Name("TestOpenURL"),
                object: url
            )
        }
    }
    #endif
}

#Preview {
    ShareRecipeView(
        recipe: Recipe(
            title: "Test Recipe",
            ingredients: [],
            steps: []
        ),
        dependencies: .preview()
    )
}
