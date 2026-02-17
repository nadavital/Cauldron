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

                        Text("Major upgrades just dropped!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        FeatureRow(
                            symbol: "wand.and.stars.inverse",
                            color: .orange,
                            title: "Model-Based Recipe Parser",
                            detail: "Imports now use a model-backed parser for more reliable ingredient, step, and metadata extraction."
                        )
                        FeatureRow(
                            symbol: "person.3.fill",
                            color: .green,
                            title: "Invite Links and Better Referrals",
                            detail: "Invite behavior was improved with more reliable link handling and smoother referral onboarding."
                        )
                        FeatureRow(
                            symbol: "ipad",
                            color: .indigo,
                            title: "New iPad and Mac Apps",
                            detail: "The brand new Cauldron iPad and Mac app is out, with layout and navigation optimizations across core recipe and collection screens."
                        )
                        FeatureRow(
                            symbol: "square.and.arrow.up.fill",
                            color: .red,
                            title: "New Share Extension",
                            detail: "Click share then Cauldron while browsing the web or any app to send your recipes right to Cauldron!"
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
