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
            Form {
                Section {
                    Picker("Import Type", selection: $viewModel.importType) {
                        Text("URL").tag(ImportType.url)
                        Text("Text").tag(ImportType.text)
                    }
                    .pickerStyle(.segmented)
                }
                
                Section {
                    switch viewModel.importType {
                    case .url:
                        urlSection
                    case .text:
                        textSection
                    }
                }
                
                // Paste from Clipboard Section
                Section {
                    Button {
                        pasteFromClipboard()
                    } label: {
                        HStack {
                            Image(systemName: "doc.on.clipboard")
                                .foregroundColor(.cauldronOrange)
                            Text("Paste from Clipboard")
                            Spacer()
                        }
                    }
                } header: {
                    Text("Quick Import")
                } footer: {
                    Text("Paste a URL or recipe text you've already copied")
                }
                
                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
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
    
    private var urlSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Recipe URL", text: $viewModel.urlString)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .autocapitalization(.none)
            
            Text("Paste a link to a recipe website")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var textSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $viewModel.textInput)
                .frame(minHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            
            Text("Paste or type your recipe. Include title, ingredients, and steps.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
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
