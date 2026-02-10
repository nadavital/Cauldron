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
    @State private var showingPreview = false
    @State private var hasTriggeredAutoImport = false
    @State private var showingOCRPicker = false
    @State private var showingOCRSourceDialog = false
    @State private var ocrSourceType: UIImagePickerController.SourceType = .photoLibrary
    private let autoImportFromInitialURL: Bool

    init(dependencies: DependencyContainer, initialURL: URL? = nil) {
        let viewModel = ImporterViewModel(dependencies: dependencies)
        if let initialURL {
            viewModel.preloadURL(initialURL)
        }
        self.autoImportFromInitialURL = initialURL != nil
        _viewModel = State(initialValue: viewModel)
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 24) {
                        headerSection

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
                    .padding(.vertical, 32)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 110)
                }
                .background(Color.cauldronBackground.ignoresSafeArea())

                if viewModel.canImport || viewModel.isLoading {
                    generateActionButton
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(), value: viewModel.canImport)
            .animation(.spring(), value: viewModel.isLoading)
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
            .fullScreenCover(isPresented: $showingPreview) {
                if let recipe = viewModel.importedRecipe, let source = viewModel.sourceInfo {
                    RecipeImportPreviewView(
                        importedRecipe: recipe,
                        dependencies: viewModel.dependencies,
                        sourceInfo: source,
                        onSave: {
                            // Dismiss the importer sheet when recipe is saved
                            dismiss()
                        }
                    )
                }
            }
            .fullScreenCover(isPresented: $showingOCRPicker) {
                ImagePicker(image: $viewModel.selectedOCRImage, sourceType: ocrSourceType, allowsEditing: false)
                    .ignoresSafeArea()
            }
            .confirmationDialog("Import from Image", isPresented: $showingOCRSourceDialog, titleVisibility: .visible) {
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
    }

    private var generateActionButton: some View {
        Button {
            Task { await performImport() }
        } label: {
            HStack(spacing: 12) {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                    Text(generateLoadingTitle)
                        .font(.headline)
                } else {
                    Image(systemName: generateActionIcon)
                        .font(.headline)
                    Text(generateActionTitle)
                        .font(.headline)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color.cauldronOrange, in: Capsule())
        }
        .disabled(viewModel.isLoading || !viewModel.canImport)
        .padding(.bottom, 32)
    }

    private var generateActionTitle: String {
        "Import Recipe"
    }

    private var generateActionIcon: String {
        "arrow.down.doc"
    }

    private var generateLoadingTitle: String {
        autoImportFromInitialURL && viewModel.importType == .url ? "Importing shared link..." : "Importing..."
    }
    
    private var headerSection: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.cauldronOrange.opacity(0.8),
                                Color.cauldronOrange
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)

                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Import a Recipe")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(headerDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardStyle()
    }

    private var importTypePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Method")
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            Picker("Import Type", selection: $viewModel.importType) {
                Label("URL", systemImage: "link").tag(ImportType.url)
                Label("Text", systemImage: "text.justifyleft").tag(ImportType.text)
                Label("Image", systemImage: "photo.on.rectangle").tag(ImportType.image)
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .cardStyle()
    }

    private var urlSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Recipe Link", systemImage: "link")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    TextField("https://example.com/recipe", text: $viewModel.urlString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .padding(12)
                        .background(Color.cauldronBackground)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isValidURL ? Color.green.opacity(0.4) : Color.secondary.opacity(0.15), lineWidth: 1.5)
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
            }
        }
        .padding(16)
        .cardStyle()
    }

    private var isValidURL: Bool {
        guard !viewModel.urlString.isEmpty else { return false }
        if let url = URL(string: viewModel.urlString),
           (url.scheme == "http" || url.scheme == "https") {
            return true
        }
        return false
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Recipe Text", systemImage: "text.justifyleft")
                    .font(.headline)

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
                    .padding(12)
                    .background(Color.cauldronBackground)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1.5)
                    )

                if viewModel.textInput.isEmpty {
                    Text("Paste your recipe here...\n\nExample:\n\nChocolate Chip Cookies\n\nIngredients:\n- 2 cups flour\n- 1 cup sugar\n...\n\nSteps:\n1. Mix dry ingredients\n2. Add wet ingredients\n...")
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
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
        }
        .padding(16)
        .cardStyle()
    }

    private var imageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recipe Image", systemImage: "photo.on.rectangle")
                .font(.headline)

            if let selectedImage = viewModel.selectedOCRImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Button {
                showingOCRSourceDialog = true
            } label: {
                Label(imageSourceButtonTitle, systemImage: "photo.badge.plus")
                    .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.cauldronOrange.opacity(0.12))
                .foregroundColor(.cauldronOrange)
                .cornerRadius(12)
            }

            Text("When you tap Import Recipe, Cauldron reads the image and tries to build a complete recipe.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .cardStyle()
    }

    private var imageSourceButtonTitle: String {
        viewModel.selectedOCRImage == nil ? "Choose Recipe Image" : "Replace Image"
    }

    private var headerDescription: String {
        if autoImportFromInitialURL {
            return "Link received from Share Sheet. We'll import it now, then you can review and save."
        }
        return "Bring recipes into Cauldron from a URL, raw text, or a recipe image."
    }

    private func errorSection(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.red)

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
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
        if viewModel.isSuccess {
            showingPreview = true
        }
    }

    private func autoImportIfNeeded() async {
        guard autoImportFromInitialURL,
              !hasTriggeredAutoImport,
              viewModel.importType == .url,
              viewModel.canImport else {
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
