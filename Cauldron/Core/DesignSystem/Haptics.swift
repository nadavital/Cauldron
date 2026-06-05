//
//  Haptics.swift
//  Cauldron
//
//  Centralized haptic feedback. Replaces ad-hoc `UIImpactFeedbackGenerator`
//  instances scattered across the app with a single, semantic API so feedback
//  is consistent and easy to audit.
//

import UIKit

/// Semantic haptic feedback helper.
///
/// Use the intent-named methods (`Haptics.success()`, `Haptics.selection()`)
/// rather than raw impact styles so the *meaning* of the feedback is clear at
/// the call site and stays consistent across the app.
@MainActor
enum Haptics {

    // MARK: - Impact

    /// Light tap — small, frequent interactions (toggling a checkbox, stepping).
    static func light() {
        impact(.light)
    }

    /// Medium tap — a committed action (saving, starting a timer).
    static func medium() {
        impact(.medium)
    }

    /// Heavy tap — a significant or destructive confirmation.
    static func heavy() {
        impact(.heavy)
    }

    /// Soft, gentle tap.
    static func soft() {
        impact(.soft)
    }

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    // MARK: - Selection

    /// Selection change — moving between discrete options (picker, segmented).
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    // MARK: - Notification

    /// Operation succeeded (recipe saved, import complete, timer finished).
    static func success() {
        notify(.success)
    }

    /// Something needs attention but isn't an error.
    static func warning() {
        notify(.warning)
    }

    /// Operation failed.
    static func error() {
        notify(.error)
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}
