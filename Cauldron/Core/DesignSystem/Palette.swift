//
//  Palette.swift
//  Cauldron
//
//  The app's semantic color palette. Warm, editorial neutrals (a hint of
//  paper/cream in light, warm charcoal in dark) layered under the existing
//  Cauldron orange accent — native-feeling, with a cozy cookbook soul.
//
//  Prefer these semantic tokens over raw `Color(.systemBackground)` etc. so the
//  whole app can be re-themed from one place.
//

import SwiftUI
import UIKit

extension Color {

    // MARK: - Surfaces

    /// App canvas behind scrolling content. Warm paper in light, warm charcoal in dark.
    static let appBackground = Color(lightHex: 0xF6F1EA, darkHex: 0x18120D)

    /// Resting card / grouped-cell surface that sits on top of `appBackground`.
    static let appSurface = Color(lightHex: 0xFFFFFF, darkHex: 0x262220)

    /// Raised surface for sheets, popovers, and stacked cards.
    static let appSurfaceElevated = Color(lightHex: 0xFFFDFB, darkHex: 0x322D29)

    /// Hairline separators / subtle strokes on warm surfaces.
    static let appSeparator = Color(lightHex: 0xE7DFD3, darkHex: 0x3A342F)

    // MARK: - Brand

    /// Deeper ember orange — pair with `cauldronOrange` for warm brand gradients.
    static let cauldronEmber = Color(lightHex: 0xE0671F, darkHex: 0xF2873A)

    /// Brand warmth gradient (top-leading → bottom-trailing). Use sparingly for
    /// hero surfaces, no-image fallbacks, and delight moments.
    static var cauldronWarmGradient: LinearGradient {
        LinearGradient(
            colors: [.cauldronOrange, .cauldronEmber],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Hex init

    /// Adaptive color from light/dark 24-bit RGB hex values.
    init(lightHex: UInt, darkHex: UInt) {
        self = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgbHex: darkHex)
                : UIColor(rgbHex: lightHex)
        })
    }
}

private extension UIColor {
    convenience init(rgbHex: UInt) {
        self.init(
            red: CGFloat((rgbHex >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgbHex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgbHex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
