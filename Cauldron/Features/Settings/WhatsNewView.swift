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

                        Text("Imports recover, Cook Mode travels with you, and your library is easier to trust.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        FeatureRow(
                            symbol: "tray.full.fill",
                            color: .purple,
                            title: "Import Inbox",
                            detail: "Shared recipes are saved to a durable inbox first, so an interrupted import can be reviewed or retried later."
                        )
                        FeatureRow(
                            symbol: "magnifyingglass",
                            color: .blue,
                            title: "Ingredient Search",
                            detail: "Require ingredients you have, exclude ingredients you avoid, and sort results by time, name, or recency."
                        )
                        FeatureRow(
                            symbol: "flame.fill",
                            color: .cauldronOrange,
                            title: "Cook Mode Everywhere",
                            detail: "Resume and navigate cooking from Siri, Shortcuts, widgets, and Live Activities—even after Cauldron relaunches."
                        )
                        FeatureRow(
                            symbol: "checkmark.seal.fill",
                            color: .green,
                            title: "More Reliable by Design",
                            detail: "Persistent timers, clearer sync health, safer grocery merging, private diagnostics, and Apple Intelligence fallback make everyday use steadier."
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
