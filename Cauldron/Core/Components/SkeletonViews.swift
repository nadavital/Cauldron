//
//  SkeletonViews.swift
//  Cauldron
//
//  Layout-matched placeholders for content that has not resolved yet.
//  Skeletons are intentionally separate from image placeholders: once an
//  entity exists, its branded image placeholder remains the right treatment.
//

import SwiftUI

enum SkeletonPresentationPolicy {
    /// Skeletons represent an unresolved first load. Cached content stays on
    /// screen during refreshes, and a resolved empty result uses its empty UI.
    nonisolated static func shouldShow(
        isLoading: Bool,
        hasResolvedOnce: Bool,
        hasContent: Bool
    ) -> Bool {
        isLoading && !hasResolvedOnce && !hasContent
    }
}

enum RecipeCardMetrics {
    static func width(isRegularWidth: Bool) -> CGFloat {
        isRegularWidth ? 252 : 240
    }

    static func imageHeight(isRegularWidth: Bool) -> CGFloat {
        isRegularWidth ? 168 : 160
    }

    static func metadataTagMaxWidth(isRegularWidth: Bool) -> CGFloat {
        isRegularWidth ? 120 : 100
    }
}

private enum SkeletonPalette {
    static let base = Color.secondary.opacity(0.13)
    static let highlight = Color.white.opacity(0.42)
    static let warmHighlight = Color.cauldronOrange.opacity(0.12)
}

/// Drives one shimmer across an entire placeholder composition. Keeping the
/// animation at the group boundary avoids a separate timeline per shape.
struct SkeletonGroup<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var shimmerOffset: CGFloat = -1.2
    @State private var isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

    @ViewBuilder let content: Content

    private var shouldAnimate: Bool {
        !reduceMotion &&
            scenePhase == .active &&
            !isLowPowerModeEnabled
    }

    var body: some View {
        content
            .overlay {
                if shouldAnimate {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [
                                .clear,
                                SkeletonPalette.warmHighlight,
                                SkeletonPalette.highlight,
                                SkeletonPalette.warmHighlight,
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: max(80, proxy.size.width * 0.42))
                        .offset(x: shimmerOffset * proxy.size.width)
                    }
                    .allowsHitTesting(false)
                    .mask(content)
                }
            }
            .onAppear(perform: restartAnimation)
            .onChange(of: shouldAnimate) { _, _ in restartAnimation() }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
    }

    private func restartAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            shimmerOffset = -1.2
        }
        guard shouldAnimate else { return }
        withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
            shimmerOffset = 2.4
        }
    }
}

private struct SkeletonBlock: View {
    let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = Theme.Radius.small) {
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(SkeletonPalette.base)
    }
}

struct RecipeCardSkeleton: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegularWidth: Bool { horizontalSizeClass == .regular }
    private var cardWidth: CGFloat { RecipeCardMetrics.width(isRegularWidth: isRegularWidth) }
    private var imageHeight: CGFloat { RecipeCardMetrics.imageHeight(isRegularWidth: isRegularWidth) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SkeletonBlock(cornerRadius: Theme.Radius.large)
                .frame(width: cardWidth, height: imageHeight)

            SkeletonBlock(cornerRadius: 4)
                .frame(width: cardWidth * 0.74, height: 20)

            HStack(spacing: Theme.Spacing.xxs) {
                SkeletonBlock(cornerRadius: 4)
                    .frame(width: 72, height: 14)
                Spacer()
                SkeletonBlock(cornerRadius: Theme.Radius.pill)
                    .frame(width: 86, height: 20)
            }
            .frame(width: cardWidth, height: 20)
        }
        .frame(width: cardWidth)
    }
}

struct RecipeRowSkeleton: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            SkeletonBlock(cornerRadius: Theme.Radius.card)
                .frame(width: 70, height: 70)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                SkeletonBlock(cornerRadius: 4)
                    .frame(maxWidth: 230)
                    .frame(height: 18)
                HStack(spacing: Theme.Spacing.xs) {
                    SkeletonBlock(cornerRadius: 4)
                        .frame(width: 66, height: 13)
                    SkeletonBlock(cornerRadius: 4)
                        .frame(width: 74, height: 13)
                    Spacer(minLength: Theme.Spacing.xxs)
                    SkeletonBlock(cornerRadius: Theme.Radius.pill)
                        .frame(width: 72, height: 20)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 68)
        .padding(.vertical, Theme.Spacing.xxs)
    }
}

struct VisualRecipeResultRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            SkeletonBlock(cornerRadius: 4)
                .frame(maxWidth: 260)
                .frame(height: 18)
            SkeletonBlock(cornerRadius: 4)
                .frame(width: 88, height: 14)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(.vertical, Theme.Spacing.xxs)
    }
}

struct VisualRecipeResultRowSkeletonList: View {
    var count = 5

    var body: some View {
        SkeletonGroup {
            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(0..<count, id: \.self) { _ in VisualRecipeResultRowSkeleton() }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading visual matches")
    }
}

struct CollectionCardSkeleton: View {
    let preferredWidth: CGFloat?

