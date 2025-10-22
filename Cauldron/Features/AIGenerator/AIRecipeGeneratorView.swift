//
//  AIRecipeGeneratorView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/14/25.
//

import SwiftUI
import FoundationModels

/// View for generating recipes using Apple Intelligence
struct AIRecipeGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AIRecipeGeneratorViewModel
    @FocusState private var isPromptFocused: Bool
    @State private var isAvailable: Bool = false

    init(dependencies: DependencyContainer) {
        _viewModel = StateObject(wrappedValue: AIRecipeGeneratorViewModel(dependencies: dependencies))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with Apple Intelligence branding
                    headerSection

                    if !isAvailable {
                        unavailableSection
                    } else {
                        // Prompt input section
                        promptSection

                        // Generation progress
                        if viewModel.isGenerating || viewModel.generatedRecipe != nil {
                            progressSection
                        }

                        // Preview of generated recipe
                        if let partial = viewModel.partialRecipe {
                            recipePreviewSection(partial: partial)
                        }

                        // Error display
                        if let error = viewModel.errorMessage {
                            errorSection(error: error)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Generate Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        viewModel.cancelGeneration()
                        dismiss()
                    }
                }

                if viewModel.generatedRecipe != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", systemImage: "checkmark") {
                            // Prevent race condition by setting isSaving immediately
                            guard !viewModel.isSaving else { return }
                            viewModel.isSaving = true

                            Task {
                                if await viewModel.saveRecipe() {
                                    // Dismiss immediately - CloudKit sync happens in background
                                    dismiss()
                                } else {
                                    viewModel.isSaving = false
                                }
                            }
                        }
                        .disabled(viewModel.isSaving)
                    }
                }
            }
            .task {
                isAvailable = await viewModel.checkAvailability()
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 16) {
            // Apple Intelligence logo
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.0, green: 0.5, blue: 1.0),
                                Color(red: 0.5, green: 0.0, blue: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)

                Image(systemName: "apple.intelligence")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 8) {
                Text("AI Recipe Generator")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Describe a recipe and Apple Intelligence will create it for you")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(.top)
    }

    private var unavailableSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)

            Text("Apple Intelligence Not Available")
                .font(.headline)

            Text("This device doesn't support Apple Intelligence, or it may be disabled in Settings.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical, 40)
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What would you like to cook?")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $viewModel.prompt)
                    .frame(minHeight: 120)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isPromptFocused ? Color.blue : Color.clear, lineWidth: 2)
                    )
                    .focused($isPromptFocused)

                Text("Examples: \"Healthy chicken pasta\", \"Quick vegetarian dinner\", \"Chocolate dessert for 8 people\"")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button {
                viewModel.generateRecipe()
                isPromptFocused = false
            } label: {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text("Generate Recipe")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.canGenerate ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!viewModel.canGenerate)
        }
        .padding(.top)
    }

    private var progressSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                if viewModel.isGenerating {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: viewModel.generationProgress.systemImage)
                        .foregroundColor(viewModel.generationProgress == .complete ? .green : .blue)
                }

                Text(viewModel.generationProgress.description)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if viewModel.generatedRecipe != nil {
                    Button {
                        viewModel.regenerate()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Regenerate")
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    private func recipePreviewSection(partial: GeneratedRecipe.PartiallyGenerated) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Recipe Preview")
                .font(.headline)

            // Title with animated typing effect
            if let title = partial.title {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Title")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            }

            // Yields and time
            if let yields = partial.yields ?? partial.totalMinutes.map({ _ in "" }) {
                HStack {
                    if let y = partial.yields {
                        Label(y, systemImage: "person.2")
                            .font(.subheadline)
                    }

                    if let minutes = partial.totalMinutes {
                        Label("\(minutes) min", systemImage: "clock")
                            .font(.subheadline)
                    }
                }
                .foregroundColor(.secondary)
                .transition(.opacity)
            }

            // Ingredients
            if let ingredients = partial.ingredients, !ingredients.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ingredients")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    ForEach(ingredients.indices, id: \.self) { index in
                        let ingredient = ingredients[index]
                        HStack {
                            Circle()
                                .fill(Color.cauldronOrange.opacity(0.3))
                                .frame(width: 6, height: 6)

                            if let value = ingredient.quantityValue,
                               let unitStr = ingredient.quantityUnit {
                                Text("\(value, specifier: "%.1f") \(unitStr)")
                                    .fontWeight(.medium)
                            }

                            Text(ingredient.name ?? "")

                            if let note = ingredient.note {
                                Text("(\(note))")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .font(.body)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            }

            // Steps
            if let steps = partial.steps, !steps.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Instructions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    ForEach(steps.indices, id: \.self) { index in
                        let step = steps[index]
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.cauldronOrange))

                            Text(step.text ?? "")
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer()
                        }
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            }

            // Tags
            if let tags = partial.tags, !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.cauldronOrange.opacity(0.2))
                                .cornerRadius(8)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: partial.ingredients?.count)
        .animation(.easeInOut(duration: 0.3), value: partial.steps?.count)
    }

    private func errorSection(error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)

            Text(error)
                .font(.subheadline)
                .foregroundColor(.red)

            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    AIRecipeGeneratorView(dependencies: .preview())
}
