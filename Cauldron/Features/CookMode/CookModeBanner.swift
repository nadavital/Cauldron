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
            // Recipe emoji or icon
            recipeIcon
                .frame(width: 32, height: 32)

            // Recipe info
            VStack(alignment: .leading, spacing: 2) {
                Text(coordinator.currentRecipe?.title ?? "Cooking...")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Text("Step \(coordinator.currentStepIndex + 1) of \(coordinator.totalSteps)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Timer badge (if timers active)
            if !dependencies.timerManager.activeTimers.isEmpty {
                timerBadge
            }

            // Chevron indicator
            Image(systemName: "chevron.up")
                .font(.caption)
                .foregroundColor(.secondary)
                .imageScale(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(Color.cauldronOrange.opacity(0.3))
                .frame(height: 2),
            alignment: .top
        )
        .contentShape(Rectangle()) // Make entire area tappable
        .onTapGesture {
            coordinator.expandToFullScreen()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var recipeIcon: some View {
        ZStack {
            Circle()
                .fill(Color.cauldronOrange.opacity(0.2))

            Image(systemName: "flame.fill")
                .font(.callout)
                .foregroundColor(.cauldronOrange)
        }
    }

    @ViewBuilder
    private var timerBadge: some View {
        let activeTimers = dependencies.timerManager.activeTimers
        let shortestTimer = activeTimers.min(by: { $0.remainingSeconds < $1.remainingSeconds })

        HStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.caption)

            if let shortest = shortestTimer {
                Text(formatTime(shortest.remainingSeconds))
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }

            if activeTimers.count > 1 {
                Text("+\(activeTimers.count - 1)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .foregroundColor(.cauldronOrange)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.cauldronOrange.opacity(0.15))
        )
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()

        CookModeBanner(coordinator: {
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
        }())
        .frame(maxWidth: .infinity)
    }
    .dependencies(.preview())
}
