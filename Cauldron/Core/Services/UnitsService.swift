//
//  UnitsService.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation

/// Service for unit conversion and scaling
actor UnitsService {
    
    /// Convert a quantity to a different unit (if compatible)
    func convert(_ quantity: Quantity, to targetUnit: UnitKind) -> Quantity? {
        // If same unit, return as-is
        if quantity.unit == targetUnit {
            return quantity
        }
        
        // Check if conversion is possible
        guard quantity.unit.isVolume && targetUnit.isVolume ||
              quantity.unit.isWeight && targetUnit.isWeight else {
            return nil // Can't convert between different measurement types
        }
        
        // Convert to base unit, then to target
        if quantity.unit.isVolume && targetUnit.isVolume {
            let milliliters = convertToMilliliters(quantity)
            return convertFromMilliliters(milliliters, to: targetUnit)
        } else if quantity.unit.isWeight && targetUnit.isWeight {
            let grams = convertToGrams(quantity)
            return convertFromGrams(grams, to: targetUnit)
        }
        
        return nil
    }
    
    /// Normalize units to preferred system (metric or imperial)
    func normalize(_ quantity: Quantity, preferMetric: Bool) -> Quantity {
        if preferMetric && !quantity.unit.isMetric && quantity.unit.isVolume {
            return convert(quantity, to: .milliliter) ?? quantity
        } else if !preferMetric && quantity.unit.isMetric && quantity.unit.isVolume {
            return convert(quantity, to: .cup) ?? quantity
        }
        return quantity
    }
    
    // MARK: - Volume Conversions
    
    private func convertToMilliliters(_ quantity: Quantity) -> Double {
        switch quantity.unit {
        case .milliliter: return quantity.value
        case .liter: return quantity.value * 1000
        case .teaspoon: return quantity.value * 4.92892
        case .tablespoon: return quantity.value * 14.7868
        case .fluidOunce: return quantity.value * 29.5735
        case .cup: return quantity.value * 236.588
        case .pint: return quantity.value * 473.176
        case .quart: return quantity.value * 946.353
        case .gallon: return quantity.value * 3785.41
        default: return quantity.value
        }
    }
    
    private func convertFromMilliliters(_ ml: Double, to unit: UnitKind) -> Quantity {
        let value: Double
        switch unit {
        case .milliliter: value = ml
        case .liter: value = ml / 1000
        case .teaspoon: value = ml / 4.92892
        case .tablespoon: value = ml / 14.7868
        case .fluidOunce: value = ml / 29.5735
        case .cup: value = ml / 236.588
        case .pint: value = ml / 473.176
        case .quart: value = ml / 946.353
        case .gallon: value = ml / 3785.41
        default: value = ml
        }
        return Quantity(value: value, unit: unit)
    }
    
    // MARK: - Weight Conversions
    
    private func convertToGrams(_ quantity: Quantity) -> Double {
        switch quantity.unit {
        case .gram: return quantity.value
        case .kilogram: return quantity.value * 1000
        case .ounce: return quantity.value * 28.3495
        case .pound: return quantity.value * 453.592
        default: return quantity.value
        }
    }
    
    private func convertFromGrams(_ grams: Double, to unit: UnitKind) -> Quantity {
        let value: Double
        switch unit {
        case .gram: value = grams
        case .kilogram: value = grams / 1000
        case .ounce: value = grams / 28.3495
        case .pound: value = grams / 453.592
        default: value = grams
        }
        return Quantity(value: value, unit: unit)
    }
}
