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
    @State private var viewModel: AIRecipeGeneratorViewModel
    @FocusState private var isPromptFocused: Bool
    @State private var isAvailable: Bool = false
    @State private var showCategories = false

    /// Tap-to-fill starter ideas to avoid the blank-prompt problem.
    private let starterPrompts = [
        "Quick weeknight dinner",
        "Use up leftover chicken",
        "Cozy soup for a cold night",
        "High-protein lunch",
        "Easy 5-ingredient dessert",
        "One-pot vegetarian meal"
    ]

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
            .navigationTitle("Generate Recipe")
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

    /// The "describe a dish" prompt card (primary path), with tap-to-fill ideas.
    private var promptCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.prompt)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 96)
                    .padding(Theme.Spacing.sm)
                    .background(Color.appSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .focused($isPromptFocused)

                if viewModel.prompt.isEmpty {
                    Text(viewModel.hasSelectedCategories ? "e.g. no peanuts, extra spicy, low sodium…" : "What would you like to cook?")
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.lg)
                        .allowsHitTesting(false)
                }
            }

            // Starter ideas (only before the user has typed anything)
            if viewModel.prompt.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(starterPrompts, id: \.self) { idea in
                            Button {
                                Haptics.light()
                                viewModel.prompt = idea
                            } label: {
                                Text(idea)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.cauldronOrange)
                                    .padding(.horizontal, Theme.Spacing.sm)
                                    .padding(.vertical, Theme.Spacing.xs)
                                    .background(Color.cauldronOrange.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(PressableScaleStyle())
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.xLarge, style: .continuous))
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
