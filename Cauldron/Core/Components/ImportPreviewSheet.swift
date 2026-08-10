//
//  ImportPreviewSheet.swift
//  Cauldron
//
//  Preview sheet for importing shared recipes, profiles, and collections
//

import SwiftUI

/// View model for import preview sheet
@MainActor
@Observable
final class ImportPreviewViewModel {
    var state: LoadingState = .loading
    var content: ImportedContent?

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

    // Required to prevent crashes in XCTest due to Swift bug #85221
    nonisolated deinit {}

    func loadContent() async {
        state = .loading

        do {
            let importedContent = try await dependencies.externalShareService.importFromShareURL(url)
            self.content = importedContent
            self.state = .loaded
        } catch {
            self.state = .error(error.localizedDescription)
        }
    }

    func importRecipe(_ recipe: Recipe, originalCreator: User?) async throws {
        guard CurrentUserSession.shared.userId != nil else {
            throw NSError(
                domain: "ImportPreview", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "User not logged in"])
        }

        _ = try await dependencies.recipeSaveService.saveRecipeToLibrary(
            recipe,
            originalCreatorId: originalCreator?.id,
            originalCreatorName: originalCreator?.displayName
        )
    }
}

/// Sheet view for previewing and importing shared content
struct ImportPreviewSheet: View {
    @State private var viewModel: ImportPreviewViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isImporting = false
    @State private var showSuccess = false
    @State private var importErrorMessage: String?

    init(url: URL, dependencies: DependencyContainer) {
        _viewModel = State(initialValue: ImportPreviewViewModel(url: url, dependencies: dependencies))
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
        AppStateView(kind: .loading, message: "Loading shared content…")
            .warmCanvas()
    }

    private func errorView(_ message: String) -> some View {
        AppStateView(
            kind: .error(),
            titleText: .localized("Unable to Load"),
            messageText: .verbatim(message),
            actionText: .localized("Try Again")
        ) {
            Task { await viewModel.loadContent() }
        }
        .warmCanvas()
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
            VStack(spacing: Theme.Spacing.lg) {
                RecipeReviewPresentation(
                    recipe: recipe,
                    dependencies: viewModel.dependencies,
                    sourceDescription: "Shared recipe",
                    attributionName: originalCreator?.displayName
                )

                if let importErrorMessage {
                    AppCard {
                        Label(importErrorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .stroke(Color.red.opacity(0.35), lineWidth: 1)
                    }
                    .frame(maxWidth: 520)
                    .padding(.horizontal, Theme.Spacing.md)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Import failed")
                    .accessibilityValue(importErrorMessage)
                }

                PrimaryActionButton(
                    "Add to My Recipes",
                    systemImage: "plus.circle.fill",
                    isBusy: isImporting
                ) {
                    guard !isImporting else { return }
                    Task {
                        isImporting = true
                        importErrorMessage = nil
                        do {
                            try await viewModel.importRecipe(recipe, originalCreator: originalCreator)
                            showSuccess = true
                        } catch {
                            AppLogger.general.error("Import error: \(error.localizedDescription)")
                            importErrorMessage = error.localizedDescription
                        }
                        isImporting = false
                    }
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xxl)
            }
        }
        .warmCanvas()
    }

    // MARK: - Profile Preview

    private func profilePreview(_ user: User) -> some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            AppCard(style: .elevated, alignment: .center) {
                VStack(spacing: Theme.Spacing.md) {
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

                    VStack(spacing: Theme.Spacing.xs) {
                        Text(user.displayName)
                            .font(Theme.Typography.screenTitle)

                        Text("@\(user.username)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: 520)

            PrimaryActionButton("Close", systemImage: "xmark", tint: .secondary) {
                dismiss()
            }
            .frame(maxWidth: 520)

            Spacer()
        }
        .padding(Theme.Spacing.md)
        .warmCanvas()
    }

    // MARK: - Collection Preview

    private func collectionPreview(_ collection: Collection, owner: User?) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
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
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
                }

                AppCard(style: .glass, alignment: .center) {
                    VStack(spacing: Theme.Spacing.sm) {
                        Text(collection.name)
                            .font(Theme.Typography.screenTitle)
                            .multilineTextAlignment(.center)

                        if let owner {
                            Label("By \(owner.displayName)", systemImage: "person.circle.fill")
                                .font(Theme.Typography.metadata)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                PrimaryActionButton("Close", systemImage: "xmark") {
                    dismiss()
                }
                .frame(maxWidth: 520)
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.lg)
        }
        .warmCanvas()
    }

    // MARK: - Helper Views

    private var placeholderImage: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
            .fill(Color.appSurfaceElevated)
            .frame(height: 250)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: Theme.IconSize.large))
                    .foregroundStyle(.secondary)
            )
    }

    private var profilePlaceholder: some View {
        Circle()
            .fill(Color.appSurfaceElevated)
            .frame(width: 120, height: 120)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: Theme.IconSize.large))
                    .foregroundStyle(.secondary)
            )
    }
}

#Preview {
    let dependencies = DependencyContainer.preview()
    let url = URL(string: "https://cauldron.web.app/recipe/abc123")!

    return ImportPreviewSheet(url: url, dependencies: dependencies)
}
