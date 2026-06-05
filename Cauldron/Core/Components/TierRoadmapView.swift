//
//  TierRoadmapView.swift
//  Cauldron
//
//  Shows tier progress with emphasis on current level and next goal
//

import SwiftUI

/// Tier progress view emphasizing current level and next goal
struct TierRoadmapView: View {
    let currentTier: UserTier
    let recipeCount: Int
    let dependencies: DependencyContainer
    @Environment(\.dismiss) private var dismiss
    @State private var showingImporter = false
    @State private var showingEditor = false
    @State private var showingAIGenerator = false
    @State private var isAIAvailable = false
    @State private var animatedProgress: CGFloat = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                GlassEffectContainer(spacing: 2) {
                    VStack(spacing: 16) {
                        // Combined current + next tier section
                        combinedProgressSection

                        // Add recipe CTA
                        addRecipeCTA

                        // All tiers overview
                        allTiersSection
                    }
                }
                .padding()
            }
            .warmCanvas()
            .navigationTitle("Tier Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingImporter) {
                ImporterView(dependencies: dependencies)
            }
            .sheet(isPresented: $showingEditor) {
                RecipeEditorView(dependencies: dependencies)
            }
            .sheet(isPresented: $showingAIGenerator) {
                AIRecipeGeneratorView(dependencies: dependencies)
            }
            .task {
                isAIAvailable = await dependencies.foundationModelsService.isAvailable
            }
        }
    }

    // MARK: - Combined Progress Section

    private var combinedProgressSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Tier icon with glow
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [currentTier.color.opacity(0.3), currentTier.color.opacity(0.1)],
                                center: .center,
                                startRadius: 15,
                                endRadius: 40
                            )
                        )
                        .frame(width: 64, height: 64)

                    Image(systemName: currentTier.icon)
                        .font(.system(size: 28))
                        .foregroundColor(currentTier.color)
                        .scaleEffect(animatedProgress > 0 || currentTier.nextTier == nil ? 1.0 : 0.7)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1), value: animatedProgress)
                }

                // Tier info
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentTier.displayName)
                        .font(.title3)
                        .fontWeight(.bold)

                    // Search boost badge (inline)
                    if currentTier.searchBoost > 1.0 {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                            Text("+\(Int((currentTier.searchBoost - 1.0) * 100))% search boost")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }

                Spacer()
            }

            // Progress bar and next tier info
            if let nextTier = currentTier.nextTier {
                let recipesNeeded = nextTier.requiredRecipes - recipeCount
                let progress = Double(recipeCount - currentTier.requiredRecipes) / Double(nextTier.requiredRecipes - currentTier.requiredRecipes)

                VStack(spacing: 8) {
                    // Progress bar (animates from empty → current on appear)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(currentTier.color)
                                .frame(width: geo.size.width * max(0.02, animatedProgress), height: 8)
                        }
                    }
                    .frame(height: 8)
                    .onAppear {
                        withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.15)) {
                            animatedProgress = max(0.02, CGFloat(progress))
                        }
                    }

                    // Recipe count and next tier
                    HStack {
                        Text("\(recipeCount)/\(nextTier.requiredRecipes)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        HStack(spacing: 4) {
                            Text("\(recipesNeeded) to")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Image(systemName: nextTier.icon)
                                .font(.caption)
                                .foregroundColor(nextTier.color)
                            Text(nextTier.displayName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(nextTier.color)
                        }
                    }
                }
            } else {
                // Max tier reached
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                        .symbolEffect(.pulse, options: .repeating)
                    Text("Max tier reached! Maximum search visibility boost active.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .glassCard(cornerRadius: 12)
    }

    // MARK: - Add Recipe CTA

    private var addRecipeCTA: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.cauldronOrange)
                Text("Add Recipes")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }

            if isAIAvailable {
                Button {
                    showingAIGenerator = true
                } label: {
                    Label("Generate with AI", systemImage: "apple.intelligence")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cauldronOrange)
            }

            HStack(spacing: 10) {
                Button {
                    showingImporter = true
                } label: {
                    Label("Import", systemImage: "arrow.down.doc")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.cauldronOrange)

                Button {
                    showingEditor = true
                } label: {
                    Label("Create", systemImage: "square.and.pencil")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.cauldronOrange)
            }
        }
        .padding()
        .glassCard(cornerRadius: 12)
    }

    // MARK: - All Tiers Section

    private var allTiersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("All Tiers")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                ForEach(UserTier.allCases, id: \.self) { tier in
                    compactTierRow(tier)
                }
            }
        }
    }

    private func compactTierRow(_ tier: UserTier) -> some View {
        let isCurrentTier = tier == currentTier
        let isUnlocked = recipeCount >= tier.requiredRecipes

        return HStack(spacing: 10) {
            // Tier icon
            ZStack {
                Circle()
                    .fill(tier.color.opacity(isUnlocked ? 0.2 : 0.1))
                    .frame(width: 28, height: 28)

                Image(systemName: tier.icon)
                    .font(.caption)
                    .foregroundColor(isUnlocked ? tier.color : tier.color.opacity(0.4))
            }

            // Tier name with current indicator
            HStack(spacing: 4) {
                Text(tier.displayName)
                    .font(.caption)
                    .fontWeight(isCurrentTier ? .semibold : .regular)
                    .foregroundColor(isUnlocked ? .primary : .secondary)

                if isCurrentTier {
                    Circle()
                        .fill(tier.color)
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()

            // Recipe requirement
            Text("\(tier.requiredRecipes)+ recipes")
                .font(.caption)
                .foregroundColor(.secondary)

            // Search boost (show +0% for apprentice too)
            Text("+\(Int((tier.searchBoost - 1.0) * 100))%")
                .font(.caption)
                .foregroundColor(tier.searchBoost > 1.0 && isUnlocked ? .green : .secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .if(isCurrentTier) { row in
            row.glassEffect(
                .regular.tint(tier.color.opacity(0.35)),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
    }
}

#Preview {
    TierRoadmapView(currentTier: .potionMaker, recipeCount: 12, dependencies: .preview())
}
