//
//  RecipeImagePlaceholder.swift
//  Cauldron
//
//  Branded fallback shown when a recipe has no image. A warm Cauldron gradient
//  with the brand mark — turns an empty gray rectangle into an on-brand,
//  intentional-feeling tile (a small "alchemy" delight moment).
//

import SwiftUI

struct RecipeImagePlaceholder: View {
    var iconSize: CGFloat
    var showText: Bool = false

    var body: some View {
        ZStack {
            Color.cauldronWarmGradient

            VStack(spacing: Theme.Spacing.xs) {
                Image("BrandMarks/CauldronIconSmall")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

                if showText {
                    Text("No Image")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(Theme.Spacing.sm)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        RecipeImagePlaceholder(iconSize: 40, showText: true)
            .frame(width: 240, height: 160)
            .cornerRadius(Theme.Radius.large)
        RecipeImagePlaceholder(iconSize: 64)
            .frame(height: 200)
    }
    .padding()
}
