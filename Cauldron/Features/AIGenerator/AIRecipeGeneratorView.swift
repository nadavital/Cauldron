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
    @State private var isInputExpanded: Bool = true

    init(dependencies: DependencyContainer) {
        _viewModel = StateObject(wrappedValue: AIRecipeGeneratorViewModel(dependencies: dependencies))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 24) {
                        if !isAvailable {
                            unavailableSection
                        } else {
                            // Combined section that expands/collapses
                            expandableInputSection

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
                    .padding(.bottom, 100) // Space for floating button
                }
                .background(Color.cauldronBackground.ignoresSafeArea())

                // Floating action button (generate/generating/regenerate)
                if isAvailable {
                    floatingActionButton
                }
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
            .onChange(of: viewModel.isGenerating) { oldValue, newValue in
                // Auto-collapse input section when generation starts
                if !oldValue && newValue {
                    withAnimation(.spring(response: 0.4)) {
                        isInputExpanded = false
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var expandableInputSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - always visible
            Button {
                // Only allow expanding/collapsing when not generating
                if !viewModel.isGenerating {
                    withAnimation(.spring(response: 0.3)) {
                        isInputExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    // Apple Intelligence icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
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
                            .frame(width: 36, height: 36)

                        Image(systemName: "apple.intelligence")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        // Show status text based on state
                        if viewModel.isGenerating {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.cauldronOrange)
                                Text(viewModel.generationProgress.description)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                        } else if viewModel.generatedRecipe != nil {
                            HStack(spacing: 8) {
                                Image(systemName: viewModel.generationProgress.systemImage)
                                    .font(.caption)
                                    .foregroundColor(.green)
                                Text(viewModel.generationProgress.description)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                        } else {
                            // Before generation starts - show ready state
                            Text("Generate with AI")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        // Show recipe summary only when collapsed
                        if !isInputExpanded && (viewModel.isGenerating || viewModel.generatedRecipe != nil) {
                            if !viewModel.prompt.isEmpty {
                                Text(viewModel.prompt)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            } else if viewModel.hasSelectedCategories {
                                Text(viewModel.selectedCategoriesSummary)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text("Custom recipe")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Spacer()

                    // Show chevron when not generating
                    if !viewModel.isGenerating {
                        Image(systemName: isInputExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isGenerating)

            // Input fields - shown when expanded
            if isInputExpanded && !viewModel.isGenerating {
                VStack(alignment: .leading, spacing: 20) {
                    Divider()
                        .padding(.horizontal, 16)

                    // Prompt/Notes field
                    VStack(alignment: .leading, spacing: 12) {
                        Text(viewModel.hasSelectedCategories ? "Additional Notes (Optional)" : "What would you like to cook?")
                            .font(.headline)

                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $viewModel.prompt)
                                .frame(minHeight: 100)
                                .padding(14)
                                .background(Color.cauldronBackground)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isPromptFocused ? Color.cauldronOrange : Color.secondary.opacity(0.15), lineWidth: 1.5)
                                )
                                .focused($isPromptFocused)

                            if viewModel.prompt.isEmpty {
                                Text(viewModel.hasSelectedCategories ? "e.g., no peanuts, extra spicy, low sodium..." : "Describe your ideal dish...")
                                    .foregroundColor(.secondary.opacity(0.5))
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 22)
                                    .allowsHitTesting(false)
                            }
                        }
                    }

                    // Categories
                    Text("Or select categories:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    // Cuisine
                    CategorySelectionRow(
                        title: "Cuisine",
                        icon: "map",
                        options: RecipeCategory.all(in: .cuisine),
                        selected: $viewModel.selectedCuisines
                    )

                    // Dietary
                    CategorySelectionRow(
                        title: "Diet",
                        icon: "leaf",
                        options: RecipeCategory.all(in: .dietary),
                        selected: $viewModel.selectedDiets
                    )

                    // Time
                    CategorySelectionRow(
                        title: "Time",
                        icon: "clock",
                        options: [.quickEasy, .onePot, .airFryer],
                        selected: $viewModel.selectedTimes
                    )

                    // Meal Type
                    CategorySelectionRow(
                        title: "Meal",
                        icon: "fork.knife",
                        options: RecipeCategory.all(in: .mealType),
                        selected: $viewModel.selectedTypes
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(Color.cauldronSecondaryBackground)
        .cornerRadius(12)
    }

    private var unifiedStatusSection: some View {
        HStack(spacing: 12) {
            // Apple Intelligence icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
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
                    .frame(width: 36, height: 36)

                Image(systemName: "apple.intelligence")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Show status text based on state
                if viewModel.isGenerating {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.cauldronOrange)
                        Text(viewModel.generationProgress.description)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                } else if viewModel.generatedRecipe != nil {
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.generationProgress.systemImage)
                            .font(.caption)
                            .foregroundColor(.green)
                        Text(viewModel.generationProgress.description)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                } else {
                    // Before generation starts - show ready state
                    Text("Generate with AI")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                // Show recipe summary only when generating or complete
                if viewModel.isGenerating || viewModel.generatedRecipe != nil {
                    if !viewModel.prompt.isEmpty {
                        Text(viewModel.prompt)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else if viewModel.hasSelectedCategories {
                        Text(viewModel.selectedCategoriesSummary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Custom recipe")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Show regenerate button when recipe is complete
            if viewModel.generatedRecipe != nil && !viewModel.isGenerating {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        isInputExpanded = true
                    }
                    viewModel.regenerate()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(.cauldronOrange)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cauldronSecondaryBackground)
        .cornerRadius(12)
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

    private var combinedInputSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Prompt/Notes field
            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.hasSelectedCategories ? "Additional Notes (Optional)" : "What would you like to cook?")
                    .font(.headline)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $viewModel.prompt)
                        .frame(minHeight: 100)
                        .padding(14)
                        .background(Color.cauldronBackground)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isPromptFocused ? Color.cauldronOrange : Color.secondary.opacity(0.15), lineWidth: 1.5)
                        )
                        .focused($isPromptFocused)

                    if viewModel.prompt.isEmpty {
                        Text(viewModel.hasSelectedCategories ? "e.g., no peanuts, extra spicy, low sodium..." : "Describe your ideal dish...")
                            .foregroundColor(.secondary.opacity(0.5))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 22)
                            .allowsHitTesting(false)
                    }
                }
            }

            Divider()
                .padding(.vertical, 4)

            // Categories
            Text("Or select categories:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Cuisine
            CategorySelectionRow(
                title: "Cuisine",
                icon: "map",
                options: RecipeCategory.all(in: .cuisine),
                selected: $viewModel.selectedCuisines
            )

            // Dietary
            CategorySelectionRow(
                title: "Diet",
                icon: "leaf",
                options: RecipeCategory.all(in: .dietary),
                selected: $viewModel.selectedDiets
            )

            // Time
            CategorySelectionRow(
                title: "Time",
                icon: "clock",
                options: [.quickEasy, .onePot, .airFryer],
                selected: $viewModel.selectedTimes
            )

            // Meal Type
            CategorySelectionRow(
                title: "Meal",
                icon: "fork.knife",
                options: RecipeCategory.all(in: .mealType),
                selected: $viewModel.selectedTypes
            )
        }
        .padding(20)
        .cardStyle()
    }

    private var floatingActionButton: some View {
        Button {
            if viewModel.isGenerating {
                // Do nothing when generating
            } else if viewModel.generatedRecipe != nil {
                // Regenerate
                withAnimation(.spring(response: 0.3)) {
                    isInputExpanded = true
                }
                viewModel.regenerate()
            } else {
                // Generate
                viewModel.generateRecipe()
                isPromptFocused = false
            }
        } label: {
            HStack(spacing: 12) {
                if viewModel.isGenerating {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                    Text("Generating")
                        .font(.headline)
                } else if viewModel.generatedRecipe != nil {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3)
                    Text("Regenerate")
                        .font(.headline)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.title3)
                    Text("Generate Recipe")
                        .font(.headline)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .glassEffect(.regular.tint(.orange).interactive(), in: Capsule())
        }
        .disabled(viewModel.isGenerating || (!viewModel.canGenerate && viewModel.generatedRecipe == nil))
        .opacity((viewModel.canGenerate || viewModel.generatedRecipe != nil || viewModel.isGenerating) ? 1.0 : 0.5)
        .padding(.bottom, 32)
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
                    tags: RecipeCategory.all(in: .cuisine),
                    onTagTap: { tag in
                        appendToPrompt(tag.displayName)
                    }
                )

                // Dietary
                RecipeTagSection(
                    title: "Diet",
                    icon: "leaf",
                    tags: RecipeCategory.all(in: .dietary),
                    onTagTap: { tag in
                        appendToPrompt(tag.displayName)
                    }
                )

                // Time
                RecipeTagSection(
                    title: "Time",
                    icon: "clock",
                    tags: [.quickEasy, .onePot, .airFryer],
                    onTagTap: { tag in
                        appendToPrompt(tag.displayName)
                    }
                )

                // Type
                RecipeTagSection(
                    title: "Type",
                    icon: "fork.knife",
                    tags: RecipeCategory.all(in: .mealType),
                    onTagTap: { tag in
                        appendToPrompt(tag.displayName)
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

    private func recipePreviewSection(partial: GeneratedRecipe.PartiallyGenerated) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title and Metadata Card
            if let title = partial.title {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)

                    // Time & Servings metadata
                    HStack(spacing: 16) {
                        if let minutes = partial.totalMinutes {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                    .foregroundColor(.cauldronOrange)
                                Text("\(minutes) min")
                            }
                        }

                        if let yields = partial.yields, !yields.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "person.2")
                                    .foregroundColor(.cauldronOrange)
                                Text(yields)
                            }
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)


                }
                .padding()
                .cardStyle()
            }

            // Ingredients Card
            if let ingredients = partial.ingredients, !ingredients.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ingredients")
                        .font(.title2)
                        .fontWeight(.bold)

                    ForEach(Array(ingredients.enumerated()), id: \.offset) { index, ingredient in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundColor(.cauldronOrange)
                                .padding(.top, 6)

                            Text(formatIngredient(ingredient))
                                .font(.body)
                                .lineLimit(nil)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding()
                .cardStyle()
            }

            // Instructions Card
            if let steps = partial.steps, !steps.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Instructions")
                        .font(.title2)
                        .fontWeight(.bold)

                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.cauldronOrange)
                                .clipShape(Circle())

                            Text(step.text ?? "")
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding()
                .cardStyle()
            }
        }
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

    // Helper function to format ingredient for display (matching RecipeDetailView style)
    private func formatIngredient(_ ingredient: GeneratedIngredient.PartiallyGenerated) -> String {
        var parts: [String] = []

        // Add quantity and unit if available
        if let value = ingredient.quantityValue,
           let unit = ingredient.quantityUnit {
            let formattedValue = value.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", value)
                : String(format: "%.1f", value)
            parts.append("\(formattedValue) \(unit)")
        }

        // Add name
        if let name = ingredient.name {
            parts.append(name)
        }

        // Add note if available
        if let note = ingredient.note {
            parts.append("(\(note))")
        }

        return parts.joined(separator: " ")
    }
}

