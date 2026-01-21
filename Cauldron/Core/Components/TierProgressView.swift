//
//  TierProgressView.swift
//  Cauldron
//
//  Progress bar showing advancement towards the next tier
//

import SwiftUI

/// Shows progress towards the next tier with a compact ring indicator
struct TierProgressView: View {
    let currentTier: UserTier
    let recipeCount: Int
    var showViewAllTiers: (() -> Void)? = nil

    private var progress: Double {
        guard let nextTier = currentTier.nextTier else { return 1.0 }
        let currentRequired = currentTier.requiredRecipes
        let nextRequired = nextTier.requiredRecipes
        let range = nextRequired - currentRequired
        let progressValue = recipeCount - currentRequired
        return min(1.0, Double(progressValue) / Double(range))
    }

    private var recipesNeeded: Int? {
        guard let nextTier = currentTier.nextTier else { return nil }
        return nextTier.requiredRecipes - recipeCount
    }

    var body: some View {
        Button {
            showViewAllTiers?()
        } label: {
            HStack(spacing: 12) {
                // Tier icon with progress ring
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                        .frame(width: 44, height: 44)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            currentTier.nextTier?.color ?? currentTier.color,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(-90))

                    Image(systemName: currentTier.icon)
                        .font(.system(size: 18))
                        .foregroundColor(currentTier.color)
                }

                // Tier info
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentTier.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    if let needed = recipesNeeded, let nextTier = currentTier.nextTier {
                        Text("\(needed) recipes to \(nextTier.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Max tier reached!")
                            .font(.caption)
                            .foregroundColor(currentTier.color)
                    }
                }

                Spacer()

                if showViewAllTiers != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color.cauldronSecondaryBackground)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(showViewAllTiers == nil)
    }
}

#Preview {
    VStack(spacing: 20) {
        TierProgressView(
            currentTier: .apprentice,
            recipeCount: 2,
            showViewAllTiers: {}
        )

        TierProgressView(
            currentTier: .potionMaker,
            recipeCount: 10,
            showViewAllTiers: {}
        )

        TierProgressView(
            currentTier: .grandWizard,
            recipeCount: 45,
            showViewAllTiers: {}
        )

        TierProgressView(
            currentTier: .legendarySorcerer,
            recipeCount: 75,
            showViewAllTiers: {}
        )
    }
    .padding()
}
