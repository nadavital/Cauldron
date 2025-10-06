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
    let dependencies: DependencyContainer
    
    @StateObject private var viewModel: CookModeViewModel
    @ObservedObject private var timerManager: TimerManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingAllTimers = false
    
    init(recipe: Recipe, dependencies: DependencyContainer) {
        self.recipe = recipe
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: CookModeViewModel(recipe: recipe, dependencies: dependencies))
        _timerManager = ObservedObject(wrappedValue: dependencies.timerManager)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                ProgressView(value: viewModel.progress)
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Exit", systemImage: "xmark") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAllTimers = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "timer")
                            
                            if !timerManager.activeTimers.isEmpty {
                                Circle()
                                    .fill(Color.red)
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
            .onAppear {
                Task {
                    await viewModel.startSession()
                }
            }
            .onDisappear {
                Task {
                    await viewModel.endSession()
                }
            }
        }
    }
    
    private var stepHeader: some View {
        VStack(spacing: 8) {
            Text("Step \(viewModel.currentStepIndex + 1) of \(recipe.steps.count)")
                .font(.headline)
                .foregroundColor(.cauldronOrange)
            
            Text(viewModel.currentStep.displayIndex)
                .font(.largeTitle)
                .fontWeight(.bold)
        }
    }
    
    private var stepContent: some View {
        Text(viewModel.currentStep.text)
            .font(.title3)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Color.cauldronSecondaryBackground)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    @ViewBuilder
    private var timersSection: some View {
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
            if !viewModel.currentStep.timers.isEmpty {
                let stepActiveTimers = timerManager.activeTimers.filter { $0.stepIndex == viewModel.currentStepIndex }
                
                VStack(alignment: .leading, spacing: 8) {
                    if !timerManager.activeTimers.isEmpty {
                        Text("Step Timers")
                            .font(.headline)
                            .padding(.top, 8)
                    }
                    
                    ForEach(viewModel.currentStep.timers) { timerSpec in
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
                                    stepIndex: viewModel.currentStepIndex,
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
                stepIndex: viewModel.currentStepIndex
            )
        }
    }
    
    private var navigationControls: some View {
        HStack(spacing: 16) {
            Button {
                Task {
                    await viewModel.previousStep()
                }
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.canGoBack ? Color.cauldronSecondaryBackground : Color.cauldronSecondaryBackground.opacity(0.5))
                    .foregroundColor(viewModel.canGoBack ? .primary : .secondary)
                    .cornerRadius(12)
            }
            .disabled(!viewModel.canGoBack)
            
            Button {
                Task {
                    if viewModel.isLastStep {
                        dismiss()
                    } else {
                        await viewModel.nextStep()
                    }
                }
            } label: {
                HStack {
                    Text(viewModel.isLastStep ? "Done" : "Next")
                        .fontWeight(.semibold)
                    Image(systemName: viewModel.isLastStep ? "checkmark" : "chevron.right")
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
    CookModeView(
        recipe: Recipe(
            title: "Sample Recipe",
            ingredients: [],
            steps: [
                CookStep(index: 0, text: "Preheat oven to 350°F", timers: []),
                CookStep(index: 1, text: "Bake for 30 minutes", timers: [.minutes(30, label: "Bake")])
            ]
        ),
        dependencies: .preview()
    )
}
