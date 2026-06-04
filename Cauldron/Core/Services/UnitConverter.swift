//
//  UnitConverter.swift
//  Cauldron
//
//  Synchronous, pure unit conversion for display. Unlike the async `UnitsService`
//  actor, this is safe to call directly from SwiftUI view bodies to convert a
//  recipe's ingredients into a chosen measurement system on the fly.
//

import Foundation

/// Measurement system a user can view a recipe's ingredients in.
enum UnitSystem: String, CaseIterable, Identifiable {
    case original
    case metric
    case us

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: return "Original"
        case .metric: return "Metric"
        case .us: return "US"
        }
    }

    /// Short label for compact controls.
    var shortLabel: String {
        switch self {
        case .original: return "Orig"
        case .metric: return "Metric"
        case .us: return "US"
        }
    }
}

/// Pure helpers for converting quantities/ingredients between measurement systems.
enum UnitConverter {

    // MARK: - Public API

    /// Convert every ingredient's quantities into the target system (display only).
    static func convert(_ ingredients: [Ingredient], to system: UnitSystem) -> [Ingredient] {
        guard system != .original else { return ingredients }
        return ingredients.map { ingredient in
            Ingredient(
                id: ingredient.id,
                name: ingredient.name,
                quantity: ingredient.quantity.map { convert($0, to: system) },
                additionalQuantities: ingredient.additionalQuantities.map { convert($0, to: system) },
                note: ingredient.note,
                section: ingredient.section
            )
        }
    }

    /// Convert a single quantity into the target system, picking a sensible unit.
    /// Quantities that aren't volume or weight (e.g. "2 pieces") are unchanged.
    static func convert(_ quantity: Quantity, to system: UnitSystem) -> Quantity {
        guard system != .original else { return quantity }

        if quantity.unit.isVolume {
            let ml = toMilliliters(quantity.value, unit: quantity.unit)
            let upperMl = quantity.upperValue.map { toMilliliters($0, unit: quantity.unit) }
            let target = volumeTargetUnit(forMilliliters: ml, system: system)
            return makeQuantity(
                baseValue: ml,
                upperBaseValue: upperMl,
                target: target,
                fromBase: fromMilliliters
            )
        }

        if quantity.unit.isWeight {
            let grams = toGrams(quantity.value, unit: quantity.unit)
            let upperGrams = quantity.upperValue.map { toGrams($0, unit: quantity.unit) }
            let target = weightTargetUnit(forGrams: grams, system: system)
            return makeQuantity(
                baseValue: grams,
                upperBaseValue: upperGrams,
                target: target,
                fromBase: fromGrams
            )
        }

        return quantity
    }

    // MARK: - Target unit selection

    private static func volumeTargetUnit(forMilliliters ml: Double, system: UnitSystem) -> UnitKind {
        switch system {
        case .metric:
            return ml >= 1000 ? .liter : .milliliter
        case .us:
            if ml < 15 { return .teaspoon }
            if ml < 45 { return .tablespoon }
            if ml < 960 { return .cup }
            return .quart
        case .original:
            return .milliliter
        }
    }

    private static func weightTargetUnit(forGrams grams: Double, system: UnitSystem) -> UnitKind {
        switch system {
        case .metric:
            return grams >= 1000 ? .kilogram : .gram
        case .us:
            return grams < 454 ? .ounce : .pound
        case .original:
            return .gram
        }
    }

    // MARK: - Quantity assembly

    private static func makeQuantity(
        baseValue: Double,
        upperBaseValue: Double?,
        target: UnitKind,
        fromBase: (Double, UnitKind) -> Double
    ) -> Quantity {
        let value = displayRound(fromBase(baseValue, target), unit: target)
        if let upperBaseValue {
            let upper = displayRound(fromBase(upperBaseValue, target), unit: target)
            return Quantity(value: value, upperValue: upper, unit: target)
        }
        return Quantity(value: value, unit: target)
    }

    /// Round to a tidy precision for display based on the target unit.
    private static func displayRound(_ value: Double, unit: UnitKind) -> Double {
        switch unit {
        case .milliliter, .gram:
            return (value).rounded()                       // whole ml/g
        case .liter, .kilogram:
            return (value * 10).rounded() / 10             // 1 decimal
        default:
            return (value * 4).rounded() / 4               // nearest 1/4 for cups/oz/etc.
        }
    }

    // MARK: - Base conversions (volume → ml, weight → g)

    private static func toMilliliters(_ value: Double, unit: UnitKind) -> Double {
        switch unit {
        case .milliliter: return value
        case .liter: return value * 1000
        case .teaspoon: return value * 4.92892
        case .tablespoon: return value * 14.7868
        case .fluidOunce: return value * 29.5735
        case .cup: return value * 236.588
        case .pint: return value * 473.176
        case .quart: return value * 946.353
        case .gallon: return value * 3785.41
        default: return value
        }
    }

    private static func fromMilliliters(_ ml: Double, to unit: UnitKind) -> Double {
        switch unit {
        case .milliliter: return ml
        case .liter: return ml / 1000
        case .teaspoon: return ml / 4.92892
        case .tablespoon: return ml / 14.7868
        case .fluidOunce: return ml / 29.5735
        case .cup: return ml / 236.588
        case .pint: return ml / 473.176
        case .quart: return ml / 946.353
        case .gallon: return ml / 3785.41
        default: return ml
        }
    }

    private static func toGrams(_ value: Double, unit: UnitKind) -> Double {
        switch unit {
        case .gram: return value
        case .kilogram: return value * 1000
        case .ounce: return value * 28.3495
        case .pound: return value * 453.592
        default: return value
        }
    }

    private static func fromGrams(_ grams: Double, to unit: UnitKind) -> Double {
        switch unit {
        case .gram: return grams
        case .kilogram: return grams / 1000
        case .ounce: return grams / 28.3495
        case .pound: return grams / 453.592
        default: return grams
        }
    }
}
