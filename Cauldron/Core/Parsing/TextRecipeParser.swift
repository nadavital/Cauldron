//
//  TextRecipeParser.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation

/// Parser for extracting recipes from plain text
actor TextRecipeParser: RecipeParser {
    
    func parse(from text: String) async throws -> Recipe {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        guard !lines.isEmpty else {
            throw ParsingError.invalidSource
        }
        
        // First line is typically the title
        let title = lines[0]
        
        // Find ingredients and steps sections
        var ingredients: [Ingredient] = []
        var steps: [CookStep] = []
        var currentSection: Section = .unknown
        
        enum Section {
            case unknown, ingredients, steps
        }
        
        for line in lines.dropFirst() {
            let lowercased = line.lowercased()
            
            // Detect section headers
            if lowercased.contains("ingredient") {
                currentSection = .ingredients
                continue
            } else if lowercased.contains("instruction") || lowercased.contains("step") || lowercased.contains("direction") {
                currentSection = .steps
                continue
            }
            
            // Parse based on current section
            switch currentSection {
            case .ingredients:
                ingredients.append(parseIngredient(line))
                
            case .steps:
                let timers = TimerExtractor.extractTimers(from: line)
                steps.append(CookStep(
                    index: steps.count,
                    text: line,
                    timers: timers
                ))
                
            case .unknown:
                // Try to infer section from content
                if line.first?.isNumber == true || line.hasPrefix("•") || line.hasPrefix("-") {
                    // Looks like a list item
                    if ingredients.isEmpty {
                        currentSection = .ingredients
                        ingredients.append(parseIngredient(line))
                    } else {
                        currentSection = .steps
                        let timers = TimerExtractor.extractTimers(from: line)
                        steps.append(CookStep(
                            index: steps.count,
                            text: line,
                            timers: timers
                        ))
                    }
                }
            }
        }
        
        // If we still don't have a clear split, try heuristic
        if ingredients.isEmpty || steps.isEmpty {
            return try parseHeuristic(lines)
        }
        
        guard !ingredients.isEmpty else {
            throw ParsingError.noIngredientsFound
        }
        
        guard !steps.isEmpty else {
            throw ParsingError.noStepsFound
        }
        
        return Recipe(
            title: title,
            ingredients: ingredients,
            steps: steps
        )
    }
    
    private func parseIngredient(_ line: String) -> Ingredient {
        // Remove bullet points and numbering
        var cleaned = line
            .replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[•\-]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        
        // Try to parse quantity if present
        if let quantity = QuantityParser.parse(cleaned) {
            // Remove the quantity part from the name
            let components = cleaned.components(separatedBy: .whitespaces)
            if components.count > 2 {
                let name = components.dropFirst(2).joined(separator: " ")
                return Ingredient(name: name, quantity: quantity)
            }
        }
        
        return Ingredient(name: cleaned)
    }
    
    private func parseHeuristic(_ lines: [String]) throws -> Recipe {
        let title = lines[0]
        
        // Simple heuristic: shorter lines (~1-3 words, or with quantities) are likely ingredients
        // Longer lines are likely steps
        var ingredients: [Ingredient] = []
        var steps: [CookStep] = []
        
        for line in lines.dropFirst() {
            let wordCount = line.components(separatedBy: .whitespaces).count
            
            if wordCount <= 5 || line.contains(where: { "0123456789/".contains($0) }) {
                // Likely an ingredient
                ingredients.append(parseIngredient(line))
            } else {
                // Likely a step
                let timers = TimerExtractor.extractTimers(from: line)
                steps.append(CookStep(
                    index: steps.count,
                    text: line,
                    timers: timers
                ))
            }
        }
        
        guard !ingredients.isEmpty else {
            throw ParsingError.noIngredientsFound
        }
        
        guard !steps.isEmpty else {
            throw ParsingError.noStepsFound
        }
        
        return Recipe(
            title: title,
            ingredients: ingredients,
            steps: steps
        )
    }
}