// MARK: - Recipe Tag Section

struct RecipeTagSection: View {
    let title: String
    let icon: String
    let tags: [RecipeCategory]
    let onTagTap: (RecipeCategory) -> Void

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
                        SuggestionChip(category: tag, onTap: {
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
    let category: RecipeCategory
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(category.emoji)
                Text(category.displayName)
            }
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(category.color.opacity(0.15))
            )
            .foregroundColor(category.color)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category Selection Row

struct CategorySelectionRow: View {
    let title: String
    let icon: String
    let options: [RecipeCategory]
    @Binding var selected: Set<RecipeCategory>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(options, id: \.self) { option in
                        CategoryChip(
                            category: option,
                            isSelected: selected.contains(option),
                            onTap: {
                                if selected.contains(option) {
                                    selected.remove(option)
                                } else {
                                    selected.insert(option)
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Category Chip

struct CategoryChip: View {
    let category: RecipeCategory
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(category.emoji)
                Text(category.displayName)
            }
            .font(.caption)
            .fontWeight(.medium)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isSelected ? category.color : category.color.opacity(0.15))
            )
            .foregroundColor(isSelected ? .white : category.color)
            .overlay(
                Capsule()
                    .stroke(category.color, lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

#Preview {
    AIRecipeGeneratorView(dependencies: .preview())
}
