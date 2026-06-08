//
//  CookModeView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import SwiftUI
import AudioToolbox

/// Step-by-step cooking mode view
struct CookModeView: View {
    let recipe: Recipe
    let coordinator: CookModeCoordinator
    let dependencies: DependencyContainer

    @ObservedObject private var timerManager: TimerManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss
    @State private var showingAllTimers = false
    @State private var showingEndSessionAlert = false
    @State private var checkedIngredientIDs: Set<UUID> = []
    @State private var scaleFactor: Double = 1.0
    @State private var unitSystem: UnitSystem = .original

    /// Ingredients adjusted for the current scale factor and unit system.
    /// Ingredient ids are preserved by both transforms, so check-off state
    /// survives scaling and conversion.
    private var displayedIngredients: [Ingredient] {
        let scaled = scaleFactor == 1.0
            ? recipe.ingredients
            : RecipeScaler.scale(recipe, by: scaleFactor).recipe.ingredients
        return UnitConverter.convert(scaled, to: unitSystem)
    }

    private var scaleFactorLabel: String {
        switch scaleFactor {
        case 0.5: return "½×"
        case 1.0: return "1×"
        default: return "\(scaleFactor.formatted(.number.precision(.fractionLength(0...1))))×"
        }
    }

    init(recipe: Recipe, coordinator: CookModeCoordinator, dependencies: DependencyContainer) {
        self.recipe = recipe
        self.coordinator = coordinator
        self.dependencies = dependencies
        _timerManager = ObservedObject(wrappedValue: dependencies.timerManager)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            ProgressView(value: coordinator.progress)
                .tint(Color.cauldronOrange)

            if isRegularWidthLayout {
                regularWidthContent
            } else {
                compactContent
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Minimize", systemImage: "chevron.down") {
                    coordinator.minimizeToBackground()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Navigate to recipe detail with current step highlighted
                    NavigationLink {
                        RecipeDetailView(
                            recipe: recipe,
                            dependencies: dependencies,
                            highlightedStepIndex: coordinator.currentStepIndex
                        )
                    } label: {
                        Label("View Recipe", systemImage: "book.fill")
                    }

                    // Scale servings live
                    Picker("Scale Servings", selection: $scaleFactor) {
                        Text("½×").tag(0.5)
                        Text("1×").tag(1.0)
                        Text("2×").tag(2.0)
                        Text("3×").tag(3.0)
                    }

                    // Convert units
                    Picker("Units", selection: $unitSystem) {
                        ForEach(UnitSystem.allCases) { system in
                            Text(system.label).tag(system)
                        }
                    }

                    // View all timers
                    Button {
                        showingAllTimers = true
                    } label: {
                        Label("All Timers (\(timerManager.activeTimers.count))", systemImage: "timer")
                    }

                    Divider()

                    // End session
                    Button(role: .destructive) {
                        showingEndSessionAlert = true
                    } label: {
                        Label("End Cooking", systemImage: "xmark.circle")
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "ellipsis.circle")

                        // Timer badge
                        if !timerManager.activeTimers.isEmpty {
                            Circle()
                                .fill(Color.cauldronOrange)
                                .frame(width: 8, height: 8)
                                .offset(x: 4, y: -4)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAllTimers) {
            AllTimersView(timerManager: timerManager)
        }
        .alert("End Cooking Session?", isPresented: $showingEndSessionAlert) {
            Button("Cancel", role: .cancel) {}
            Button("End Session", role: .destructive) {
                coordinator.endSession()
            }
        } message: {
            Text("Your progress will be saved and you can resume anytime.")
        }
        .onAppear {
            // Record in cooking history (only once when starting)
            if coordinator.currentStepIndex == 0 {
                Task {
                    try? dependencies.cookingHistoryRepository.recordCooked(
                        recipeId: recipe.id,
                        recipeTitle: recipe.title
                    )
                }
            }
        }
    }

    private var isRegularWidthLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var compactContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    recipeVisualHeader
                        .overlay(alignment: .bottom) {
                            stepProgressBadge
                                .padding(.horizontal, 16)
                                .offset(y: 20)
                        }
                    VStack(spacing: 24) {
                        stepContent
                        timersSection
                    }
                    .padding(.top, 34)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }

            Spacer()

