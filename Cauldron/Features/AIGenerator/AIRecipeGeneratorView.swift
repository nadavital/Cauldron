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
                // Immersive Background
                AnimatedMeshGradient()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        if !isAvailable {
                            unavailableSection
                        } else {
                            // Combined section that expands/collapses
                            expandableInputSection
                                .shadow(color: Color.black.opacity(0.05), radius: 15, x: 0, y: 5)

                            if let partial = viewModel.partialRecipe {
                                recipePreviewSection(partial: partial)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }

                            if let error = viewModel.errorMessage {
                                errorSection(error: error)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                    .padding(.vertical, 28)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100) // Space for floating button
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.partialRecipe == nil)
                }
                
                // Floating action button (generate/generating/regenerate)
                if isAvailable && (viewModel.canGenerate || viewModel.isGenerating || viewModel.generatedRecipe != nil) {
                    floatingActionButton
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(), value: viewModel.canGenerate)
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
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
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
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        isInputExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 16) {
                    // Apple Intelligence icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.cauldronOrange,
                                        Color.cauldronOrange.opacity(0.7)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                            .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)

                        Image(systemName: "apple.intelligence")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .symbolEffect(.pulse, isActive: viewModel.isGenerating)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        // Show status text based on state
                        if viewModel.isGenerating {
                            HStack(spacing: 8) {
                                Text(viewModel.generationProgress.description)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.primary, .secondary],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            }
                        } else if viewModel.generatedRecipe != nil {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                                Text("Recipe Ready")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                        } else {
                            // Before generation starts - show ready state
                            Text("Generate with AI")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }

                        // Show recipe summary only when collapsed
                        if !isInputExpanded && (viewModel.isGenerating || viewModel.generatedRecipe != nil) {
                            if !viewModel.prompt.isEmpty {
                                Text(viewModel.prompt)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            } else if viewModel.hasSelectedCategories {
                                Text(viewModel.selectedCategoriesSummary)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text("Custom recipe")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        } else if !viewModel.isGenerating && viewModel.generatedRecipe == nil {
                             Text("Create your perfect dish")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // Show chevron when not generating
                    if !viewModel.isGenerating {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isInputExpanded ? 180 : 0))
                    }
                }
                .padding(20)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isGenerating)

            // Input fields - shown when expanded
            if isInputExpanded && !viewModel.isGenerating {
                VStack(alignment: .leading, spacing: 24) {
                    Divider()
                        .padding(.horizontal, 20)

                    // Prompt/Notes field
                    VStack(alignment: .leading, spacing: 12) {
                        Text(viewModel.hasSelectedCategories ? "Additional Notes (Optional)" : "What would you like to cook?")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)

                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $viewModel.prompt)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 120)
                                .padding(12)
                                .background(Color.cauldronBackground.opacity(0.3))
                                .cornerRadius(12)
                                .padding(.horizontal, 20)
                                .focused($isPromptFocused)

                            if viewModel.prompt.isEmpty {
                                Text(viewModel.hasSelectedCategories ? "e.g., no peanuts, extra spicy, low sodium..." : "Describe your ideal dish...")
                                    .foregroundColor(.secondary.opacity(0.5))
                                    .padding(.horizontal, 36)
                                    .padding(.vertical, 24)
                                    .allowsHitTesting(false)
                            }
                        }
                    }

                    // Categories
                    VStack(alignment: .leading, spacing: 16) {
                        if viewModel.allSelectedCategories.isEmpty {
                            Text("Or select categories")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 20)
                        }

                        selectedTagsSummary

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
                            options: RecipeCategory.all(in: .other),
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
                }
                .padding(.bottom, 24)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(.ultraThinMaterial)
        .background(Color.cauldronSecondaryBackground.opacity(0.5))
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private var selectedTagsSummary: some View {
        Group {
            if !viewModel.allSelectedCategories.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Selected", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.cauldronOrange)
                        .textCase(.uppercase)
                        .padding(.horizontal, 20)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(viewModel.allSelectedCategories.sorted(by: { $0.tagValue < $1.tagValue })) { tag in
                                TagView(tag.tagValue, isSelected: true, onRemove: {
                                    withAnimation {
                                        viewModel.removeCategory(tag)
                                    }
                                })
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.bottom, 8)
            }
        }
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
                withAnimation(.spring(response: 0.4)) {
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
                    Text("Generating Magic...")
                        .font(.headline)
                } else if viewModel.generatedRecipe != nil {
                    Image(systemName: "arrow.clockwise")
                        .font(.headline)
                    Text("Regenerate")
                        .font(.headline)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.headline)
                    Text("Generate Recipe")
                        .font(.headline)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .glassEffect(.regular.tint(.orange).interactive(), in: Capsule())
        }
        .padding(.bottom, 32)
    }

    private func recipePreviewSection(partial: GeneratedRecipe.PartiallyGenerated) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            // Title and Metadata Card
            if let title = partial.title {
                VStack(alignment: .leading, spacing: 16) {
                    Text(title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Time & Servings metadata
                    HStack(spacing: 20) {
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
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Ingredients Card
            if let ingredients = partial.ingredients, !ingredients.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Ingredients", systemImage: "basket")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(ingredients.enumerated()), id: \.offset) { index, ingredient in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundColor(.cauldronOrange)
                                    .padding(.top, 8)

                                Text(formatIngredient(ingredient))
                                    .font(.body)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 4)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
            }

            // Instructions Card
            if let steps = partial.steps, !steps.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Instructions", systemImage: "list.number")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 16) {
                                Text("\(index + 1)")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [.cauldronOrange, .orange],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    )
                                    .shadow(color: .orange.opacity(0.3), radius: 4, x: 0, y: 2)

                                Text(step.text ?? "")
                                    .font(.body)
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
            }
        }
    }

    private func errorSection(error: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundColor(.red)
                .symbolEffect(.pulse)

            VStack(alignment: .leading, spacing: 4) {
                Text("Generation Failed")
                    .font(.headline)
                    .foregroundColor(.red)
                
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.red.opacity(0.8))
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Color.red.opacity(0.08))
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.red.opacity(0.2), lineWidth: 1)
        )
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
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(tags, id: \.self) { tag in
                        Button {
                            onTagTap(tag)
                        } label: {
                            TagView(tag.tagValue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4) // Space for shadow
            }
        }
    }
}



// MARK: - Animated Mesh Gradient

struct AnimatedMeshGradient: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // Base background
            Color.cauldronBackground
            
            // Moving orbs
            GeometryReader { proxy in
                ZStack {
                    // Orb 1
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: proxy.size.width * 0.8)
                        .blur(radius: 60)
                        .offset(x: animate ? -50 : 50, y: animate ? -50 : 50)
                    
                    // Orb 2
                    Circle()
                        .fill(Color.yellow.opacity(0.15))
                        .frame(width: proxy.size.width * 0.7)
                        .blur(radius: 60)
                        .offset(x: animate ? 100 : -100, y: animate ? 100 : -50)
                    
                    // Orb 3
                    Circle()
                        .fill(Color.red.opacity(0.1))
                        .frame(width: proxy.size.width * 0.6)
                        .blur(radius: 50)
                        .offset(x: animate ? -30 : 150, y: animate ? 150 : -30)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
    }
}

// MARK: - View Modifiers

extension View {
    func pressEvents(onPress: @escaping (Bool) -> Void) -> some View {
        self.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onPress(true) }
                .onEnded { _ in onPress(false) }
        )
    }
}

#Preview {
    AIRecipeGeneratorView(dependencies: .preview())
}
