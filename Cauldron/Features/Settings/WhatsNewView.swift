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

                        Text("Imports recover, recipes travel farther, and Siri understands more of your kitchen.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    AppCard(style: .resting, padding: Theme.Spacing.lg) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                            FeatureRow(
                                symbol: "tray.full.fill",
                                color: .purple,
                                title: "Import Inbox",
                                detail: "Shared recipes are saved to a durable inbox first, so an interrupted import can be reviewed or retried later."
                            )
                            FeatureRow(
                                symbol: "sparkles",
                                color: .blue,
                                title: "Smarter Siri & Visual Search",
                                detail: "Find and open your recipes, add ingredients, import links or text, control Cook Mode, and discover visual matches with supported Apple Intelligence features."
                            )
                            FeatureRow(
                                symbol: "flame.fill",
                                color: .cauldronOrange,
                                title: "Cook Mode Everywhere",
                                detail: "Resume and navigate cooking from Siri, Shortcuts, widgets, and Live Activities—even after Cauldron relaunches."
                            )
                            FeatureRow(
                                symbol: "safari.fill",
                                color: .cauldronOrange,
                                title: "Recipes on the Web",
                                detail: "Share your profile or a public recipe with anyone. Recipe links now open as complete, readable pages with an easy path back to Cauldron."
                            )
                            FeatureRow(
                                symbol: "checkmark.seal.fill",
                                color: .green,
                                title: "More Reliable by Design",
                                detail: "Persistent timers, clearer sync health, safer grocery merging, private diagnostics, and Apple Intelligence fallback make everyday use steadier."
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
