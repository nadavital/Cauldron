//
//  CookModeBanner.swift
//  Cauldron
//
//  Created by Claude on 10/31/25.
//

import SwiftUI

/// Compact banner view shown above tab bar when cook mode is active
struct CookModeBanner: View {
    @Environment(\.dependencies) private var dependencies
    let coordinator: CookModeCoordinator

    var body: some View {
        HStack(spacing: 12) {
            // Recipe icon
            recipeIcon
                .frame(width: 36, height: 36)

            // Recipe info
            VStack(alignment: .leading, spacing: 2) {
                Text(coordinator.currentRecipe?.title ?? "Cooking...")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text("Step \(coordinator.currentStepIndex + 1) of \(coordinator.totalSteps)")
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            // Timer badge (if timers active)
            if !dependencies.timerManager.activeTimers.isEmpty {
                timerBadge
            }

            // End session button
            Button(action: {
                coordinator.endSession()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 20)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var recipeIcon: some View {
        Image("BrandMarks/CauldronIconTiny")
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    @ViewBuilder
    private var timerBadge: some View {
        let activeTimers = dependencies.timerManager.activeTimers
        // Get shortest running timer with valid future end date
        let shortestTimer = activeTimers
            .filter { !$0.isPaused && $0.endDate > Date() }
            .min(by: { $0.endDate < $1.endDate })

        HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.system(size: 16))

            if let shortest = shortestTimer {
                Text(shortest.endDate, style: .timer)
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }

            if activeTimers.count > 1 {
                Text("+\(activeTimers.count - 1)")
                    .font(.caption2)
            }
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()

        CookModeBanner(
            coordinator: {
                let container = DependencyContainer.preview()
                let coordinator = CookModeCoordinator(dependencies: container)

                // Simulate active session
                let recipe = Recipe(
                    title: "Spaghetti Carbonara",
                    ingredients: [],
                    steps: [
                        CookStep(index: 0, text: "Boil pasta"),
                        CookStep(index: 1, text: "Cook bacon"),
                        CookStep(index: 2, text: "Mix eggs"),
                        CookStep(index: 3, text: "Combine"),
                    ]
                )

                Task { @MainActor in
                    await coordinator.startCooking(recipe)
                    coordinator.minimizeToBackground()
                }

                return coordinator
            }()
        )
        .frame(maxWidth: .infinity)
    }
    .dependencies(.preview())
}
