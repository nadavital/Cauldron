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
                        .cornerRadius(16)

                    VStack(spacing: 8) {
                        Text("What's New")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Fresh upgrades for your kitchen ritual.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        FeatureRow(
                            symbol: "app.badge.fill",
                            color: .orange,
                            title: "New App Icons",
                            detail: "Invite friends to unlock new looks, then pick your favorite in Profile."
                        )
                        FeatureRow(
                            symbol: "tag.fill",
                            color: .pink,
                            title: "Referral Codes",
                            detail: "Share your code to connect instantly and earn rewards together."
                        )
                        FeatureRow(
                            symbol: "crown.fill",
                            color: .yellow,
                            title: "Cauldron Tiers",
                            detail: "Cook more recipes to level up and unlock perks over time."
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
