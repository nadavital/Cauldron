//
//  StateViews.swift
//  Cauldron
//
//  Unified loading / empty / error presentation with compatibility wrappers.
//

import SwiftUI

struct AppStateView: View {
    enum Kind {
        case loading
        case empty(systemImage: String)
        case error(systemImage: String = "exclamationmark.triangle")
    }

    private let kind: Kind
    private let title: AppText?
    private let message: AppText?
    private let actionTitle: AppText?
    private let action: (() -> Void)?

    init(
        kind: Kind,
        title: LocalizedStringResource? = nil,
        message: LocalizedStringResource? = nil,
        actionTitle: LocalizedStringResource? = nil,
        action: (() -> Void)? = nil
    ) {
        self.kind = kind
        self.title = title.map(AppText.localized)
        self.message = message.map(AppText.localized)
        self.actionTitle = actionTitle.map(AppText.localized)
        self.action = action
    }

    init(
        kind: Kind,
        titleText: AppText? = nil,
        messageText: AppText? = nil,
        actionText: AppText? = nil,
        action: (() -> Void)? = nil
    ) {
        self.kind = kind
        self.title = titleText
        self.message = messageText
        self.actionTitle = actionText
        self.action = action
    }

    var body: some View {
        Group {
            switch kind {
            case .loading:
                loadingContent
            case .empty(let systemImage):
                unavailableContent(
                    title: title ?? .localized("Nothing Here Yet"),
                    systemImage: systemImage
                )
            case .error(let systemImage):
                unavailableContent(
                    title: title ?? .localized("Something Went Wrong"),
                    systemImage: systemImage
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingContent: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .controlSize(.large)

            if let title {
                title.text
                    .font(.headline)
            }

            if let message {
                message.text
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Theme.Spacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: loadingAccessibilityLabel))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var loadingAccessibilityLabel: String {
        title?.resolvedString ?? message?.resolvedString ?? String(localized: "Loading")
    }

    private func unavailableContent(title: AppText, systemImage: String) -> some View {
        ContentUnavailableView {
            Label {
                title.text
            } icon: {
                Image(systemName: systemImage)
            }
        } description: {
            message?.text
        } actions: {
            if let actionTitle, let action {
                PrimaryActionButton(title: actionTitle, action: action)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Compatibility wrappers

/// Compatibility wrapper for existing dynamic loading messages.
struct LoadingStateView: View {
    var message: String?

    var body: some View {
        AppStateView(
            kind: .loading,
            messageText: message.map(AppText.verbatim)
        )
    }
}

/// Compatibility wrapper for existing dynamic error messages.
struct ErrorStateView: View {
    var title: String = "Something Went Wrong"
    var message: String
    var systemImage: String = "exclamationmark.triangle"
    var retryTitle: String = "Try Again"
    var retry: (() -> Void)?

    var body: some View {
        AppStateView(
            kind: .error(systemImage: systemImage),
            titleText: .verbatim(title),
            messageText: .verbatim(message),
            actionText: retry.map { _ in .verbatim(retryTitle) },
            action: retry
        )
    }
}

/// Compatibility wrapper for existing dynamic empty-state copy.
struct EmptyStateView: View {
    var title: String
    var message: String
    var systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        AppStateView(
            kind: .empty(systemImage: systemImage),
            titleText: .verbatim(title),
            messageText: .verbatim(message),
            actionText: actionTitle.map(AppText.verbatim),
            action: action
        )
    }
}

#Preview("Loading") {
    AppStateView(kind: .loading, message: "Loading recipes…")
}

#Preview("Error") {
    AppStateView(
        kind: .error(),
        title: "Couldn't Reach iCloud",
        message: "Check your connection and try again.",
        actionTitle: "Try Again"
    ) {}
}

#Preview("Empty") {
    AppStateView(
        kind: .empty(systemImage: "book.closed"),
        title: "No Recipes Yet",
        message: "Import or create your first recipe to get started.",
        actionTitle: "Add Recipe"
    ) {}
}
