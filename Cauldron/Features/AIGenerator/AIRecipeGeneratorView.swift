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
                                    categoriesCard
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
                isAvailable = await viewModel.checkAvailability() || RuntimeEnvironment.forceAIGeneratorUI
            }
        }
    }

    // MARK: - Sections

    // MARK: - Idle input

    /// The "describe a dish" prompt card (primary path).
    private var promptCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                aiIcon(size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Generate with AI")
                        .font(.system(.title3, design: .serif).weight(.semibold))
                    Text("Describe a dish, or pick categories below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.prompt)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
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
        }
        .padding(Theme.Spacing.lg)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.xLarge, style: .continuous))
    }

    /// Category selection card (cuisine / diet / time / meal), with chosen tags
    /// surfaced as removable chips at the top.
    private var categoriesCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            selectedTagsSummary

            CategorySelectionRow(title: "Cuisine", icon: "map", options: RecipeCategory.all(in: .cuisine), selected: $viewModel.selectedCuisines)
            CategorySelectionRow(title: "Diet", icon: "leaf", options: RecipeCategory.all(in: .dietary), selected: $viewModel.selectedDiets)
            CategorySelectionRow(title: "Time", icon: "clock", options: RecipeCategory.all(in: .other), selected: $viewModel.selectedTimes)
            CategorySelectionRow(title: "Meal", icon: "fork.knife", options: RecipeCategory.all(in: .mealType), selected: $viewModel.selectedTypes)
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

    private var floatingActionButton: some View {
        Button {
            if viewModel.isGenerating {
                // Do nothing when generating
            } else if viewModel.generatedRecipe != nil {
                viewModel.regenerate()
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
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, Theme.Spacing.xxs)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.extraLarge)
        .tint(.cauldronOrange)
        .padding(.bottom, Theme.Spacing.xl)
    }

}

// MARK: - Recipe Tag Section

#Preview {
    AIRecipeGeneratorView(dependencies: .preview())
}
