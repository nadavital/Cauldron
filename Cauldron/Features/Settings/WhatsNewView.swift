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

                        Text("Reliability and sharing polish just landed.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        FeatureRow(
                            symbol: "person.3.fill",
                            color: .green,
                            title: "Safer Sharing and Profiles",
                            detail: "Shared recipe and profile links now route more consistently, with better save detection and connection loading."
                        )
                        FeatureRow(
                            symbol: "icloud.and.arrow.up.fill",
                            color: .blue,
                            title: "Stronger Offline Sync",
                            detail: "Recipe changes and deletes are queued more durably so CloudKit interruptions can retry cleanly."
                        )
                        FeatureRow(
                            symbol: "ipad",
                            color: .indigo,
                            title: "Better iPad and Mac Layouts",
                            detail: "Friends, collections, and recipe details are more comfortable on larger screens."
                        )
                        FeatureRow(
                            symbol: "square.and.arrow.up.fill",
                            color: .red,
                            title: "More Reliable Imports",
                            detail: "Share extension, text, and URL imports now follow a more consistent recipe handoff path."
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
