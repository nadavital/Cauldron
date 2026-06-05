//
//  DesignTokens.swift
//  Cauldron
//
//  Centralized design tokens for spacing, corner radius, icon sizes,
//  animation, and shadow. Replaces magic numbers scattered across views
//  so the look stays consistent and is easy to tune in one place.
//

import SwiftUI

/// Design system namespace. Use the nested tokens instead of hardcoded values:
/// `Theme.Spacing.md`, `Theme.Radius.card`, `Theme.Animation.spring`, etc.
enum Theme {

    // MARK: - Spacing

    /// 4-pt based spacing scale. Use these instead of literal paddings.
    enum Spacing {
        /// 4 pt
        static let xxs: CGFloat = 4
        /// 8 pt
        static let xs: CGFloat = 8
        /// 12 pt
        static let sm: CGFloat = 12
        /// 16 pt — default horizontal screen inset
        static let md: CGFloat = 16
        /// 20 pt
        static let lg: CGFloat = 20
        /// 24 pt — default vertical section spacing
        static let xl: CGFloat = 24
        /// 32 pt
        static let xxl: CGFloat = 32
        /// 48 pt
        static let xxxl: CGFloat = 48
    }

    // MARK: - Corner Radius

    enum Radius {
        /// 8 pt — small chips/tags
        static let small: CGFloat = 8
        /// 12 pt — standard cards (matches existing `cardStyle()`)
        static let card: CGFloat = 12
        /// 16 pt — large surfaces / sheets
        static let large: CGFloat = 16
        /// 20 pt — hero/feature surfaces
        static let xLarge: CGFloat = 20
        /// Fully rounded (capsule-like) when applied to small controls
        static let pill: CGFloat = 999
    }

    // MARK: - Icon Sizes

    /// Base icon point sizes. Pair with `@ScaledMetric` in views that need
    /// the icon to grow with Dynamic Type.
    enum IconSize {
        static let small: CGFloat = 16
        static let medium: CGFloat = 22
        static let large: CGFloat = 32
        static let xLarge: CGFloat = 44
    }

    // MARK: - Hit Targets

    enum HitTarget {
        /// Apple HIG minimum tappable size.
        static let minimum: CGFloat = 44
    }

    // MARK: - Shadow

    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    enum Shadow {
        /// Subtle card shadow (matches existing `cardStyle()`).
        static let card = ShadowStyle(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        /// Slightly stronger elevation for floating elements.
        static let elevated = ShadowStyle(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
    }

    // MARK: - Typography

    /// Semantic, Dynamic-Type-friendly text styles. These build on the system
    /// text styles (so they scale automatically) while standardizing the few
    /// places the app wants a rounded, branded feel.
    /// Editorial voice: a serif (system New York) for titles and section
    /// headers gives recipes a warm, cookbook feel, while SF stays for body and
    /// UI chrome. All styles build on system text styles so Dynamic Type works.
    enum Typography {
        /// Large screen / hero title (serif).
        static let screenTitle = SwiftUI.Font.system(.largeTitle, design: .serif).weight(.bold)
        /// Hero recipe title on the detail screen (serif).
        static let recipeTitle = SwiftUI.Font.system(.title, design: .serif).weight(.semibold)
        /// Section header within a screen (serif — ties screens together).
        static let sectionTitle = SwiftUI.Font.system(.title2, design: .serif).weight(.bold)
        /// Recipe card / row title (serif, smaller).
        static let cardTitle = SwiftUI.Font.system(.headline, design: .serif)
        /// Secondary metadata (time, counts, captions).
        static let metadata = SwiftUI.Font.caption
        /// Numeric, rounded display (timers, counts) — pair with `.monospacedDigit()`.
        static let numericDisplay = SwiftUI.Font.system(.largeTitle, design: .rounded).weight(.bold)
    }

    // MARK: - Animation

    enum Animation {
        /// Standard spring for most state transitions.
        static let spring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.8)
        /// Snappier spring for small, frequent interactions (toggles, taps).
        static let snappy = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.85)
        /// Gentle ease for fades / appearance.
        static let easeFade = SwiftUI.Animation.easeOut(duration: 0.3)
    }
}

// MARK: - View Conveniences

extension View {
    /// Apply a design-system shadow style.
    func shadow(_ style: Theme.ShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }

    /// Subtle press-down feedback for tappable cards/tiles. Gives interactive
    /// surfaces a responsive feel without changing layout.
    func pressable() -> some View {
        buttonStyle(PressableScaleStyle())
    }

    /// Replace a scroll/list's default system canvas with the warm app
    /// background, so cards (`appSurface`) sit on the editorial paper tone.
    func warmCanvas() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.appBackground.ignoresSafeArea())
    }

    /// Frosted glass card surface (translucent material + hairline stroke).
    /// Use for content cards that should feel light and layered over the warm
    /// canvas — recipe sections, feed headers, etc.
    func glassCard(cornerRadius: CGFloat = Theme.Radius.large) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.appSeparator.opacity(0.6), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
    }
}

/// Button style that scales and dims slightly while pressed.
struct PressableScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(Theme.Animation.snappy, value: configuration.isPressed)
    }
}
