//
//  ImporterView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import SwiftUI

/// View for importing recipes
struct ImporterView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ImporterViewModel
    @State private var showingPreview = false
    
    init(dependencies: DependencyContainer) {
        _viewModel = StateObject(wrappedValue: ImporterViewModel(dependencies: dependencies))
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
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 38))
                .foregroundColor(.cauldronOrange)

            VStack(alignment: .leading, spacing: 6) {
                Text("Import a Recipe")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Bring recipes into Cauldron by pasting a link or dropping in the full text. We'll take care of the rest.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var importTypePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Method")
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            Picker("Import Type", selection: $viewModel.importType) {
                Text("URL").tag(ImportType.url)
                Text("Text").tag(ImportType.text)
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
                TextField("https://example.com/recipe", text: $viewModel.urlString)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .padding(12)
                    .background(Color.cauldronBackground)
                    .cornerRadius(10)

                Text("Paste a link to the recipe and we'll import the details.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .cardStyle()
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Recipe Text", systemImage: "text.justifyleft")
                .font(.headline)

            TextEditor(text: $viewModel.textInput)
                .frame(minHeight: 220)
                .padding(12)
                .background(Color.cauldronBackground)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )

            Text("Include the title, ingredients, and steps for the most accurate import.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .cardStyle()
    }

    private var quickImportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Actions")
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            Button {
                pasteFromClipboard()
            } label: {
                Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.cauldronOrange.opacity(0.12))
                    .foregroundColor(.cauldronOrange)
                    .cornerRadius(12)
            }

            Text("We'll detect whether it's a link or recipe text automatically.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .cardStyle()
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
