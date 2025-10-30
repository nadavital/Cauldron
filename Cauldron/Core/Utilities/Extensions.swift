//
//  Extensions.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation
import SwiftUI

// MARK: - Date Extensions

extension Date {
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
    
    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }
    
    func timeAgo() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - String Extensions

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var nonEmpty: String? {
        let trimmed = self.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Color Extensions

extension Color {
    static let cauldronOrange = Color(red: 1.0, green: 0.6, blue: 0.2)
    static let cauldronBackground = Color(.systemBackground)
    static let cauldronSecondaryBackground = Color(.secondarySystemBackground)

    // MARK: - Profile Colors

    /// Profile color options for user customization
    /// Organized in a distinct, well-spaced palette with clear visual differences

    // Warm colors
    static let profileOrange = Color(red: 1.0, green: 0.55, blue: 0.0)
    static let profileRed = Color(red: 0.95, green: 0.25, blue: 0.25)
    static let profilePink = Color(red: 1.0, green: 0.35, blue: 0.65)
    static let profileCoral = Color(red: 0.95, green: 0.45, blue: 0.35)

    // Cool colors
    static let profileBlue = Color(red: 0.2, green: 0.55, blue: 0.95)
    static let profileTeal = Color(red: 0.15, green: 0.75, blue: 0.7)
    static let profileSky = Color(red: 0.4, green: 0.75, blue: 1.0)
    static let profileMint = Color(red: 0.25, green: 0.85, blue: 0.65)

    // Purples
    static let profilePurple = Color(red: 0.65, green: 0.3, blue: 0.85)
    static let profileIndigo = Color(red: 0.4, green: 0.35, blue: 0.9)
    static let profileLavender = Color(red: 0.75, green: 0.55, blue: 0.9)
    static let profileMagenta = Color(red: 0.85, green: 0.25, blue: 0.75)

    // Greens & Yellows
    static let profileGreen = Color(red: 0.25, green: 0.75, blue: 0.35)
    static let profileLime = Color(red: 0.55, green: 0.85, blue: 0.2)
    static let profileYellow = Color(red: 0.95, green: 0.75, blue: 0.15)
    static let profileAmber = Color(red: 1.0, green: 0.65, blue: 0.0)

    /// All available profile colors organized by color family
    static let allProfileColors: [Color] = [
        // Row 1: Warm colors
        .profileRed,
        .profileCoral,
        .profileOrange,
        .profileAmber,

        // Row 2: Pinks & Purples
        .profilePink,
        .profileMagenta,
        .profilePurple,
        .profileLavender,

        // Row 3: Blues
        .profileIndigo,
        .profileBlue,
        .profileSky,
        .profileTeal,

        // Row 4: Greens & Yellows
        .profileMint,
        .profileGreen,
        .profileLime,
        .profileYellow
    ]

    /// Convert Color to hex string
    func toHex() -> String? {
        guard let components = self.cgColor?.components else { return nil }

        let r = components[0]
        let g = components[1]
        let b = components[2]

        return String(format: "#%02X%02X%02X",
                     Int(r * 255),
                     Int(g * 255),
                     Int(b * 255))
    }

    /// Create Color from hex string
    static func fromHex(_ hex: String) -> Color? {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        return Color(red: r, green: g, blue: b)
    }

    /// Initialize Color from hex string
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Extensions

extension View {
    func cardStyle() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cauldronSecondaryBackground)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    func prominentButton() -> some View {
        self
            .font(.headline)
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.cauldronOrange)
            .cornerRadius(12)
    }
}
