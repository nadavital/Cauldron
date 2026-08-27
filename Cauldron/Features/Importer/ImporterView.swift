//
//  ImporterView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import SwiftUI
import UIKit

/// View for importing recipes
struct ImporterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ImporterViewModel
    @State private var previewContext: PreviewContext?
    @State private var hasTriggeredAutoImport = false
    @State private var hasPresentedPreparedPreview = false
    @State private var showingOCRPicker = false
    @State private var showingOCRSourceDialog = false
    @State private var ocrSourceType: UIImagePickerController.SourceType = .photoLibrary
    private let autoImportFromInitialURL: Bool
    private let autoImportFromInitialText: Bool
    private let hasPreparedRecipe: Bool
    private let destinationRecipeID: UUID?
    private let onSuccessfulSave: () async -> Bool

    private struct PreviewContext: Identifiable {
        let id = UUID()
        let recipe: Recipe
        let sourceInfo: String
    }

    init(
        dependencies: DependencyContainer,
        initialURL: URL? = nil,
        initialText: String? = nil,
        preparedRecipe: Recipe? = nil,
        preparedSourceInfo: String? = nil,
        destinationRecipeID: UUID? = nil,
        onSuccessfulSave: @escaping () async -> Bool = { true }
    ) {
        let viewModel = ImporterViewModel(dependencies: dependencies)
        if let initialURL {
            viewModel.preloadURL(initialURL)
        }
        if let initialText {
            viewModel.preloadText(initialText)
        }
        if let preparedRecipe, let preparedSourceInfo {
            viewModel.preloadImportedRecipe(preparedRecipe, sourceInfo: preparedSourceInfo)
        }
        self.autoImportFromInitialURL = initialURL != nil
        self.autoImportFromInitialText =
            initialText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        self.hasPreparedRecipe = preparedRecipe != nil
        self.destinationRecipeID = destinationRecipeID
        self.onSuccessfulSave = onSuccessfulSave
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    GlassEffectContainer(spacing: 2) {
                        VStack(spacing: Theme.Spacing.lg) {
                            importTypePicker

                            switch viewModel.importType {
                            case .url:
                                urlSection
                            case .text:
                                textSection
                            case .image:
                                imageSection
                            }

                            if let ocrError = viewModel.ocrErrorMessage {
                                errorSection(ocrError)
                            }

                            if let error = viewModel.errorMessage {
                                errorSection(error)
                            }
                        }
                    }
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.xxl)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, 110)
                }
                .appPageChrome()

                if viewModel.canImport || viewModel.isLoading {
                    generateActionButton
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Theme.Animation.spring, value: viewModel.canImport)
            .animation(Theme.Animation.spring, value: viewModel.isLoading)
            .navigationTitle("Import Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }
            .task {
                await autoImportIfNeeded()
            }
            .onChange(of: viewModel.importType) { _, _ in
                viewModel.clearSourceErrors()
            }
            .onChange(of: viewModel.urlString) { _, _ in
                viewModel.clearSourceErrors()
            }
            .onChange(of: viewModel.textInput) { _, _ in
                viewModel.clearSourceErrors()
            }
            .fullScreenCover(item: $previewContext) { context in
                RecipeImportPreviewView(
                    importedRecipe: context.recipe,
                    dependencies: viewModel.dependencies,
                    sourceInfo: context.sourceInfo,
                    destinationRecipeID: destinationRecipeID,
                    onSave: onSuccessfulSave
                )
            }
            .fullScreenCover(isPresented: $showingOCRPicker) {
                ImagePicker(
                    image: ocrImageBinding, sourceType: ocrSourceType, allowsEditing: false
                )
                .ignoresSafeArea()
            }
            .confirmationDialog(
                "Import from Image", isPresented: $showingOCRSourceDialog, titleVisibility: .visible
            ) {
                Button("Photo Library") {
                    ocrSourceType = .photoLibrary
                    showingOCRPicker = true
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Camera") {
                        ocrSourceType = .camera
                        showingOCRPicker = true
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose a photo source for recipe image import.")
            }
        }
        .frame(minWidth: catalystMinimumWidth, minHeight: catalystMinimumHeight)
    }

    private var catalystMinimumWidth: CGFloat? {
        #if targetEnvironment(macCatalyst)
        720
        #else
        nil
        #endif
    }

    private var catalystMinimumHeight: CGFloat? {
        #if targetEnvironment(macCatalyst)
        620
        #else
        nil
        #endif
    }

    private var generateActionButton: some View {
        PrimaryActionButton(
            verbatimTitle: viewModel.isLoading ? generateLoadingTitle : generateActionTitle,
            systemImage: generateActionIcon,
            isBusy: viewModel.isLoading,
            isDisabled: !viewModel.canImport
        ) {
            Task { await performImport() }
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.xxl)
    }

    private var generateActionTitle: String {
        "Import Recipe"
    }

    private var generateActionIcon: String {
        "arrow.down.doc"
    }

    private var generateLoadingTitle: String {
        if hasPreparedRecipe {
            return "Preparing shared recipe..."
        }
        if autoImportFromInitialURL && viewModel.importType == .url {
            return "Importing shared link..."
        }
        if autoImportFromInitialText && viewModel.importType == .text {
            return "Importing shared text..."
        }
        return "Importing..."
    }

    private var importTypePicker: some View {
        AppCard(style: .glass) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label("Import Method", systemImage: "arrow.triangle.branch")
                    .font(.headline)

                Picker("Import Type", selection: $viewModel.importType) {
                    Label("URL", systemImage: "link").tag(ImportType.url)
                    Label("Text", systemImage: "text.justifyleft").tag(ImportType.text)
                    Label("Image", systemImage: "photo.on.rectangle").tag(ImportType.image)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var urlSection: some View {
        AppCard(style: .glass) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Label("Recipe Link", systemImage: "link")
                    .font(Theme.Typography.cardTitle)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.sm) {
                        TextField("https://example.com/recipe", text: $viewModel.urlString)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .padding(Theme.Spacing.sm)
                            .background(Color.appSurfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                                    .stroke(
                                        isValidURL ? Color.green.opacity(0.4) : Color.secondary.opacity(0.15),
                                        lineWidth: 1.5)
                            )

                        if isValidURL {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title3)
                        }
                    }

                    Text("Paste a link to the recipe and we'll import the details.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button {
                        pasteURLFromClipboard()
                    } label: {
                        Label("Paste URL from Clipboard", systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.cauldronOrange)
                    .controlSize(.large)
                    .frame(minHeight: Theme.HitTarget.minimum)
                }
            }
        }
    }

    private var isValidURL: Bool {
        viewModel.normalizedURLInput() != nil
    }

    private var textSection: some View {
        AppCard(style: .glass) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    Label("Recipe Text", systemImage: "text.justifyleft")
                        .font(Theme.Typography.cardTitle)

                    Spacer()

                    if !viewModel.textInput.isEmpty {
                        Text("\(viewModel.textInput.count) characters")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $viewModel.textInput)
                        .frame(minHeight: 220)
                        .padding(Theme.Spacing.sm)
                        .background(Color.appSurfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1.5)
                        )

                    if viewModel.textInput.isEmpty {
                        Text(
                            "Paste your recipe here...\n\nExample:\n\nChocolate Chip Cookies\n\nIngredients:\n- 2 cups flour\n- 1 cup sugar\n...\n\nSteps:\n1. Mix dry ingredients\n2. Add wet ingredients\n..."
                        )
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.lg)
                        .allowsHitTesting(false)
                    }
                }

                Text("Include the title, ingredients, and steps for the most accurate import.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    pasteTextFromClipboard()
                } label: {
                    Label("Paste Text from Clipboard", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.cauldronOrange)
                .controlSize(.large)
                .frame(minHeight: Theme.HitTarget.minimum)
            }
        }
    }

    private var imageSection: some View {
        AppCard(style: .glass) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label("Recipe Image", systemImage: "photo.on.rectangle")
                    .font(Theme.Typography.cardTitle)

                if let selectedImage = viewModel.selectedOCRImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }

                Button {
                    showingOCRSourceDialog = true
                } label: {
                    Label(imageSourceButtonTitle, systemImage: "photo.badge.plus")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Color.cauldronOrange.opacity(0.12))
                        .foregroundColor(.cauldronOrange)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        .frame(minHeight: Theme.HitTarget.minimum)
                }

                Text(
                    "When you tap Import Recipe, Cauldron reads the image and tries to build a complete recipe."
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }

    private var imageSourceButtonTitle: String {
        viewModel.selectedOCRImage == nil ? "Choose Recipe Image" : "Replace Image"
    }

    private var ocrImageBinding: Binding<UIImage?> {
        Binding(
            get: { viewModel.selectedOCRImage },
            set: { image in
                viewModel.selectedOCRImage = image
                viewModel.clearSourceErrors()
            }
        )
    }

    private func errorSection(_ message: String) -> some View {
        AppCard(style: .glass) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.red)

                Spacer(minLength: 0)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Color.red.opacity(0.35), lineWidth: 1)
        }
    }

    private func pasteURLFromClipboard() {
        guard let clipboardString = UIPasteboard.general.string else { return }
        viewModel.urlString = clipboardString
    }

    private func pasteTextFromClipboard() {
        guard let clipboardString = UIPasteboard.general.string else { return }
        viewModel.textInput = clipboardString
    }

    private func performImport() async {
        await viewModel.importRecipe()
        if let recipe = viewModel.importedRecipe,
            let source = viewModel.sourceInfo
        {
            previewContext = PreviewContext(recipe: recipe, sourceInfo: source)
        }
    }

    private func autoImportIfNeeded() async {
        if hasPreparedRecipe,
            !hasPresentedPreparedPreview,
            let recipe = viewModel.importedRecipe,
            let source = viewModel.sourceInfo
        {
            hasPresentedPreparedPreview = true
            previewContext = PreviewContext(recipe: recipe, sourceInfo: source)
            return
        }

        guard autoImportFromInitialURL || autoImportFromInitialText,
            !hasTriggeredAutoImport,
            viewModel.canImport
        else {
            return
        }

        hasTriggeredAutoImport = true
        await performImport()
    }
}

enum ImportType {
    case url
    case text
    case image
}

#Preview {
    ImporterView(dependencies: .preview())
}
