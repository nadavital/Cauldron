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
                VStack(spacing: 24) {
                    Spacer(minLength: 20)

                    Image("BrandMarks/CauldronIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .cornerRadius(16)

                    VStack(spacing: 8) {
                        Text("Welcome to Cauldron")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Your personal recipe collection awaits.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        FeatureRow(
                            symbol: "link",
                            color: .blue,
                            title: "Import Recipes",
                            detail: "Save recipes from any website, YouTube, TikTok, or Instagram with a single tap."
                        )
                        FeatureRow(
                            symbol: "timer",
                            color: .orange,
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
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        onClose()
                    } label: {
                        Text("Get Started")
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
    WelcomeView(onClose: {})
}
