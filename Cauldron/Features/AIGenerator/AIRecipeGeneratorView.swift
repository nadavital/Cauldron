//
//  AIRecipeGeneratorView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/14/25.
//

import SwiftUI
import Combine
import FoundationModels

/// View for generating recipes using Apple Intelligence
struct AIRecipeGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AIRecipeGeneratorViewModel
    @FocusState private var isPromptFocused: Bool
    @State private var isAvailable: Bool = false
    @State private var showCategories = false
    @State private var placeholderIndex = 0

    /// Evocative examples that gently cycle through the empty prompt field.
    private let cravingExamples = [
        "cozy ramen for a rainy night",
        "a showstopper dinner-party dessert",
        "a high-protein lunch in 20 minutes",
        "something spicy and comforting",
        "a bright, colorful summer salad",
        "a cozy one-pot meal for tonight"
    ]

    /// Open-ended seeds for the "Surprise me" one-tap.
    private let surprisePrompts = [
        "a surprising dinner using everyday pantry staples",
        "an adventurous dish from a cuisine I rarely cook",
        "a nostalgic comfort food, reinvented",
        "an impressive dessert that's secretly easy",
        "a vibrant, colorful plate full of veggies",
        "a cozy weeknight dinner with a clever twist"
    ]

    private let placeholderTimer = Timer.publish(every: 3.5, on: .main, in: .common).autoconnect()

    private var isBusyOrDone: Bool {
        viewModel.isGenerating || viewModel.generatedRecipe != nil
    }

    init(dependencies: DependencyContainer) {
        _viewModel = State(initialValue: AIRecipeGeneratorViewModel(dependencies: dependencies))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Immersive Background
                AnimatedMeshGradient()
                    .ignoresSafeArea()
                
                ScrollView {
                    GlassEffectContainer(spacing: Theme.Spacing.md) {
                        VStack(spacing: Theme.Spacing.xl) {
                            if !isAvailable {
                                AIUnavailableCard()
                            } else {
                                if isBusyOrDone {
                                    generationStatusStrip
                                } else {
                                    promptCard
                                    categoriesSection
                                }

                                if let partial = viewModel.partialRecipe {
                                    AIRecipePreview(partial: partial)
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                }

                                if let error = viewModel.errorMessage {
                                    AIErrorCard(error: error)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xl)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, 100) // Space for floating button
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.partialRecipe == nil)
                }
                .onTapGesture {
                    isPromptFocused = false
                }
                
                // Floating action button (generate/generating/regenerate)
                if isAvailable && (viewModel.canGenerate || viewModel.isGenerating || viewModel.generatedRecipe != nil) {
                    floatingActionButton
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(), value: viewModel.canGenerate)
            .animation(.spring(), value: viewModel.selectedCuisines.count)
            .animation(.spring(), value: viewModel.selectedDiets.count)
            .animation(.spring(), value: viewModel.selectedTimes.count)
            .animation(.spring(), value: viewModel.selectedTypes.count)
            .animation(.spring(), value: viewModel.prompt)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        viewModel.cancelGeneration()
                        dismiss()
                    }
                }
            }
            .task {
                isAvailable = await viewModel.checkAvailability() || RuntimeEnvironment.forceAIGeneratorUI
            }
        }
    }

    // MARK: - Sections

    // MARK: - Idle input

    /// The "describe a dish" prompt card (primary path) — warm hero, a gently
    /// rotating placeholder for ambient inspiration, and a "Surprise me" shortcut.
    private var promptCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // Warm hero — doubles as the screen's title (nav title is intentionally blank).
            HStack(spacing: Theme.Spacing.sm) {
                aiIcon(size: 44)
                Text("What are you craving?")
                    .font(.system(.title2, design: .serif).weight(.bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.prompt)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 96)
                    .padding(Theme.Spacing.sm)
                    .background(Color.appSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .focused($isPromptFocused)

                if viewModel.prompt.isEmpty {
                    Group {
                        if viewModel.hasSelectedCategories {
                            Text("Add anything else… e.g. no peanuts, extra spicy")
                        } else {
                            // Cycles through evocative examples so it never feels static.
                            Text("Try “\(cravingExamples[placeholderIndex])”")
                                .id(placeholderIndex)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                ))
                        }
                    }
                    .font(.body)
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.lg)
                    .allowsHitTesting(false)
                }
            }

            // One-tap magic: fill a creative prompt and start cooking immediately.
            if viewModel.prompt.isEmpty {
                Button {
                    Haptics.light()
                    let pick = surprisePrompts.randomElement() ?? cravingExamples[placeholderIndex]
                    viewModel.prompt = pick
                    isPromptFocused = false
                    viewModel.generateRecipe()
                } label: {
                    Label("Surprise me", systemImage: "wand.and.stars")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
                .tint(.cauldronOrange)
            }
        }
        .padding(Theme.Spacing.lg)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.xLarge, style: .continuous))
        .onReceive(placeholderTimer) { _ in
            guard viewModel.prompt.isEmpty, !viewModel.hasSelectedCategories else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                placeholderIndex = (placeholderIndex + 1) % cravingExamples.count
            }
        }
    }

    /// Categories tucked behind a disclosure so the prompt stays the hero.
    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Button {
                withAnimation(Theme.Animation.snappy) { showCategories.toggle() }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Label("Refine with categories", systemImage: "slider.horizontal.3")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    if !viewModel.allSelectedCategories.isEmpty {
                        Text("\(viewModel.allSelectedCategories.count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Color.cauldronOrange, in: Circle())
                    }
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showCategories ? 180 : 0))
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }
            .buttonStyle(.plain)

            // Chosen categories stay visible even when collapsed.
            if !showCategories {
                selectedTagsSummary
            }

            if showCategories {
                selectedTagsSummary
                CategorySelectionRow(title: "Cuisine", icon: "map", options: RecipeCategory.all(in: .cuisine), selected: $viewModel.selectedCuisines)
                CategorySelectionRow(title: "Diet", icon: "leaf", options: RecipeCategory.all(in: .dietary), selected: $viewModel.selectedDiets)
                CategorySelectionRow(title: "Time", icon: "clock", options: RecipeCategory.all(in: .other), selected: $viewModel.selectedTimes)
                CategorySelectionRow(title: "Meal", icon: "fork.knife", options: RecipeCategory.all(in: .mealType), selected: $viewModel.selectedTypes)
            }
        }
        .padding(.vertical, Theme.Spacing.lg)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.xLarge, style: .continuous))
    }

    @ViewBuilder
    private var selectedTagsSummary: some View {
        if !viewModel.allSelectedCategories.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label("Selected", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.cauldronOrange)
                    .textCase(.uppercase)
                    .padding(.horizontal, Theme.Spacing.lg)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.allSelectedCategories.sorted(by: { $0.tagValue < $1.tagValue })) { tag in
                            TagView(tag.tagValue, isSelected: true, onRemove: {
                                withAnimation { viewModel.removeCategory(tag) }
                            })
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Generating / done

    /// Slim status strip shown while generating or after a recipe is ready.
    private var generationStatusStrip: some View {
        HStack(spacing: Theme.Spacing.sm) {
            aiIcon(size: 36)

            VStack(alignment: .leading, spacing: 2) {
                if viewModel.isGenerating {
                    Text(viewModel.generationProgress.description)
                        .font(.headline)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Recipe ready")
                            .font(.headline)
                    }
                }

                Text(promptSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if viewModel.generatedRecipe != nil && !viewModel.isGenerating {
                Button {
                    viewModel.regenerate()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.headline)
                        .foregroundStyle(Color.cauldronOrange)
                }
                .accessibilityLabel("Regenerate")
            }
        }
        .padding(Theme.Spacing.md)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
    }

    private var promptSummary: String {
        if !viewModel.prompt.isEmpty { return viewModel.prompt }
        if viewModel.hasSelectedCategories { return viewModel.selectedCategoriesSummary }
        return "Custom recipe"
    }

    /// Apple Intelligence brand icon used across the AI generator.
    private func aiIcon(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.cauldronWarmGradient)
                .frame(width: size, height: size)
                .shadow(color: Color.cauldronOrange.opacity(0.3), radius: 8, x: 0, y: 4)
            Image(systemName: "apple.intelligence")
                .font(.system(size: size * 0.45))
                .foregroundColor(.white)
                .symbolEffect(.pulse, isActive: viewModel.isGenerating)
        }
    }

    /// Single primary action that morphs Generate → generating → Save.
    private var floatingActionButton: some View {
        Button {
            if viewModel.isGenerating {
                // No-op while generating.
            } else if viewModel.generatedRecipe != nil {
                guard !viewModel.isSaving else { return }
                viewModel.isSaving = true
                Task {
                    if await viewModel.saveRecipe() {
                        dismiss()
                    } else {
                        viewModel.isSaving = false
                    }
                }
            } else {
                viewModel.generateRecipe()
                isPromptFocused = false
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                if viewModel.isGenerating {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                    Text("Cooking up your recipe…")
                        .font(.headline)
                } else if viewModel.generatedRecipe != nil {
                    if viewModel.isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.headline)
                    }
                    Text("Save Recipe")
                        .font(.headline)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.headline)
                    Text("Generate Recipe")
                        .font(.headline)
                }
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, Theme.Spacing.xxs)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.extraLarge)
        .tint(.cauldronOrange)
        .disabled(viewModel.isGenerating || viewModel.isSaving)
        .padding(.bottom, Theme.Spacing.xl)
    }

}

// MARK: - Recipe Tag Section

#Preview {
    AIRecipeGeneratorView(dependencies: .preview())
}
