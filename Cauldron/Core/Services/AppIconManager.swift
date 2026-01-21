//
//  AppIconManager.swift
//  Cauldron
//
//  Manages alternate app icon selection and switching
//

import UIKit
import Combine

/// Represents an available app icon theme
struct AppIconTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let iconName: String? // nil means default icon
    let category: IconCategory

    enum IconCategory: String, CaseIterable {
        case standard = "Standard"
        case wicked = "Wicked"
        case disney = "Disney"
        case marvel = "Marvel"
        case houses = "Houses"
    }

    static func == (lhs: AppIconTheme, rhs: AppIconTheme) -> Bool {
        lhs.id == rhs.id
    }
}

/// Manages app icon switching functionality
@MainActor
final class AppIconManager: ObservableObject {
    static let shared = AppIconManager()

    @Published private(set) var currentIconName: String?
    @Published private(set) var supportsAlternateIcons: Bool

    /// All available icon themes
    let availableIcons: [AppIconTheme] = [
        // Standard
        AppIconTheme(id: "default", name: "Classic", iconName: nil, category: .standard),

        // Wicked Musical
        AppIconTheme(id: "wicked", name: "Wicked", iconName: "CauldronIconWicked", category: .wicked),
        AppIconTheme(id: "goodwitch", name: "Glinda", iconName: "CauldronIconGoodWitch", category: .wicked),

        // Disney Villains
        AppIconTheme(id: "maleficent", name: "Maleficent", iconName: "CauldronIconMaleficent", category: .disney),
        AppIconTheme(id: "ursula", name: "Ursula", iconName: "CauldronIconUrsula", category: .disney),

        // Marvel
        AppIconTheme(id: "agatha", name: "Agatha", iconName: "CauldronIconAgatha", category: .marvel),
        AppIconTheme(id: "scarletwitch", name: "Scarlet Witch", iconName: "CauldronIconScarletWitch", category: .marvel),

        // House Animals
        AppIconTheme(id: "lion", name: "Lion", iconName: "CauldronIconLion", category: .houses),
        AppIconTheme(id: "serpent", name: "Serpent", iconName: "CauldronIconSerpent", category: .houses),
        AppIconTheme(id: "badger", name: "Badger", iconName: "CauldronIconBadger", category: .houses),
        AppIconTheme(id: "eagle", name: "Eagle", iconName: "CauldronIconEagle", category: .houses),
    ]

    private init() {
        self.supportsAlternateIcons = UIApplication.shared.supportsAlternateIcons
        self.currentIconName = UIApplication.shared.alternateIconName
    }

    /// Returns icons grouped by category
    var iconsByCategory: [AppIconTheme.IconCategory: [AppIconTheme]] {
        Dictionary(grouping: availableIcons, by: { $0.category })
    }

    /// Returns the currently selected icon theme
    var currentTheme: AppIconTheme {
        availableIcons.first { $0.iconName == currentIconName } ?? availableIcons[0]
    }

    /// Returns only unlocked icons
    var unlockedIcons: [AppIconTheme] {
        availableIcons.filter { ReferralManager.shared.isIconUnlocked($0.id) }
    }

    /// Returns unlocked icons grouped by category
    var unlockedIconsByCategory: [AppIconTheme.IconCategory: [AppIconTheme]] {
        Dictionary(grouping: unlockedIcons, by: { $0.category })
    }

    /// Check if a specific icon is unlocked
    func isUnlocked(_ theme: AppIconTheme) -> Bool {
        ReferralManager.shared.isIconUnlocked(theme.id)
    }

    /// Get how many referrals needed to unlock an icon
    func referralsToUnlock(_ theme: AppIconTheme) -> Int? {
        ReferralManager.shared.referralsNeeded(for: theme.id)
    }

    /// Changes the app icon to the specified theme
    /// - Parameter theme: The theme to switch to
    /// - Returns: True if successful, false otherwise
    @discardableResult
    func setIcon(_ theme: AppIconTheme) async -> Bool {
        guard supportsAlternateIcons else {
            AppLogger.general.warning("Device does not support alternate icons")
            return false
        }

        // Check if icon is unlocked
        guard isUnlocked(theme) else {
            AppLogger.general.warning("Cannot set locked icon: \(theme.name)")
            return false
        }

        // Don't change if already set to this icon
        if currentIconName == theme.iconName {
            return true
        }

        do {
            try await UIApplication.shared.setAlternateIconName(theme.iconName)
            currentIconName = theme.iconName
            AppLogger.general.info("✅ Changed app icon to: \(theme.name)")
            return true
        } catch {
            // Simulator sometimes reports errors even when the icon change succeeded
            // Check if the icon actually changed despite the error
            let actualIconName = UIApplication.shared.alternateIconName
            if actualIconName == theme.iconName {
                currentIconName = theme.iconName
                AppLogger.general.info("✅ Changed app icon to: \(theme.name) (despite reported error)")
                return true
            }

            AppLogger.general.error("❌ Failed to change app icon: \(error.localizedDescription)")
            return false
        }
    }

    /// Resets to the default app icon
    @discardableResult
    func resetToDefault() async -> Bool {
        await setIcon(availableIcons[0])
    }
}
