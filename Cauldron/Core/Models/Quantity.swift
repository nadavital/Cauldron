//
//  Quantity.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation

/// Represents a quantity with a numeric value and unit
struct Quantity: Codable, Sendable, Hashable {
    let value: Double
    let unit: UnitKind
    
    init(value: Double, unit: UnitKind) {
        self.value = value
        self.unit = unit
    }
    
    /// Display the quantity with proper formatting
    var displayString: String {
        let formatted = formatValue(value)
        let unitStr = value == 1.0 ? unit.displayName : unit.pluralName
        return "\(formatted) \(unitStr)"
    }
    
    /// Format value as fraction if appropriate
    private func formatValue(_ value: Double) -> String {
        // Handle common fractions
        let fraction = value.truncatingRemainder(dividingBy: 1.0)
        let whole = Int(value)
        
        // Common fractions
        if abs(fraction - 0.25) < 0.01 {
            return whole > 0 ? "\(whole) ¼" : "¼"
        } else if abs(fraction - 0.33) < 0.02 {
            return whole > 0 ? "\(whole) ⅓" : "⅓"
        } else if abs(fraction - 0.5) < 0.01 {
            return whole > 0 ? "\(whole) ½" : "½"
        } else if abs(fraction - 0.67) < 0.02 {
            return whole > 0 ? "\(whole) ⅔" : "⅔"
        } else if abs(fraction - 0.75) < 0.01 {
            return whole > 0 ? "\(whole) ¾" : "¾"
        } else if abs(fraction) < 0.01 {
            return "\(whole)"
        } else {
            // Use decimal with appropriate precision
            return String(format: "%.2f", value)
        }
    }
    
    /// Scale the quantity by a factor
    func scaled(by factor: Double) -> Quantity {
        Quantity(value: value * factor, unit: unit)
    }
}
