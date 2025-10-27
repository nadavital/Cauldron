//
//  SharingTabView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import SwiftUI
import os

/// Navigation destinations for SharingTab
enum SharingTabDestination: Hashable {
    case connections
}

/// Sections in the Sharing tab
enum SharingSection: String, CaseIterable {
    case recipes = "Recipes"
    case connections = "Connections"
}

/// Main sharing tab view showing shared recipes
struct SharingTabView: View {
    @ObservedObject private var viewModel = SharingTabViewModel.shared
    @StateObject private var userSession = CurrentUserSession.shared
    @State private var showingEditProfile = false
    @State private var navigationPath = NavigationPath()
    @State private var selectedSection: SharingSection = .recipes

    let dependencies: DependencyContainer

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                // Segmented control for switching sections
                Picker("Section", selection: $selectedSection) {
                    ForEach(SharingSection.allCases, id: \.self) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // Content based on selected section
                Group {
                    switch selectedSection {
                    case .recipes:
                        recipesSection
                    case .connections:
                        ConnectionsView(dependencies: dependencies)
                    }
                }
            }
            .navigationTitle("Sharing")
            .toolbar {
                
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let user = userSession.currentUser {
                            Button {
                                showingEditProfile = true
                            } label: {
                                Label("Edit Profile (@\(user.username))", systemImage: "person.circle")
                            }

                            #if DEBUG
                            Divider()
                            #endif
                        }

                        #if DEBUG
                        Button {
                            Task {
                                await viewModel.createDemoUsers()
                            }
                        } label: {
                            Label("Create Demo Users", systemImage: "person.2.fill")
                        }
                        #endif
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .task {
                // Configure dependencies if not already done
                viewModel.configure(dependencies: dependencies)
                await viewModel.loadSharedRecipes()
            }
            .refreshable {
                await viewModel.loadSharedRecipes()
            }
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView(dependencies: dependencies)
            }
            .alert("Success", isPresented: $viewModel.showSuccessAlert) {
                Button("OK") { }
            } message: {
                Text(viewModel.alertMessage)
            }
            .alert("Error", isPresented: $viewModel.showErrorAlert) {
                Button("OK") { }
            } message: {
                Text(viewModel.alertMessage)
            }
            .navigationDestination(for: SharingTabDestination.self) { destination in
                switch destination {
                case .connections:
                    ConnectionsView(dependencies: dependencies)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToConnections"))) { _ in
                // Navigate to connections when notification is tapped
                AppLogger.general.info("📍 Navigating to Connections from notification")
                selectedSection = .connections
            }
        }
    }

    private var recipesSection: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading shared recipes...")
            } else if viewModel.sharedRecipes.isEmpty {
                emptyState
            } else {
                recipesList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Shared Recipes")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Recipes shared with you will appear here")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            #if DEBUG
            Text("Tap the menu to create demo users for testing")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            #endif
        }
        .padding()
    }
    
    private var recipesList: some View {
        List {
            ForEach(viewModel.sharedRecipes) { sharedRecipe in
                NavigationLink(destination: SharedRecipeDetailView(
                    sharedRecipe: sharedRecipe,
                    dependencies: dependencies,
                    onCopy: {
                        await viewModel.copyToPersonalCollection(sharedRecipe)
                    },
                    onRemove: {
                        await viewModel.removeSharedRecipe(sharedRecipe)
                    }
                )) {
                    SharedRecipeRowView(sharedRecipe: sharedRecipe)
                }
            }
        }
    }
}

/// Row view for a shared recipe
struct SharedRecipeRowView: View {
    let sharedRecipe: SharedRecipe
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(sharedRecipe.recipe.title)
                    .font(.headline)
                
                Spacer()
                
                if let time = sharedRecipe.recipe.displayTime {
                    Label(time, systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                Label("Shared by \(sharedRecipe.sharedBy.displayName)", systemImage: "person.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(sharedRecipe.sharedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if !sharedRecipe.recipe.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(sharedRecipe.recipe.tags, id: \.name) { tag in
                            Text(tag.name)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.cauldronOrange.opacity(0.2))
                                .foregroundColor(.cauldronOrange)
                                .cornerRadius(6)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SharingTabView(dependencies: .preview())
}
