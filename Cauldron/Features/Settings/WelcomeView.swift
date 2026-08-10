//
//  WelcomeView.swift
//  Cauldron
//
//  Welcome splash for brand new users after onboarding.
//

import SwiftUI

struct WelcomeView: View {
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
                        Text("Welcome to Cauldron")
                            .font(Theme.Typography.screenTitle)

                        Text("Your personal recipe collection awaits.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    AppCard(style: .resting, padding: Theme.Spacing.lg) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                            FeatureRow(
                                symbol: "link",
                                color: .blue,
                                title: "Import Recipes",
                                detail: "Save recipes from any website, YouTube, TikTok, or Instagram with a single tap."
                            )
                            FeatureRow(
                                symbol: "timer",
                                color: .cauldronOrange,
                                title: "Cook Mode",
                                detail: "Hands-free cooking with step-by-step instructions and built-in timers."
                            )
                            FeatureRow(
                                symbol: "person.2.fill",
                                color: .pink,
                                title: "Share & Connect",
                                detail: "Share recipes with friends and see what they're cooking."
                            )
                        }
                    }

                    PrimaryActionButton("Get Started") {
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
    WelcomeView(onClose: {})
}
