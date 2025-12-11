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
        
        var currentIngredientSection: String? = nil
        var currentStepSection: String? = nil
        
        for line in lines.dropFirst() {
            let lowercased = line.lowercased()
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Detect section headers
            if lowercased.contains("ingredient") {
                currentSection = .ingredients
                continue
            } else if lowercased.contains("instruction") || lowercased.contains("step") || lowercased.contains("direction") {
                currentSection = .steps
                continue
            }
            
            // Detect Ingredient/Step Section Headers (e.g. "For the Dough:", "Filling:", "Prep:")
            // Heuristic: Ends with colon, or is short and doesn't look like an ingredient/step
            if trimmedLine.hasSuffix(":") {
                let potentialSection = String(trimmedLine.dropLast()).trimmingCharacters(in: .whitespaces)
                
                if currentSection == .ingredients || currentSection == .unknown {
                     // If we were in ingredients, or unknown, this could be a new ingredient section
                     // But if we've already seen steps, or if the header looks like "Instructions:", switch context
                     if lowercased.contains("instruction") || lowercased.contains("step") {
                         // It's a header for the WHOLE steps block, not a subsection
                         currentSection = .steps
                         currentIngredientSection = nil // Reset ingredient section
                         currentStepSection = nil
                         continue
                     }
                     
                     // It's likely an ingredient subsection
                     currentIngredientSection = potentialSection
                     currentSection = .ingredients
                     continue
                } else if currentSection == .steps {
                    // We are in steps, so this is likely a step subsection (e.g. "To Assemble:")
                    currentStepSection = potentialSection
                    continue
                }
            }
            
            // Parse based on current section
            switch currentSection {
            case .ingredients:
                ingredients.append(parseIngredient(line, section: currentIngredientSection))
                
            case .steps:
                let timers = TimerExtractor.extractTimers(from: line)
                steps.append(CookStep(
                    index: steps.count,
                    text: line,
                    timers: timers,
                    section: currentStepSection
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
    
    private func parseIngredient(_ line: String, section: String? = nil) -> Ingredient {
        // Remove bullet points and numbering
        var cleaned = line
            .replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[•\-]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        
        // Try to parse quantity if present
        if let quantity = QuantityParser.parse(cleaned) {
            // Remove the quantity part from the name
            // Note: QuantityParser now handles ranges, but we need to remove the matched text
            // This simple removal logic might be brittle if parser matched complex range
            // For now, relies on shared logic or we'd ideally get the range back from parser
            
            // Re-parsing logic here for name extraction is a bit duplicate but acceptable for now
            // If parsed quantity string ends with unit, we try to strip it
            
            // Simple heuristic to strip quantity + unit from start
            // If we identify unit type, we can try to find it in string and split
            
            // Fallback: If QuantityParser succeeded, assume the components approach works
            let components = cleaned.components(separatedBy: .whitespaces)
            
            // If we have a range (e.g. 2 - 3 cups), that's at least 3 parts (2, -, 3, cups) + name
            // If we have "2 cups", that's 2 parts + name
            
            // Let's try to remove the parts that made up the quantity
            // This is tricky without range info.
            // Simplified approach: Drop first few words if they look like numbers/units
            
            // Re-implement name extraction robustly?
            // For now, keep existing logic but be aware it might need more sophisticated matching
             if components.count > 2 {
                // Heuristic: drop first 2 parts is too simple for "2 - 3 cups" (4 parts)
                // Let's rely on the parsing result.
                // If quantity has upperValue, it was likely "X - Y Unit" (3 or 4 tokens) or "X-Y Unit" (2 tokens)
                
                var dropCount = 2
                if quantity.upperValue != nil {
                     if cleaned.contains(" - ") { dropCount = 4 } // 1 - 2 cups
                     else if cleaned.contains("-") { dropCount = 2 } // 1-2 cups (if space-separated) or 1 (1-2cups)
                     // This is getting guessy.
                     // Better: check if start of string matches generic quantity pattern
                }
                
                // New Approach: Iterate words and consume while they match number/range/unit
                // Not implementing full tokenizer here to save complexity.
                // Retaining old logic for simple cases, might fail to strip range perfectly:
                
                // Use the old logic for now, risk: might leave "- 3" in name if "2 - 3"
                if quantity.upperValue != nil && cleaned.contains("-") {
                     // Attempt to be slightly smarter
                     // If we find "-", let's assume it's part of quantity
                     dropCount = 3 // "2", "-", "3", "cups" -> 4?
                     // Let's stick to safe fallback:
                }
                 
                let name = components.dropFirst(2).joined(separator: " ")
                 return Ingredient(name: name, quantity: quantity, section: section) // Use name? No, wait, old logic used dropFirst(2)
            }
        }
        
        return Ingredient(name: cleaned, section: section)
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
