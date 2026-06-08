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

                        Text("Collections, discovery, and recipe details feel cleaner.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        FeatureRow(
                            symbol: "books.vertical.fill",
                            color: .purple,
                            title: "Richer Collections",
                            detail: "Collections now feel more like cookbooks, with photo headers, custom covers, and clearer saved collection organization."
                        )
                        FeatureRow(
                            symbol: "magnifyingglass",
                            color: .blue,
                            title: "Better Recipe Discovery",
                            detail: "Search, tags, and Explore results have been polished so the right recipes are easier to find."
                        )
                        FeatureRow(
                            symbol: "list.bullet.rectangle",
                            color: .cauldronOrange,
                            title: "Cleaner Recipe Details",
                            detail: "Related recipes, saved recipes, and preview recipes now behave more consistently across your library."
                        )
                        FeatureRow(
                            symbol: "checkmark.seal.fill",
                            color: .green,
                            title: "More Predictable Saving",
                            detail: "Cauldron is better at recognizing recipes and collections you already saved, with fewer confusing duplicates."
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
