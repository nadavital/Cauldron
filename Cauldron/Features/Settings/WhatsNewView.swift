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
            Color.appBackground.ignoresSafeArea()

            RadialGradient(
                colors: [Color.cauldronOrange.opacity(0.1), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 360
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image("BrandMarks/CauldronIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                        Text("Cauldron")
                            .font(.headline)
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("A more polished Cauldron")
                            .font(Theme.Typography.screenTitle)
                        Text("The everyday parts of Cauldron are now calmer, faster, and more dependable.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        FeatureRow(
                            symbol: "sparkles",
                            title: "A calmer Cauldron",
                            detail: "Cleaner navigation and recipe views across iPhone, iPad, and Mac."
                        )
                        Divider().padding(.leading, 44)
                        FeatureRow(
                            symbol: "tray.full.fill",
                            title: "Imports you can trust",
                            detail: "Shared recipes survive interruptions and remain ready to review."
                        )
                        Divider().padding(.leading, 44)
                        FeatureRow(
                            symbol: "waveform",
                            title: "Your recipes, everywhere",
                            detail: "Use Siri, visual search, Cook Mode, and complete public recipe links."
                        )
                    }
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.xxl)
                .padding(.bottom, Theme.Spacing.xxl)
                .frame(maxWidth: .infinity)
                .frame(maxWidth: 560)
            }
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryActionButton("Continue") { onClose() }
                .frame(maxWidth: 520)
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.md)
                .background(Color.appBackground)
        }
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: symbol)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.cauldronOrange)
                .frame(width: 28, height: 28)
                .background(Color.cauldronOrange.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, Theme.Spacing.md)
    }
}

#Preview {
    WhatsNewView(onClose: {})
}
