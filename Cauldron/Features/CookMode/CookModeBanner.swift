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
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 12) {
            // Recipe icon
            recipeIcon
                .frame(width: 36, height: 36)
                .matchedGeometryEffect(id: "cookModeIcon", in: namespace)

            // Recipe info
            VStack(alignment: .leading, spacing: 2) {
                Text(coordinator.currentRecipe?.title ?? "Cooking...")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .matchedGeometryEffect(id: "cookModeTitle", in: namespace)

                Text("Step \(coordinator.currentStepIndex + 1) of \(coordinator.totalSteps)")
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .matchedGeometryEffect(id: "cookModeProgress", in: namespace)
            }

            Spacer(minLength: 8)

            // Timer badge (if timers active)
            if !dependencies.timerManager.activeTimers.isEmpty {
                timerBadge
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 20)
        .matchedGeometryEffect(id: "cookModeBanner", in: namespace, properties: .frame, isSource: true)
        .contentShape(Rectangle()) // Make entire area tappable
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                coordinator.expandToFullScreen()
            }
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

        HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.system(size: 16))

            if let shortest = shortestTimer {
                Text(formatTime(shortest.remainingSeconds))
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

    // MARK: - Helpers

    private func formatTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @Namespace var namespace

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
            }(),
            namespace: namespace
        )
        .frame(maxWidth: .infinity)
    }
    .dependencies(.preview())
}
