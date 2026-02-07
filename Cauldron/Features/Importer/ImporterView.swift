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
    @State private var showingOCRPicker = false
    @State private var showingOCRSourceDialog = false
    @State private var ocrSourceType: UIImagePickerController.SourceType = .photoLibrary

    init(dependencies: DependencyContainer, initialURL: URL? = nil) {
        let viewModel = ImporterViewModel(dependencies: dependencies)
        if let initialURL {
            viewModel.preloadURL(initialURL)
        }
        _viewModel = State(initialValue: viewModel)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection

                    importTypePicker

                    switch viewModel.importType {
                    case .url:
                        urlSection
                    case .text:
                        textSection
                    }

                    quickImportSection

                    if viewModel.isProcessingOCR {
                        ocrProcessingSection
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
            }
            .background(Color.cauldronBackground.ignoresSafeArea())
            .navigationTitle("Import Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", systemImage: "checkmark") {
                        Task {
                            await viewModel.importRecipe()
                            if viewModel.isSuccess {
                                showingPreview = true
                            }
                        }
                    }
                    .disabled(viewModel.isLoading || !viewModel.canImport)
                }
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
            .fullScreenCover(isPresented: $showingOCRPicker, onDismiss: {
                Task {
                    await viewModel.extractTextFromSelectedImage()
                }
            }) {
                ImagePicker(image: $viewModel.selectedOCRImage, sourceType: ocrSourceType)
                    .ignoresSafeArea()
            }
            .confirmationDialog("Scan Recipe Text", isPresented: $showingOCRSourceDialog, titleVisibility: .visible) {
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
                Text("Choose a photo source for OCR text extraction.")
            }
        }
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

                Text("Bring recipes into Cauldron by pasting a link or the full recipe text.")
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
        }
        .padding(16)
        .cardStyle()
    }

    private var quickImportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            Button {
                pasteFromClipboard()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard.fill")
                    Text("Paste from Clipboard")
                        .fontWeight(.semibold)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.cauldronOrange.opacity(0.12))
                .foregroundColor(.cauldronOrange)
                .cornerRadius(12)
            }

            Button {
                showingOCRSourceDialog = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.viewfinder")
                    Text("Scan from Photo (OCR)")
                        .fontWeight(.semibold)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.cauldronSecondaryBackground)
                .foregroundColor(.primary)
                .cornerRadius(12)
            }

            Text("We'll detect whether it's a link or recipe text automatically.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .cardStyle()
    }

    private var ocrProcessingSection: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.cauldronOrange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Extracting text from image...")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("This usually takes a few seconds.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.cauldronSecondaryBackground)
        .cornerRadius(12)
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
    
    private func pasteFromClipboard() {
        if let clipboardString = UIPasteboard.general.string {
            // Try to detect if it's a URL
            if let url = URL(string: clipboardString),
               (url.scheme == "http" || url.scheme == "https") {
                viewModel.importType = .url
                viewModel.urlString = clipboardString
            } else {
                // Otherwise treat as text
                viewModel.importType = .text
                viewModel.textInput = clipboardString
            }
        }
    }
}

enum ImportType {
    case url
    case text
}

#Preview {
    ImporterView(dependencies: .preview())
}
