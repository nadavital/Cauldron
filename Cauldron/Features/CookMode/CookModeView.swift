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
    let namespace: Namespace.ID

    @ObservedObject private var timerManager: TimerManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingAllTimers = false
    @State private var showingEndSessionAlert = false

    init(recipe: Recipe, coordinator: CookModeCoordinator, dependencies: DependencyContainer, namespace: Namespace.ID) {
        self.recipe = recipe
        self.coordinator = coordinator
        self.dependencies = dependencies
        self.namespace = namespace
        _timerManager = ObservedObject(wrappedValue: dependencies.timerManager)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            ProgressView(value: coordinator.progress)
                .tint(Color.cauldronOrange)

            // Current step
            ScrollView {
                VStack(spacing: 24) {
                    stepHeader
                    stepContent
                    timersSection
                }
                .padding()
            }

            Spacer()

            // Navigation controls
            navigationControls
        }
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(
            // Hidden matched geometry elements for smooth transition
            VStack {
                Text(recipe.title)
                    .matchedGeometryEffect(id: "cookModeTitle", in: namespace)
                    .hidden()
                Text("Step \(coordinator.currentStepIndex + 1) of \(coordinator.totalSteps)")
                    .matchedGeometryEffect(id: "cookModeProgress", in: namespace)
                    .hidden()
            }
        )
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Minimize", systemImage: "chevron.down") {
                    coordinator.minimizeToBackground()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Navigate to recipe detail
                    NavigationLink {
                        RecipeDetailView(recipe: recipe, dependencies: dependencies)
                    } label: {
                        Label("View Recipe", systemImage: "book.fill")
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
                    try? await dependencies.cookingHistoryRepository.recordCooked(
                        recipeId: recipe.id,
                        recipeTitle: recipe.title
                    )
                }
            }
        }
    }

    private var stepHeader: some View {
        VStack(spacing: 8) {
            Text("Step \(coordinator.currentStepIndex + 1) of \(coordinator.totalSteps)")
                .font(.headline)
                .foregroundColor(.cauldronOrange)

            if let currentStep = coordinator.currentStep {
                Text(currentStep.displayIndex)
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
        }
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
                    .cornerRadius(16)
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
                                    .cornerRadius(16)
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

    private var navigationControls: some View {
        HStack(spacing: 16) {
            Button {
                coordinator.previousStep()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(coordinator.isFirstStep ? Color.cauldronSecondaryBackground.opacity(0.5) : Color.cauldronSecondaryBackground)
                    .foregroundColor(coordinator.isFirstStep ? .secondary : .primary)
                    .cornerRadius(12)
            }
            .disabled(coordinator.isFirstStep)

            Button {
                if coordinator.isLastStep {
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
                .padding()
                .background(Color.cauldronOrange)
                .foregroundColor(.white)
                .cornerRadius(12)
                .shadow(color: Color.cauldronOrange.opacity(0.3), radius: 4, x: 0, y: 2)
            }
        }
        .padding()
        .background(Color.cauldronBackground)
    }
}

#Preview {
    @Previewable @Namespace var namespace
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
            dependencies: container,
            namespace: namespace
        )
    }
    .dependencies(container)
}
