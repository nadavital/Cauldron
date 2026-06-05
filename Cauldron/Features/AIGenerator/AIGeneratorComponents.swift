//
//  AIGeneratorComponents.swift
//  Cauldron
//
//  Reusable, self-contained pieces extracted from AIRecipeGeneratorView to keep
//  that file focused on generation flow/state.
//

import SwiftUI

// MARK: - Tag Section

struct RecipeTagSection: View {
    let title: String
    let icon: String
    let tags: [RecipeCategory]
    let onTagTap: (RecipeCategory) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(tags, id: \.self) { tag in
                        Button {
                            onTagTap(tag)
                        } label: {
                            TagView(tag.tagValue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4) // Space for shadow
            }
        }
    }
}

// MARK: - Unavailable Card

/// Shown when Apple Intelligence isn't available on the device.
struct AIUnavailableCard: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundColor(.orange)

            Text("Apple Intelligence Not Available")
                .font(.headline)

            Text("This device doesn't support Apple Intelligence, or it may be disabled in Settings.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .cardStyle()
    }
}

// MARK: - Animated Mesh Gradient

/// Immersive, slowly-drifting warm gradient backdrop for the AI generator.
struct AnimatedMeshGradient: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            Color.cauldronBackground

            GeometryReader { proxy in
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: proxy.size.width * 0.8)
                        .blur(radius: 60)
                        .offset(x: animate ? -50 : 50, y: animate ? -50 : 50)

                    Circle()
                        .fill(Color.yellow.opacity(0.15))
                        .frame(width: proxy.size.width * 0.7)
                        .blur(radius: 60)
                        .offset(x: animate ? 100 : -100, y: animate ? 100 : -50)

                    Circle()
                        .fill(Color.red.opacity(0.1))
                        .frame(width: proxy.size.width * 0.6)
                        .blur(radius: 50)
                        .offset(x: animate ? -30 : 150, y: animate ? 150 : -30)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
    }
}

// MARK: - Press Events

extension View {
    func pressEvents(onPress: @escaping (Bool) -> Void) -> some View {
        self.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onPress(true) }
                .onEnded { _ in onPress(false) }
        )
    }
}
