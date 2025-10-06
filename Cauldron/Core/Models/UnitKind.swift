//
//  UnitKind.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation

/// Represents different units of measurement for ingredients
enum UnitKind: String, Codable, Sendable, CaseIterable {
    // Volume - US
    case teaspoon = "tsp"
    case tablespoon = "tbsp"
    case fluidOunce = "fl oz"
    case cup = "cup"
    case pint = "pint"
    case quart = "quart"
    case gallon = "gallon"
    
    // Volume - Metric
    case milliliter = "ml"
    case liter = "L"
    
    // Weight - Imperial
    case ounce = "oz"
    case pound = "lb"
    
    // Weight - Metric
    case gram = "g"
    case kilogram = "kg"
    
    // Count/Other
    case piece = "piece"
    case pinch = "pinch"
    case dash = "dash"
    case whole = "whole"
    case clove = "clove"
    case bunch = "bunch"
    case can = "can"
    case package = "package"
    
    var displayName: String {
        switch self {
        case .teaspoon: return "teaspoon"
        case .tablespoon: return "tablespoon"
        case .fluidOunce: return "fluid ounce"
        case .cup: return "cup"
        case .pint: return "pint"
        case .quart: return "quart"
        case .gallon: return "gallon"
        case .milliliter: return "milliliter"
        case .liter: return "liter"
        case .ounce: return "ounce"
        case .pound: return "pound"
        case .gram: return "gram"
        case .kilogram: return "kilogram"
        case .piece: return "piece"
        case .pinch: return "pinch"
        case .dash: return "dash"
        case .whole: return "whole"
        case .clove: return "clove"
        case .bunch: return "bunch"
        case .can: return "can"
        case .package: return "package"
        }
    }
    
    /// Compact abbreviated display name for UI pickers
    var compactDisplayName: String {
        switch self {
        case .teaspoon: return "tsp"
        case .tablespoon: return "tbsp"
        case .fluidOunce: return "fl oz"
        case .cup: return "cup"
        case .pint: return "pint"
        case .quart: return "quart"
        case .gallon: return "gallon"
        case .milliliter: return "ml"
        case .liter: return "L"
        case .ounce: return "oz"
        case .pound: return "lb"
        case .gram: return "g"
        case .kilogram: return "kg"
        case .piece: return "piece"
        case .pinch: return "pinch"
        case .dash: return "dash"
        case .whole: return "whole"
        case .clove: return "clove"
        case .bunch: return "bunch"
        case .can: return "can"
        case .package: return "package"
        }
    }
    
    var pluralName: String {
        switch self {
        case .teaspoon: return "teaspoons"
        case .tablespoon: return "tablespoons"
        case .fluidOunce: return "fluid ounces"
        case .cup: return "cups"
        case .pint: return "pints"
        case .quart: return "quarts"
        case .gallon: return "gallons"
        case .milliliter: return "milliliters"
        case .liter: return "liters"
        case .ounce: return "ounces"
        case .pound: return "pounds"
        case .gram: return "grams"
        case .kilogram: return "kilograms"
        case .piece: return "pieces"
        case .pinch: return "pinches"
        case .dash: return "dashes"
        case .whole: return "whole"
        case .clove: return "cloves"
        case .bunch: return "bunches"
        case .can: return "cans"
        case .package: return "packages"
        }
    }
    
    var isVolume: Bool {
        switch self {
        case .teaspoon, .tablespoon, .fluidOunce, .cup, .pint, .quart, .gallon,
             .milliliter, .liter:
            return true
        default:
            return false
        }
    }
    
    var isWeight: Bool {
        switch self {
        case .ounce, .pound, .gram, .kilogram:
            return true
        default:
            return false
        }
    }
    
    var isMetric: Bool {
        switch self {
        case .milliliter, .liter, .gram, .kilogram:
            return true
        default:
            return false
        }
    }
}
