//
//  AppActionButtons.swift
//  Cauldron
//
//  Consistent action controls with localization, loading, disabled, and hit-
//  target behavior built in.
//

import SwiftUI

enum AppText {
    case localized(LocalizedStringResource)
    case verbatim(String)

    var text: Text {
        switch self {
        case .localized(let resource):
            Text(resource)
        case .verbatim(let value):
            Text(verbatim: value)
        }
    }

    var resolvedString: String {
        switch self {
        case .localized(let resource):
            String(localized: resource)
        case .verbatim(let value):
            value
        }
    }
}

enum AppActionAvailabilityPolicy {
    nonisolated static func isDisabled(isBusy: Bool, isExplicitlyDisabled: Bool) -> Bool {
        isBusy || isExplicitlyDisabled
    }
}

/// Full-width primary action with a stable label while work is in progress.
struct PrimaryActionButton: View {
    private let title: AppText
    private let systemImage: String?
    private let role: ButtonRole?
    private let tint: Color
    private let isBusy: Bool
    private let isExplicitlyDisabled: Bool
    private let action: () -> Void

    init(
        _ title: LocalizedStringResource,
        systemImage: String? = nil,
        role: ButtonRole? = nil,
        tint: Color = .cauldronOrange,
        isBusy: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = .localized(title)
        self.systemImage = systemImage
        self.role = role
        self.tint = tint
        self.isBusy = isBusy
        self.isExplicitlyDisabled = isDisabled
        self.action = action
    }

    init(
        verbatimTitle: String,
        systemImage: String? = nil,
        role: ButtonRole? = nil,
        tint: Color = .cauldronOrange,
        isBusy: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = .verbatim(verbatimTitle)
        self.systemImage = systemImage
        self.role = role
        self.tint = tint
        self.isBusy = isBusy
        self.isExplicitlyDisabled = isDisabled
        self.action = action
    }

    init(
        title: AppText,
        systemImage: String? = nil,
        role: ButtonRole? = nil,
        tint: Color = .cauldronOrange,
        isBusy: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.tint = tint
        self.isBusy = isBusy
        self.isExplicitlyDisabled = isDisabled
        self.action = action
    }

    private var isDisabled: Bool {
        AppActionAvailabilityPolicy.isDisabled(
            isBusy: isBusy,
            isExplicitlyDisabled: isExplicitlyDisabled
        )
    }

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                        .accessibilityHidden(true)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }

                title.text
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.HitTarget.minimum)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(tint)
        .disabled(isDisabled)
        .accessibilityLabel(Text(verbatim: title.resolvedString))
        .accessibilityValue(isBusy ? Text("In progress") : Text("") )
    }
}

/// Primary action that owns its in-flight state and prevents duplicate taps.
struct AsyncActionButton: View {
    private let title: LocalizedStringResource
    private let systemImage: String?
    private let role: ButtonRole?
    private let tint: Color
    private let isExplicitlyDisabled: Bool
    private let action: () async -> Void

    @State private var isBusy = false

    init(
        _ title: LocalizedStringResource,
        systemImage: String? = nil,
        role: ButtonRole? = nil,
        tint: Color = .cauldronOrange,
        isDisabled: Bool = false,
        action: @escaping () async -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.tint = tint
        self.isExplicitlyDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        PrimaryActionButton(
            title,
            systemImage: systemImage,
            role: role,
            tint: tint,
            isBusy: isBusy,
            isDisabled: isExplicitlyDisabled
        ) {
            guard !isBusy else { return }
            isBusy = true
            Task {
                await action()
                isBusy = false
            }
        }
    }
}

enum IconActionButtonStyle: Sendable {
    case toolbar
    case tinted
    case glass
}

/// Compact icon control whose interactive region always meets the app's
/// 44-point minimum, even when the visible glyph remains small.
struct IconActionButton: View {
    private let title: LocalizedStringResource
    private let systemImage: String
    private let role: ButtonRole?
    private let style: IconActionButtonStyle
    private let tint: Color
    private let isDisabled: Bool
    private let action: () -> Void

    init(
        _ title: LocalizedStringResource,
        systemImage: String,
        role: ButtonRole? = nil,
        style: IconActionButtonStyle = .toolbar,
        tint: Color = .cauldronOrange,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.style = style
        self.tint = tint
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: Theme.IconSize.small, weight: .semibold))
                .frame(
                    minWidth: Theme.HitTarget.minimum,
                    minHeight: Theme.HitTarget.minimum
                )
                .contentShape(Rectangle())
                .foregroundStyle(foregroundStyle)
                .background { background }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(Text(title))
    }

    private var foregroundStyle: Color {
        switch style {
        case .toolbar:
            .primary
        case .tinted, .glass:
            tint
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .toolbar:
            Color.clear
        case .tinted:
            Circle().fill(tint.opacity(0.12))
        case .glass:
            Circle().glassEffect(.regular, in: Circle())
        }
    }
}
