//
//  CollectionsListView.swift
//  Cauldron
//
//  Created by Claude on 10/29/25.
//

import SwiftUI

struct CollectionsListView: View {
    @Environment(\.dependencies) private var dependencies
    @StateObject private var viewModel: CollectionsListViewModel
    @State private var showingCreateSheet = false
    @State private var recipeImageCache: [UUID: [URL?]] = [:]  // Cache recipe images by collection ID

    init(dependencies: DependencyContainer) {
        _viewModel = StateObject(wrappedValue: CollectionsListViewModel(dependencies: dependencies))
    }

    var body: some View {
        ScrollView {
                VStack(spacing: 24) {
                    // My Collections Section
                    if !viewModel.filteredOwnedCollections.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            // Only show "My Collections" header if there are also saved collections
                            if !viewModel.filteredReferencedCollections.isEmpty {
                                Text("My Collections")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal)
                            }

                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)
                            ], spacing: 20) {
                                ForEach(viewModel.filteredOwnedCollections) { collection in
                                    NavigationLink(destination: CollectionDetailView(collection: collection, dependencies: dependencies)) {
                                        CollectionCardView(
                                            collection: collection,
                                            recipeImages: recipeImageCache[collection.id] ?? []
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .task(id: collection.id) {
                                        // Load recipe images if not cached
                                        if recipeImageCache[collection.id] == nil {
                                            let images = await viewModel.getRecipeImages(for: collection)
                                            recipeImageCache[collection.id] = images
                                        }
                                    }
                                    .contextMenu {
                                        Button {
                                            // TODO: Edit collection
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }

                                        Button(role: .destructive) {
                                            Task {
                                                await viewModel.deleteCollection(collection)
                                            }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Saved Collections Section (Referenced from friends)
                    if !viewModel.filteredReferencedCollections.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Saved Collections")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal)

                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)
                            ], spacing: 20) {
                                ForEach(viewModel.filteredReferencedCollections) { reference in
                                    NavigationLink {
                                        ReferencedCollectionDetailView(
                                            reference: reference,
                                            dependencies: dependencies
                                        )
                                    } label: {
                                        CollectionReferenceCardView(
                                            reference: reference,
                                            recipeImages: []  // TODO: Fetch first 4 recipe images
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            Task {
                                                await viewModel.deleteCollectionReference(reference)
                                            }
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Empty State
                    if viewModel.filteredOwnedCollections.isEmpty && viewModel.filteredReferencedCollections.isEmpty {
                        VStack(spacing: 16) {
                            Spacer()
                                .frame(height: 60)

                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)

                            Text("No Collections Yet")
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text("Create a collection to organize your recipes")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)

                            Button {
                                showingCreateSheet = true
                            } label: {
                                Label("Create Collection", systemImage: "plus.circle.fill")
                                    .font(.headline)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.cauldronOrange)
                            .padding(.top, 8)
                        }
                        .padding()
                    }
                }
                .padding(.vertical)
        }
        .navigationTitle("Collections")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $viewModel.searchText, prompt: "Search collections")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CollectionFormView()
                .environment(\.dependencies, dependencies)
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .task {
            await viewModel.loadCollections()
        }
        .refreshable {
            recipeImageCache.removeAll()  // Clear cache on refresh
            await viewModel.loadCollections()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecipeDeleted"))) { _ in
            recipeImageCache.removeAll()  // Clear image cache
            Task {
                await viewModel.loadCollections()
            }
        }
    }
}

#Preview {
    CollectionsListView(dependencies: DependencyContainer.preview())
}
