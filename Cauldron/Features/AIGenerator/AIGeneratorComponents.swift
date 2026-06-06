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

// MARK: - Streaming Recipe Preview

/// Renders the partially-generated recipe (title, ingredients, steps) as it
/// streams in. Pure function of the partial result — no generator state.
struct AIRecipePreview: View {
    let partial: GeneratedRecipe.PartiallyGenerated

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let title = partial.title {
                VStack(alignment: .leading, spacing: 16) {
                    Text(title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 20) {
                        if let minutes = partial.totalMinutes {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                    .foregroundColor(.cauldronOrange)
                                Text("\(minutes) min")
                            }
                        }

                        if let yields = partial.yields, !yields.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "person.2")
                                    .foregroundColor(.cauldronOrange)
                                Text(yields)
                            }
                        }
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let ingredients = partial.ingredients, !ingredients.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Ingredients", systemImage: "basket")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(ingredients.enumerated()), id: \.offset) { _, ingredient in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundColor(.cauldronOrange)
                                    .padding(.top, 8)

                                Text(Self.formatIngredient(ingredient))
                                    .font(.body)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 4)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
            }

            if let steps = partial.steps, !steps.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Instructions", systemImage: "list.number")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 16) {
                                Text("\(index + 1)")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [.cauldronOrange, .orange],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    )
                                    .shadow(color: .orange.opacity(0.3), radius: 4, x: 0, y: 2)

                                Text(step.text?.decodingHTMLEntities ?? "")
                                    .font(.body)
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
            }
        }
    }

    /// Format an ingredient for display (matching RecipeDetailView style).
    static func formatIngredient(_ ingredient: GeneratedIngredient.PartiallyGenerated) -> String {
        var parts: [String] = []

        if let value = ingredient.quantityValue, let unit = ingredient.quantityUnit {
            let formattedValue = value.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", value)
                : String(format: "%.1f", value)
            parts.append("\(formattedValue) \(unit)")
        }

        if let name = ingredient.name {
            parts.append(name)
        }

        if let note = ingredient.note {
            parts.append("(\(note))")
        }

        return parts.joined(separator: " ")
    }
}

// MARK: - Error Card

struct AIErrorCard: View {
    let error: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundColor(.red)
                .symbolEffect(.pulse)

            VStack(alignment: .leading, spacing: 4) {
                Text("Generation Failed")
                    .font(.headline)
                    .foregroundColor(.red)

                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.red.opacity(0.8))
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Color.red.opacity(0.08))
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.red.opacity(0.2), lineWidth: 1)
        )
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
