//
//  CookModeViewModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class CookModeViewModel: ObservableObject {
    @Published var currentStepIndex = 0
    @Published var progress: Double = 0.0
    
    let recipe: Recipe
    let dependencies: DependencyContainer
    
    var currentStep: CookStep {
        recipe.steps[currentStepIndex]
    }
    
    var canGoBack: Bool {
        currentStepIndex > 0
    }
    
    var isLastStep: Bool {
        currentStepIndex == recipe.steps.count - 1
    }
    
    init(recipe: Recipe, dependencies: DependencyContainer) {
        self.recipe = recipe
        self.dependencies = dependencies
        updateProgress()
    }
    
    func startSession() async {
        await dependencies.cookSessionManager.startSession(recipe: recipe)
        // Record in cooking history
        try? await dependencies.cookingHistoryRepository.recordCooked(recipeId: recipe.id, recipeTitle: recipe.title)
    }
    
    func endSession() async {
        await dependencies.cookSessionManager.endSession()
    }
    
    func nextStep() async {
        guard !isLastStep else { return }
        
        if let newStep = await dependencies.cookSessionManager.nextStep() {
            currentStepIndex = newStep
            updateProgress()
            
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
    }
    
    func previousStep() async {
        guard canGoBack else { return }
        
        if let newStep = await dependencies.cookSessionManager.previousStep() {
            currentStepIndex = newStep
            updateProgress()
            
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
    }
    
    private func updateProgress() {
        progress = Double(currentStepIndex + 1) / Double(recipe.steps.count)
    }
}
