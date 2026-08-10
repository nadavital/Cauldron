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
                VStack(spacing: Theme.Spacing.xl) {
                    Spacer(minLength: Theme.Spacing.lg)

                    Image("BrandMarks/CauldronIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .cornerRadius(Theme.Radius.large)

                    VStack(spacing: 8) {
                        Text("What's New")
                            .font(Theme.Typography.screenTitle)

                        Text("A calmer design, safer imports, and more ways to use your recipes.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    AppCard(style: .resting, padding: Theme.Spacing.lg) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                            FeatureRow(
                                symbol: "sparkles",
                                color: .cauldronOrange,
                                title: "Refined Design",
                                detail: "Cleaner navigation, recipe details, collections, and large-screen layouts now share one warmer visual system."
                            )
                            FeatureRow(
                                symbol: "tray.full.fill",
                                color: .purple,
                                title: "Safer Imports",
                                detail: "Interrupted share-sheet imports are saved first, so you can review or retry them later."
                            )
                            FeatureRow(
                                symbol: "waveform",
                                color: .blue,
                                title: "Siri & Visual Search",
                                detail: "Find recipes, add ingredients, import content, and control Cook Mode with supported Apple Intelligence features."
                            )
                            FeatureRow(
                                symbol: "safari.fill",
                                color: .green,
                                title: "Sharing That Travels",
                                detail: "Public recipes open as complete web pages, while syncing, timers, and grocery updates recover more reliably."
                            )
                        }
                    }

                    PrimaryActionButton("Continue") {
                        onClose()
                    }
                    .padding(.top, Theme.Spacing.xs)
                }
                .padding(Theme.Spacing.xl)
                .frame(maxWidth: .infinity)
                .frame(maxWidth: 640)
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
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundColor(color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
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
