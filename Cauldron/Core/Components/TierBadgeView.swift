//
//  TierBadgeView.swift
//  Cauldron
//
//  Reusable tier badge component with multiple display styles
//

import SwiftUI

/// Display style for the tier badge
enum TierBadgeStyle {
    case compact    // Icon only (for recipe cards)
    case standard   // Icon + tier name (for profiles)
    case expanded   // Icon + name + boost info (for roadmap)
}

/// Reusable tier badge view that displays a user's tier
struct TierBadgeView: View {
    let tier: UserTier
    var style: TierBadgeStyle = .standard

    var body: some View {
        switch style {
        case .compact:
            compactBadge
        case .standard:
            standardBadge
        case .expanded:
            expandedBadge
        }
    }

    // MARK: - Compact Style (Icon only)

    private var compactBadge: some View {
        Image(systemName: tier.icon)
            .font(.caption2)
            .foregroundColor(tier.color)
    }

    // MARK: - Standard Style (Icon + name)

    private var standardBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: tier.icon)
                .font(.caption)
            Text(tier.displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(tier.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tier.color.opacity(0.15))
        .cornerRadius(8)
    }

    // MARK: - Expanded Style (Icon + name + boost)

    private var expandedBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: tier.icon)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(tier.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if tier.searchBoost > 1.0 {
                    Text("\(Int((tier.searchBoost - 1.0) * 100))% search boost")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .foregroundColor(tier.color)
    }
}

// MARK: - Convenience Initializers

extension TierBadgeView {
    /// Create a badge from a recipe count
    init(recipeCount: Int, style: TierBadgeStyle = .standard) {
        self.tier = UserTier.tier(for: recipeCount)
        self.style = style
    }
}

#Preview("Compact") {
    HStack(spacing: 16) {
        ForEach(UserTier.allCases, id: \.self) { tier in
            TierBadgeView(tier: tier, style: .compact)
        }
    }
    .padding()
}

#Preview("Standard") {
    VStack(spacing: 12) {
        ForEach(UserTier.allCases, id: \.self) { tier in
            TierBadgeView(tier: tier, style: .standard)
        }
    }
    .padding()
}

#Preview("Expanded") {
    VStack(alignment: .leading, spacing: 16) {
        ForEach(UserTier.allCases, id: \.self) { tier in
            TierBadgeView(tier: tier, style: .expanded)
        }
    }
    .padding()
}
