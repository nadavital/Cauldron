//
//  SectionHeaderLabel.swift
//  Cauldron
//
//  Reusable section header: a brand-colored icon plus a bold title. Standardizes
//  the `Label(...).font(.title2).bold` pattern repeated across detail screens.
//

import SwiftUI

struct SectionHeaderLabel: View {
    let title: String
    let systemImage: String
    var iconColor: Color = .cauldronOrange

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
            Text(title)
        }
        .font(Theme.Typography.sectionTitle)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
        SectionHeaderLabel(title: "Ingredients", systemImage: "basket")
        SectionHeaderLabel(title: "Instructions", systemImage: "list.number")
        SectionHeaderLabel(title: "Nutrition", systemImage: "chart.bar.fill")
    }
    .padding()
}
