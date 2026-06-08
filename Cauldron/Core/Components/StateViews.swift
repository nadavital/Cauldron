//
//  StateViews.swift
//  Cauldron
//
//  Reusable loading / error / empty state views so every feature presents
//  async states consistently instead of hand-rolling one-off layouts.
//

import SwiftUI

// MARK: - Loading

/// Centered progress indicator with an optional message.
struct LoadingStateView: View {
    var message: String?

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .controlSize(.large)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message ?? "Loading")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Error

/// Standard error presentation with an optional retry action.
///
/// Uses `ContentUnavailableView` so it matches the system look and gets
/// accessibility for free.
struct ErrorStateView: View {
    var title: String = "Something Went Wrong"
    var message: String
    var systemImage: String = "exclamationmark.triangle"
    var retryTitle: String = "Try Again"
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let retry {
                Button(retryTitle, action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(.cauldronOrange)
            }
        }
    }
}

// MARK: - Empty

/// Standard empty state with an optional call to action.
struct EmptyStateView: View {
    var title: String
    var message: String
    var systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(.cauldronOrange)
            }
        }
    }
}

#Preview("Loading") {
    LoadingStateView(message: "Loading recipes…")
}

#Preview("Error") {
    ErrorStateView(message: "We couldn't reach iCloud. Check your connection and try again.") {}
}

#Preview("Empty") {
    EmptyStateView(
        title: "No Recipes Yet",
        message: "Import or create your first recipe to get started.",
        systemImage: "book.closed",
        actionTitle: "Add Recipe"
    ) {}
}
