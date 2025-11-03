//
//  CookModeWidget.swift
//  CauldronWidget
//
//  Widget Extension for Cauldron Cook Mode Live Activities
//

import WidgetKit
import SwiftUI

/// Main Widget Bundle for Cauldron
/// Registers the Live Activity configuration
@main
struct CauldronWidgetBundle: WidgetBundle {
    var body: some Widget {
        // Register the Live Activity
        CookModeLiveActivity()
    }
}
