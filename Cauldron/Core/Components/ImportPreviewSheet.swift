//
//  ImportPreviewSheet.swift
//  Cauldron
//
//  Preview sheet for importing shared recipes, profiles, and collections
//

import SwiftUI
import Combine

/// View model for import preview sheet
@MainActor
class ImportPreviewViewModel: ObservableObject {
    @Published var state: LoadingState = .loading
    @Published var content: ImportedContent?

    enum LoadingState {
        case loading
        case loaded
        case error(String)
    }

    let dependencies: DependencyContainer
    let url: URL

    init(url: URL, dependencies: DependencyContainer) {
        self.url = url
        self.dependencies = dependencies
    }

    func loadContent() async {
        state = .loading

        do {
            let importedContent = try await dependencies.externalShareService.importFromShareURL(url)
            await MainActor.run {
                self.content = importedContent
                self.state = .loaded
            }
        } catch {
            await MainActor.run {
                self.state = .error(error.localizedDescription)
            }
        }
    }

    func importRecipe(_ recipe: Recipe, originalCreator: User?) async throws {
        // Add recipe to user's library
        guard let userId = CurrentUserSession.shared.userId else {
            throw NSError(domain: "ImportPreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])
        }

        // Create a copy of the recipe with attribution using the helper method
        let importedRecipe = recipe.withOwner(
            userId,
            originalCreatorId: originalCreator?.id,
            originalCreatorName: originalCreator?.displayName
        )

        try await dependencies.recipeRepository.create(importedRecipe)
    }
}

/// Sheet view for previewing and importing shared content
struct ImportPreviewSheet: View {
    @StateObject private var viewModel: ImportPreviewViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isImporting = false
    @State private var showSuccess = false

    init(url: URL, dependencies: DependencyContainer) {
        _viewModel = StateObject(wrappedValue: ImportPreviewViewModel(url: url, dependencies: dependencies))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .loading:
                    loadingView
                case .loaded:
                    if let content = viewModel.content {
                        contentView(content)
                    } else {
                        errorView("No content loaded")
                    }
                case .error(let message):
                    errorView(message)
                }
            }
            .navigationTitle("Shared Content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await viewModel.loadContent()
        }
        .alert("Recipe Added!", isPresented: $showSuccess) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("The recipe has been added to your library")
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading shared content...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Unable to Load")
                .font(.title2)
                .fontWeight(.semibold)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func contentView(_ content: ImportedContent) -> some View {
        switch content {
        case .recipe(let recipe, let originalCreator):
            recipePreview(recipe, originalCreator: originalCreator)
        case .profile(let user):
            profilePreview(user)
        case .collection(let collection, let owner):
            collectionPreview(collection, owner: owner)
        }
    }

    // MARK: - Recipe Preview

    private func recipePreview(_ recipe: Recipe, originalCreator: User?) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Recipe Image - Using RecipeImageView with CloudKit fallback
                RecipeImageView(
                    imageURL: recipe.imageURL,
                    size: .preview,
                    showPlaceholderText: false,
                    recipeImageService: viewModel.dependencies.recipeImageService,
                    recipeId: recipe.id,
                    ownerId: recipe.ownerId
                )
                .frame(height: 250)
                .cornerRadius(12)
                .padding(.horizontal)
                .task(id: recipe.id) {
                    // Task will automatically cancel when recipe.id changes
                }

                VStack(spacing: 12) {
                    Text(recipe.title)
                        .font(.title)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    // Recipe metadata
                    HStack(spacing: 20) {
                        Label("\(recipe.ingredients.count) ingredients", systemImage: "list.bullet")
                        if let minutes = recipe.totalMinutes {
                            Label("\(minutes) min", systemImage: "clock")
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                    // Tags
                    if !recipe.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(recipe.tags, id: \.self) { tag in
                                    Text(tag.name)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.orange.opacity(0.2))
                                        .foregroundColor(.orange)
                                        .cornerRadius(12)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Attribution
                    if let creator = originalCreator {
                        HStack {
                            Image(systemName: "person.circle.fill")
                            Text("Shared by \(creator.displayName)")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal)

                // Import button
                Button(action: {
                    Task {
                        isImporting = true
                        do {
                            try await viewModel.importRecipe(recipe, originalCreator: originalCreator)
                            showSuccess = true
                        } catch {
                            AppLogger.general.error("Import error: \(error.localizedDescription)")
                        }
                        isImporting = false
                    }
                }) {
                    HStack {
                        if isImporting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "plus.circle.fill")
                            Text("Add to My Recipes")
                        }
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(12)
                }
                .disabled(isImporting)
                .padding(.horizontal)
                .padding(.top, 20)
            }
            .padding(.vertical)
        }
    }

    // MARK: - Profile Preview

    private func profilePreview(_ user: User) -> some View {
        VStack(spacing: 24) {
            Spacer()

            // Profile Image
            if let imageURL = user.profileImageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                    case .failure, .empty:
                        profilePlaceholder
                    @unknown default:
                        profilePlaceholder
                    }
                }
            } else {
                profilePlaceholder
            }

            VStack(spacing: 8) {
                Text(user.displayName)
                    .font(.title)
                    .fontWeight(.bold)

                Text("@\(user.username)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Close button
            Button(action: {
                dismiss()
            }) {
                HStack {
                    Image(systemName: "xmark")
                    Text("Close")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.secondary)
                .cornerRadius(12)
            }
            .padding(.horizontal)

            Spacer()
        }
    }

    // MARK: - Collection Preview

    private func collectionPreview(_ collection: Collection, owner: User?) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Collection Cover Image
                if let imageURL = collection.coverImageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 250)
                                .clipped()
                        case .failure:
                            placeholderImage
                        case .empty:
                            ProgressView()
                                .frame(height: 250)
                        @unknown default:
                            placeholderImage
                        }
                    }
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                VStack(spacing: 12) {
                    Text(collection.name)
                        .font(.title)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    // Attribution
                    if let owner = owner {
                        HStack {
                            Image(systemName: "person.circle.fill")
                            Text("By \(owner.displayName)")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                // Close button (collection import not supported)
                Button(action: {
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "xmark")
                        Text("Close")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(12)
                }
                .disabled(isImporting)
                .padding(.horizontal)
                .padding(.top, 20)
            }
            .padding(.vertical)
        }
    }

    // MARK: - Helper Views

    private var placeholderImage: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(height: 250)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 48))
                    .foregroundColor(.gray)
            )
    }

    private var profilePlaceholder: some View {
        Circle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 120, height: 120)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.gray)
            )
    }
}

#Preview {
    let dependencies = DependencyContainer.preview()
    let url = URL(string: "https://cauldron.web.app/recipe/abc123")!

    return ImportPreviewSheet(url: url, dependencies: dependencies)
}
