//
//  ShareRecipeView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import SwiftUI
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

@MainActor
class ShareRecipeViewModel: ObservableObject {
    @Published var availableUsers: [User] = []
    @Published var isLoading = false
    @Published var sharingInProgress = false
    @Published var showSuccessAlert = false
    @Published var showErrorAlert = false
    @Published var alertMessage = ""
    
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
