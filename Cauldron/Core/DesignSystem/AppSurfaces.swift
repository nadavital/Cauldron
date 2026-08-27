//
//  AppSurfaces.swift
//  Cauldron
//
//  Explicit surface primitives for the app's warm editorial design language.
//

import SwiftUI

/// The three supported surface roles. Choosing a role is intentionally more
/// explicit than applying an ad-hoc background, radius, and shadow at each
/// call site.
enum AppSurfaceStyle: Sendable {
    /// A quiet card on the warm canvas: subtle separator, no elevation.
    case resting
    /// A raised card or popover-like surface with stronger elevation.
    case elevated
    /// Native Liquid Glass. Group neighboring glass surfaces in a
    /// `GlassEffectContainer` at the composition boundary.
    case glass

    var cornerRadius: CGFloat {
        switch self {
        case .resting:
            Theme.Radius.card
        case .elevated, .glass:
            Theme.Radius.large
        }
    }
}

/// Stable content sizes for modal workspaces when Cauldron is hosted on macOS.
/// SwiftUI's automatic Catalyst sheet size is frequently too narrow for the
/// app's iPad-first forms, so callers choose the amount of working room their
/// content needs while iPhone and iPad keep their native sheet behavior.
enum AppSheetSize: Sendable {
    case compact
    case standard
    case large

    var width: CGFloat {
        switch self {
        case .compact: 520
        case .standard: 680
        case .large: 860
        }
    }

    var height: CGFloat {
        switch self {
        case .compact: 480
        case .standard: 620
        case .large: 720
        }
    }
}

private struct AppSheetSizingModifier: ViewModifier {
    let size: AppSheetSize

    @ViewBuilder
    func body(content: Content) -> some View {
        if RuntimeEnvironment.prefersDesktopWorkspace {
            content
                .frame(
                    minWidth: size.width,
                    idealWidth: size.width,
                    minHeight: size.height,
                    idealHeight: size.height
                )
                .presentationSizing(.fitted)
        } else {
            content
        }
    }
}

/// Applies one of Cauldron's supported surfaces without imposing content
/// padding. Use `AppCard` for the common padded-card composition.
struct AppSurface<Content: View>: View {
    let style: AppSurfaceStyle
    let cornerRadius: CGFloat?
    @ViewBuilder let content: Content

    init(
        style: AppSurfaceStyle = .resting,
        cornerRadius: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    private var resolvedCornerRadius: CGFloat {
        cornerRadius ?? style.cornerRadius
    }

    var body: some View {
        switch style {
        case .resting:
            content
                .background(Color.appSurface, in: surfaceShape)
                .overlay(surfaceShape.stroke(Color.appSeparator, lineWidth: 1))

        case .elevated:
            content
                .background(Color.appSurfaceElevated, in: surfaceShape)
                .overlay(surfaceShape.stroke(Color.appSeparator.opacity(0.7), lineWidth: 1))
                .shadow(Theme.Shadow.elevated)

        case .glass:
            content
                .glassEffect(.regular, in: surfaceShape)
        }
    }

    private var surfaceShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
    }
}

/// Standard padded card. This is the preferred replacement for assembling
/// `.padding`, `.background`, `.cornerRadius`, and `.shadow` independently.
struct AppCard<Content: View>: View {
    let style: AppSurfaceStyle
    let padding: CGFloat
    let cornerRadius: CGFloat?
    let alignment: Alignment
    @ViewBuilder let content: Content

    init(
        style: AppSurfaceStyle = .resting,
        padding: CGFloat = Theme.Spacing.md,
        cornerRadius: CGFloat? = nil,
        alignment: Alignment = .leading,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        AppSurface(style: style, cornerRadius: cornerRadius) {
            content
                .frame(maxWidth: .infinity, alignment: alignment)
                .padding(padding)
        }
    }
}

extension View {
    /// Surface-only convenience for content that already owns its padding.
    func appSurface(
        _ style: AppSurfaceStyle = .resting,
        cornerRadius: CGFloat? = nil
    ) -> some View {
        AppSurface(style: style, cornerRadius: cornerRadius) { self }
    }

    /// Gives Catalyst and iOS-on-Mac sheets enough room to remain legible.
    /// Other platforms continue to use the native presentation dimensions.
    func appSheetSizing(_ size: AppSheetSize = .standard) -> some View {
        modifier(AppSheetSizingModifier(size: size))
    }
}
