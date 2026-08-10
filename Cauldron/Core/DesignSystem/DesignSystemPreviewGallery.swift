//
//  DesignSystemPreviewGallery.swift
//  Cauldron
//

import SwiftUI

struct DesignSystemPreviewGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                SectionHeaderLabel(title: "Surfaces", systemImage: "square.stack.3d.up")

                AppCard(style: .resting) {
                    galleryCardCopy(title: "Resting", detail: "Quiet content on the warm canvas")
                }

                AppCard(style: .elevated) {
                    galleryCardCopy(title: "Elevated", detail: "Raised transient or featured content")
                }

                GlassEffectContainer(spacing: Theme.Spacing.xs) {
                    AppCard(style: .glass) {
                        galleryCardCopy(title: "Glass", detail: "Interactive or layered native material")
                    }
                }

                SectionHeaderLabel(title: "Actions", systemImage: "hand.tap")

                PrimaryActionButton("Save Recipe", systemImage: "checkmark") {}
                PrimaryActionButton("Saving Recipe", isBusy: true) {}

                HStack(spacing: Theme.Spacing.sm) {
                    IconActionButton("Add", systemImage: "plus", style: .tinted) {}
                    IconActionButton("Favorite", systemImage: "star", style: .glass) {}
                    IconActionButton(
                        "Delete",
                        systemImage: "trash",
                        role: .destructive,
                        style: .tinted,
                        tint: .red
                    ) {}
                }

                SectionHeaderLabel(title: "States", systemImage: "hourglass")

                AppStateView(
                    kind: .empty(systemImage: "book.closed"),
                    title: "No Recipes Yet",
                    message: "Import or create your first recipe to get started.",
                    actionTitle: "Add Recipe"
                ) {}
                .frame(height: 260)
            }
            .padding(Theme.Spacing.md)
        }
        .warmCanvas()
    }

    private func galleryCardCopy(title: LocalizedStringResource, detail: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.cardTitle)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Design System") {
    DesignSystemPreviewGallery()
}