            navigationControls
        }
    }

    private var regularWidthContent: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        recipeVisualHeader
                            .overlay(alignment: .bottom) {
                                stepProgressBadge
                                    .padding(.horizontal, 24)
                                    .offset(y: 22)
                            }
                        VStack(spacing: 28) {
                            stepContent
                        }
                        .padding(.top, 38)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                }

                Spacer(minLength: 0)
                navigationControls
            }

            Divider()

            workbenchPanel
                .frame(width: 360)
                .background(Color.cauldronSecondaryBackground)
        }
    }

    private var stepProgressBadge: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.number")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.cauldronOrange)
                .frame(width: 34, height: 34)
                .background(Color.cauldronOrange.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Step \(coordinator.currentStepIndex + 1) of \(coordinator.totalSteps)")
                    .font(isRegularWidthLayout ? .title3.weight(.bold) : .headline.weight(.semibold))
                    .foregroundStyle(Color.cauldronOrange)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.cauldronSecondaryBackground, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
    }

    private var recipeVisualHeader: some View {
        RecipeImageView(
            imageURL: recipe.imageURL,
            size: .preview,
            showPlaceholderText: false,
            recipeImageService: dependencies.recipeImageService,
            recipeId: recipe.id,
            ownerId: recipe.ownerId
        )
        .frame(height: isRegularWidthLayout ? 300 : 230)
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color.appBackground.opacity(0),
                    Color.appBackground.opacity(0.5),
                    Color.appBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)
            .allowsHitTesting(false)
        }
        .backgroundExtensionEffect(isEnabled: isRegularWidthLayout)
        .ignoresSafeArea(edges: .top)
        .clipped()
    }

    private var stepContent: some View {
        Group {
            if let currentStep = coordinator.currentStep {
                Text(currentStep.text)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(Color.cauldronSecondaryBackground)
                    .cornerRadius(Theme.Radius.large)
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            }
        }
    }

    @ViewBuilder
    private var timersSection: some View {
        if let currentStep = coordinator.currentStep {
            VStack(spacing: 12) {
                // Show ALL active timers (not just for current step)
                if !timerManager.activeTimers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Active Timers")
                            .font(.headline)
                            .foregroundColor(.cauldronOrange)

                        ForEach(timerManager.activeTimers) { activeTimer in
                            ImprovedTimerRowView(timer: activeTimer, timerManager: timerManager)
                        }
                    }
                }

                // Show start buttons for timers defined in current step that haven't been started yet
                if !currentStep.timers.isEmpty {
                    let stepActiveTimers = timerManager.activeTimers.filter { $0.stepIndex == coordinator.currentStepIndex }

                    VStack(alignment: .leading, spacing: 8) {
                        if !timerManager.activeTimers.isEmpty {
                            Text("Step Timers")
                                .font(.headline)
                                .padding(.top, 8)
                        }

                        ForEach(currentStep.timers) { timerSpec in
                            // Check if this timer is already running for this step
                            let isRunning = stepActiveTimers.contains { activeTimer in
                                activeTimer.spec.seconds == timerSpec.seconds &&
                                activeTimer.spec.label == timerSpec.label
                            }

                            if !isRunning {
                                // Start button for timer
                                Button {
                                    timerManager.startTimer(
                                        spec: timerSpec,
                                        stepIndex: coordinator.currentStepIndex,
                                        recipeName: recipe.title
                                    )
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(timerSpec.label)
                                                .font(.headline)
                                            Text(timerSpec.displayDuration)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        Image(systemName: "play.circle.fill")
                                            .font(.title)
                                            .foregroundColor(.cauldronOrange)
                                    }
                                    .padding(16)
                                    .background(Color.cauldronSecondaryBackground)
                                    .cornerRadius(Theme.Radius.large)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Quick timer button
                QuickTimerButton(
                    timerManager: timerManager,
                    recipeName: recipe.title,
                    stepIndex: coordinator.currentStepIndex
                )
            }
        }
    }

    private var workbenchPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ingredientChecklistSection
                timerWorkbenchSection
            }
            .padding(20)
        }
    }

    private var ingredientChecklistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: Theme.Spacing.xs) {
                Text("Ingredients")
                    .font(.headline)
                if scaleFactor != 1.0 {
                    Text(scaleFactorLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.cauldronOrange)
                        .padding(.horizontal, Theme.Spacing.xs)
                        .padding(.vertical, 2)
                        .background(Color.cauldronOrange.opacity(0.15), in: Capsule())
                }
                Spacer()
                Text("\(checkedIngredientIDs.count)/\(displayedIngredients.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if displayedIngredients.isEmpty {
                Text("No ingredients available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayedIngredients) { ingredient in
                    let isChecked = checkedIngredientIDs.contains(ingredient.id)

                    Button {
                        toggleIngredientCheck(ingredient.id)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isChecked ? Color.cauldronOrange : .secondary)
                                .font(.body)
                                .contentTransition(.symbolEffect(.replace))
                                .symbolEffect(.bounce, value: isChecked)

                            Text(ingredient.displayString)
                                .font(.subheadline)
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(isChecked ? .secondary : .primary)
                                .strikethrough(isChecked)

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var timerWorkbenchSection: some View {
        let pendingTimers = unstartedCurrentStepTimers

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Timers")
                    .font(.headline)
                Spacer()
                if !timerManager.activeTimers.isEmpty {
                    Text("\(timerManager.activeTimers.count) active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if timerManager.activeTimers.isEmpty && pendingTimers.isEmpty {
                Text("No active timers")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !timerManager.activeTimers.isEmpty {
                ForEach(timerManager.activeTimers) { activeTimer in
                    ImprovedTimerRowView(timer: activeTimer, timerManager: timerManager)
                }
            }

            if !pendingTimers.isEmpty {
                Text("Current Step Timers")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.top, timerManager.activeTimers.isEmpty ? 0 : 4)

                ForEach(Array(pendingTimers.enumerated()), id: \.element.id) { _, timerSpec in
                    Button {
                        timerManager.startTimer(
                            spec: timerSpec,
                            stepIndex: coordinator.currentStepIndex,
                            recipeName: recipe.title
                        )
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(timerSpec.label)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(timerSpec.displayDuration)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "play.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.cauldronOrange)
                        }
                        .padding(12)
                        .background(Color.cauldronBackground, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }

            QuickTimerButton(
                timerManager: timerManager,
                recipeName: recipe.title,
                stepIndex: coordinator.currentStepIndex
            )
            .padding(.top, 2)
        }
    }

    private var unstartedCurrentStepTimers: [TimerSpec] {
        guard let currentStep = coordinator.currentStep else { return [] }
        let stepActiveTimers = timerManager.activeTimers.filter { $0.stepIndex == coordinator.currentStepIndex }

        return currentStep.timers.filter { timerSpec in
            !stepActiveTimers.contains { activeTimer in
                activeTimer.spec.seconds == timerSpec.seconds &&
                activeTimer.spec.label == timerSpec.label
            }
        }
    }

    private func toggleIngredientCheck(_ ingredientID: UUID) {
        if checkedIngredientIDs.contains(ingredientID) {
            checkedIngredientIDs.remove(ingredientID)
        } else {
            checkedIngredientIDs.insert(ingredientID)
        }
    }

    /// Celebratory overlay shown when the cook finishes the last step.
    private var navigationControls: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    coordinator.previousStep()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.extraLarge)
                .disabled(coordinator.isFirstStep)

                Button {
                    if coordinator.isLastStep {
                        Haptics.success()
                        coordinator.endSession()
                    } else {
                        coordinator.nextStep()
                    }
                } label: {
                    HStack {
                        Text(coordinator.isLastStep ? "Done" : "Next")
                            .fontWeight(.semibold)
                        Image(systemName: coordinator.isLastStep ? "checkmark" : "chevron.right")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
                .tint(.cauldronOrange)
            }
        }
        .padding()
    }
}

#Preview {
    let container = DependencyContainer.preview()
    let coordinator = CookModeCoordinator(dependencies: container)
    let recipe = Recipe(
        title: "Sample Recipe",
        ingredients: [],
        steps: [
            CookStep(index: 0, text: "Preheat oven to 350°F", timers: []),
            CookStep(index: 1, text: "Bake for 30 minutes", timers: [.minutes(30, label: "Bake")])
        ]
    )

    Task { @MainActor in
        await coordinator.startCooking(recipe)
    }

    return NavigationStack {
        CookModeView(
            recipe: recipe,
            coordinator: coordinator,
            dependencies: container
        )
    }
    .dependencies(container)
}
