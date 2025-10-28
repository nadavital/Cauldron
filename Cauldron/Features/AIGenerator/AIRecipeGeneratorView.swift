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
                    headerSection

                    if !isAvailable {
                        unavailableSection
                    } else {
                        promptSection

                        if viewModel.isGenerating || viewModel.generatedRecipe != nil {
                            progressSection
                        }

                        if let partial = viewModel.partialRecipe {
                            recipePreviewSection(partial: partial)
                        }

                        if let error = viewModel.errorMessage {
                            errorSection(error: error)
                        }
                    }
                }
                .padding(.vertical, 28)
                .padding(.horizontal, 20)
            }
            .background(Color.cauldronBackground.ignoresSafeArea())
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
        VStack(spacing: 20) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.18, green: 0.28, blue: 0.99),
                                    Color(red: 0.57, green: 0.14, blue: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 70, height: 70)

                    Image(systemName: "apple.intelligence")
                        .font(.system(size: 34))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("AI Recipe Generator")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Describe what you crave and Cauldron will craft the recipe using Apple Intelligence.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            Text("Fine-tune the prompt with ingredients, dietary preferences, or timing to receive a recipe that's ready to cook.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(20)
        .cardStyle()
    }

    private var unavailableSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundColor(.orange)

            Text("Apple Intelligence Not Available")
                .font(.headline)

            Text("This device doesn't support Apple Intelligence, or it may be disabled in Settings.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .cardStyle()
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What would you like to cook?")
                .font(.headline)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.prompt)
                    .frame(minHeight: 160)
                    .padding(14)
                    .background(Color.cauldronBackground)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isPromptFocused ? Color.cauldronOrange : Color.secondary.opacity(0.15), lineWidth: 1.5)
                    )
                    .focused($isPromptFocused)

                // Placeholder text
                if viewModel.prompt.isEmpty {
                    Text("Describe your ideal dish...")
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 22)
                        .allowsHitTesting(false)
                }
            }

            // Category-based inspiration
            VStack(alignment: .leading, spacing: 16) {
                Text("Get inspired:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Cuisine
                RecipeTagSection(
                    title: "Cuisine",
                    icon: "map",
                    tags: ["Italian", "Mexican", "Asian", "Mediterranean", "French", "Indian"],
                    onTagTap: { tag in
                        appendToPrompt(tag)
                    }
                )

                // Dietary
                RecipeTagSection(
                    title: "Diet",
                    icon: "leaf",
                    tags: ["Vegetarian", "Vegan", "Gluten-free", "Low-carb", "Keto", "Paleo"],
                    onTagTap: { tag in
                        appendToPrompt(tag)
                    }
                )

                // Time
                RecipeTagSection(
                    title: "Time",
                    icon: "clock",
                    tags: ["Quick (< 30 min)", "Weeknight", "Weekend project"],
                    onTagTap: { tag in
                        appendToPrompt(tag)
                    }
                )

                // Type
                RecipeTagSection(
                    title: "Type",
                    icon: "fork.knife",
                    tags: ["Breakfast", "Lunch", "Dinner", "Dessert", "Snack", "Comfort food"],
                    onTagTap: { tag in
                        appendToPrompt(tag)
                    }
                )
            }

            Button {
                viewModel.generateRecipe()
                isPromptFocused = false
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                    Text("Generate Recipe")
                        .fontWeight(.semibold)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(viewModel.canGenerate ? Color.cauldronOrange : Color.gray.opacity(0.3))
                .foregroundColor(viewModel.canGenerate ? .white : .secondary)
                .cornerRadius(12)
            }
            .disabled(!viewModel.canGenerate)
        }
        .padding(20)
        .cardStyle()
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if viewModel.isGenerating {
                    ProgressView()
                        .tint(.cauldronOrange)
                } else {
                    Image(systemName: viewModel.generationProgress.systemImage)
                        .foregroundColor(viewModel.generationProgress == .complete ? .green : .cauldronOrange)
                }

                Text(viewModel.generationProgress.description)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if viewModel.generatedRecipe != nil {
                    Button {
                        viewModel.regenerate()
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        .cardStyle()
    }

    private func recipePreviewSection(partial: GeneratedRecipe.PartiallyGenerated) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Recipe Preview")
                .font(.headline)

            if let title = partial.title {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Title")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    Text(title)
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.cauldronSecondaryBackground)
                )
            }

            if partial.yields != nil || partial.totalMinutes != nil {
                HStack(spacing: 16) {
                    if let yields = partial.yields, !yields.isEmpty {
                        Label(yields, systemImage: "person.2")
                    }

                    if let minutes = partial.totalMinutes {
                        Label("\(minutes) min", systemImage: "clock")
                    }
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }

            if let ingredients = partial.ingredients, !ingredients.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ingredients")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(ingredients.indices, id: \.self) { index in
                            let ingredient = ingredients[index]

                            HStack(alignment: .top, spacing: 12) {
                                Circle()
                                    .fill(Color.cauldronOrange.opacity(0.25))
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 6)

                                VStack(alignment: .leading, spacing: 4) {
                                    if let value = ingredient.quantityValue,
                                       let unit = ingredient.quantityUnit {
                                        Text("\(value, specifier: "%.1f") \(unit)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }

                                    Text(ingredient.name ?? "")
                                        .font(.body)

                                    if let note = ingredient.note {
                                        Text(note)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.cauldronSecondaryBackground)
                )
            }

            if let steps = partial.steps, !steps.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Instructions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(steps.indices, id: \.self) { index in
                            let step = steps[index]

                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .padding(8)
                                    .background(Circle().fill(Color.cauldronOrange.opacity(0.15)))
                                    .foregroundColor(.cauldronOrange)

                                Text(step.text ?? "")
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.cauldronSecondaryBackground)
                )
            }

            if let tags = partial.tags, !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.cauldronOrange.opacity(0.15))
                                .foregroundColor(.cauldronOrange)
                                .cornerRadius(10)
                        }
                    }
                }
            }
        }
        .padding(20)
        .cardStyle()
    }

    private func errorSection(error: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)

            Text(error)
                .font(.subheadline)
                .foregroundColor(.red)

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
    }

    // Helper function to append tags to prompt
    private func appendToPrompt(_ tag: String) {
        if viewModel.prompt.isEmpty {
            viewModel.prompt = tag
        } else if !viewModel.prompt.contains(tag) {
            // Add with proper spacing
            let trimmed = viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            viewModel.prompt = trimmed + (trimmed.hasSuffix(",") ? " " : ", ") + tag
        }
    }
}

// MARK: - Recipe Tag Section

struct RecipeTagSection: View {
    let title: String
    let icon: String
    let tags: [String]
    let onTagTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        SuggestionChip(text: tag, onTap: {
                            onTagTap(tag)
                        })
                    }
                }
            }
        }
    }
}

// MARK: - Suggestion Chip

struct SuggestionChip: View {
    let text: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(Color.cauldronOrange.opacity(0.1))
                )
                .foregroundColor(.cauldronOrange)
                .overlay(
                    Capsule()
                        .stroke(Color.cauldronOrange.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AIRecipeGeneratorView(dependencies: .preview())
}
