//
//  WhatsNewView.swift
//  Cauldron
//
//  One-time splash for new features.
//

import SwiftUI

struct WhatsNewView: View {
    let onClose: () -> Void

    var body: some View {
        ZStack {
            AnimatedMeshGradient()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 20)

                    Image("BrandMarks/CauldronIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .cornerRadius(Theme.Radius.large)

                    VStack(spacing: 8) {
                        Text("What's New")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("A calmer design language, steadier sharing, and cleaner recipe surfaces.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        FeatureRow(
                            symbol: "sparkles",
                            color: .cauldronOrange,
                            title: "Refreshed Design",
                            detail: "Cauldron has a warmer visual system with cleaner navigation, softer surfaces, and more consistent large-screen layouts."
                        )
                        FeatureRow(
                            symbol: "books.vertical.fill",
                            color: .blue,
                            title: "Better Collections",
                            detail: "Saved collections and recipe groups are easier to scan, organize, and revisit across your devices."
                        )
                        FeatureRow(
                            symbol: "list.bullet.rectangle",
                            color: .purple,
                            title: "Cleaner Recipe Details",
                            detail: "Recipe screens have been tightened up so ingredients, steps, related recipes, and source details feel more predictable."
                        )
                        FeatureRow(
                            symbol: "checkmark.seal.fill",
                            color: .green,
                            title: "More Reliable Sharing",
                            detail: "Friend, image, and saved-recipe flows include additional stability fixes for smoother syncing."
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        onClose()
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.cauldronOrange)
                            .cornerRadius(14)
                    }
                    .padding(.top, 8)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct FeatureRow: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundColor(color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    WhatsNewView(onClose: {})
}
