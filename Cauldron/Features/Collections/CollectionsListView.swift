//
//  CollectionsListView.swift
//  Cauldron
//
//  Created by Claude on 10/29/25.
//

import SwiftUI

struct CollectionsListView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var viewModel: CollectionsListViewModel
    @State private var showingCreateSheet = false

    init(dependencies: DependencyContainer) {
        _viewModel = State(initialValue: CollectionsListViewModel(dependencies: dependencies))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                collectionSection(
                    title: "My Collections",
                    collections: viewModel.filteredOwnedCollections,
                    isSavedSection: false
                )

                collectionSection(
                    title: "Saved Collections",
                    collections: viewModel.filteredSavedCollections,
                    isSavedSection: true
                )

                // Empty State
                if !viewModel.hasVisibleCollections {
                    EmptyStateView(
                        title: "No Collections Yet",
                        message: "Create a collection to organize your recipes.",
                        systemImage: "folder.badge.plus",
                        actionTitle: "Create Collection",
                        action: { showingCreateSheet = true }
                    )
                    .padding()
                }
            }
            .padding(.vertical)
        }
        .warmCanvas()
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
            await viewModel.loadCollections()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecipeDeleted"))) { _ in
            Task {
                await viewModel.loadCollections()
            }
        }
    }

    private var gridColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            return [GridItem(.adaptive(minimum: 190, maximum: 240), spacing: Theme.Spacing.sm)]
        }
        return [
            GridItem(.flexible(minimum: 150), spacing: Theme.Spacing.sm),
            GridItem(.flexible(minimum: 150), spacing: Theme.Spacing.sm)
        ]
    }

    @ViewBuilder
    private func collectionSection(
        title: String,
        collections: [Collection],
        isSavedSection: Bool
    ) -> some View {
        if !collections.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)

                    Spacer()

                    Text("\(collections.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.appSurface, in: Capsule())
                }
                .padding(.horizontal)

                LazyVGrid(columns: gridColumns, spacing: Theme.Spacing.sm) {
                    ForEach(collections) { collection in
                        NavigationLink(destination: CollectionDetailView(collection: collection, dependencies: dependencies)) {
                            CollectionCardView(
                                collection: collection,
                                recipeImages: viewModel.recipeImages(for: collection),
                                recipeImageSources: viewModel.recipeImageSources(for: collection),
                                preferredWidth: nil,
                                dependencies: dependencies
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .contextMenu {
                            Button(role: .destructive) {
                                Task {
                                    await viewModel.deleteCollection(collection)
                                }
                            } label: {
                                Label(
                                    isSavedSection ? "Remove Saved Collection" : "Delete",
                                    systemImage: isSavedSection ? "bookmark.slash" : "trash"
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

#Preview {
    CollectionsListView(dependencies: DependencyContainer.preview())
}