    init(preferredWidth: CGFloat? = 200) {
        self.preferredWidth = preferredWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SkeletonBlock(cornerRadius: Theme.Radius.card)
                .aspectRatio(1, contentMode: .fit)

            SkeletonBlock(cornerRadius: 4)
                .frame(maxWidth: 150)
                .frame(height: 17)

            SkeletonBlock(cornerRadius: 4)
                .frame(width: 82, height: 13)
        }
        .frame(width: preferredWidth, alignment: .leading)
        .frame(maxWidth: preferredWidth == nil ? .infinity : nil, alignment: .leading)
    }
}

struct UserRowSkeleton: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(SkeletonPalette.base)
                .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                SkeletonBlock(cornerRadius: 4)
                    .frame(maxWidth: 180)
                    .frame(height: 18)
                SkeletonBlock(cornerRadius: 4)
                    .frame(width: 112, height: 14)
            }
            Spacer()
            Circle()
                .fill(SkeletonPalette.base)
                .frame(width: 36, height: 36)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

struct CollectionRowSkeleton: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(SkeletonPalette.base)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                SkeletonBlock(cornerRadius: 4)
                    .frame(maxWidth: 190)
                    .frame(height: 17)
                SkeletonBlock(cornerRadius: 4)
                    .frame(width: 88, height: 13)
            }
            Spacer()
            Circle()
                .fill(SkeletonPalette.base)
                .frame(width: 22, height: 22)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

struct ConnectionAvatarSkeleton: View {
    var body: some View {
        VStack(spacing: 6) {
            Circle()
                .fill(SkeletonPalette.base)
                .frame(width: 60, height: 60)
            SkeletonBlock(cornerRadius: 4)
                .frame(width: 58, height: 12)
        }
        .frame(width: 70)
    }
}

struct RecipeCardSkeletonRail: View {
    var count = 3
    var horizontalPadding: CGFloat = Theme.Spacing.md

    var body: some View {
        ScrollView(.horizontal) {
            SkeletonGroup {
                LazyHStack(spacing: Theme.Spacing.md) {
                    ForEach(0..<count, id: \.self) { _ in RecipeCardSkeleton() }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, Theme.Spacing.xs)
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading recipes")
    }
}

struct CollectionCardSkeletonRail: View {
    var count = 3
    var horizontalPadding: CGFloat = Theme.Spacing.md

    var body: some View {
        ScrollView(.horizontal) {
            SkeletonGroup {
                LazyHStack(spacing: Theme.Spacing.md) {
                    ForEach(0..<count, id: \.self) { _ in CollectionCardSkeleton() }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, Theme.Spacing.xs)
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading collections")
    }
}

struct RecipeRowSkeletonList: View {
    var count = 5

    var body: some View {
        SkeletonGroup {
            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(0..<count, id: \.self) { _ in RecipeRowSkeleton() }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading recipes")
    }
}

struct UserRowSkeletonList: View {
    var count = 5

    var body: some View {
        SkeletonGroup {
            LazyVStack(spacing: Theme.Spacing.xs) {
                ForEach(0..<count, id: \.self) { _ in UserRowSkeleton() }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading people")
    }
}

struct CollectionRowSkeletonList: View {
    var count = 5

    var body: some View {
        SkeletonGroup {
            LazyVStack(spacing: Theme.Spacing.xs) {
                ForEach(0..<count, id: \.self) { _ in CollectionRowSkeleton() }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading collections")
    }
}

struct CollectionCardSkeletonGrid: View {
    let columns: [GridItem]
    var count = 6

    var body: some View {
        SkeletonGroup {
            LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                ForEach(0..<count, id: \.self) { _ in
                    CollectionCardSkeleton(preferredWidth: nil)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading collections")
    }
}

struct RecipeCardSkeletonGrid: View {
    let columns: [GridItem]
    var count = 6

    var body: some View {
        SkeletonGroup {
            LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                ForEach(0..<count, id: \.self) { _ in RecipeCardSkeleton() }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading recipes")
    }
}

struct DashboardSkeletonView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            skeletonSection(title: "Quick & Easy", systemImage: "timer") {
                RecipeCardSkeletonRail()
            }
            skeletonSection(title: "My Collections", systemImage: "folder.fill", showsSeeAll: true) {
                CollectionCardSkeletonRail()
            }
            skeletonSection(title: "All Recipes", systemImage: "fork.knife", showsSeeAll: true) {
                RecipeCardSkeletonRail()
            }
        }
        .padding(.vertical)
    }

    private func skeletonSection<Content: View>(
        title: String,
        systemImage: String,
        iconColor: Color = .cauldronOrange,
        showsSeeAll: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                SectionHeaderLabel(title: title, systemImage: systemImage, iconColor: iconColor)
                if showsSeeAll {
                    if horizontalSizeClass != .regular {
                        Spacer()
                    }
                    HStack(spacing: Theme.Spacing.xxs) {
                        Text("See All")
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.cauldronOrange)
                }
            }
                .padding(.horizontal, Theme.Spacing.md)
            content()
        }
    }
}

#Preview("Skeletons") {
    ScrollView {
        DashboardSkeletonView()
        SkeletonGroup {
            VStack(spacing: Theme.Spacing.sm) {
                RecipeRowSkeleton()
                UserRowSkeleton()
            }
            .padding()
        }
    }
    .warmCanvas()
}
