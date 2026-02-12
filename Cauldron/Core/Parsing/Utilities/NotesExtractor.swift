//
//  NotesExtractor.swift
//  Cauldron
//
//  Created on January 25, 2026.
//

import Foundation

/// Extracts notes, tips, and additional information from recipe text
///
/// Handles sections like:
/// - "Notes:", "Chef's Notes:", "Recipe Notes:"
/// - "Tips:", "Pro Tips:", "Helpful Tips:"
/// - "Variations:", "Substitutions:"
/// - "Storage:", "Make Ahead:", "Freezing:"
struct NotesExtractor {

    /// Section headers that indicate notes content
    private static let notesSectionHeaders = [
        "notes",
        "note",
        "chef's notes",
        "chef notes",
        "recipe notes",
        "tips",
        "tip",
        "pro tips",
        "helpful tips",
        "cooking tips",
        "variations",
        "variation",
        "substitutions",
        "substitution",
        "storage",
        "storing",
        "make ahead",
        "make-ahead",
        "freezing",
        "to freeze",
        "reheating",
        "to reheat",
        "nutrition notes",
        "serving suggestions",
        "additional notes",
        "important notes"
    ]

    /// Extract notes from lines of text
    ///
    /// - Parameter lines: Array of text lines to search
    /// - Returns: Combined notes text, or nil if none found
    ///
    /// Examples:
    /// ```swift
    /// NotesExtractor.extractNotes(from: ["...", "Notes:", "Use fresh herbs", "Tips:", "Can substitute butter"])
    /// // "Notes:\nUse fresh herbs\n\nTips:\nCan substitute butter"
    /// ```
    static func extractNotes(from lines: [String]) -> String? {
        var notesSections: [(header: String, content: [String])] = []
        var currentSection: (header: String, content: [String])? = nil
        var inNotesSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Check if this line is a notes section header
            if let header = isNotesSectionHeader(trimmed) {
                // Save previous section if exists
                if let section = currentSection, !section.content.isEmpty {
                    notesSections.append(section)
                }

                // Start new section
                currentSection = (header: header, content: [])
                inNotesSection = true
                continue
            }

            // Check if we hit a non-notes section header (end of notes)
            if inNotesSection && isOtherSectionHeader(trimmed) {
                // Save current section and stop
                if let section = currentSection, !section.content.isEmpty {
                    notesSections.append(section)
                }
                currentSection = nil
                inNotesSection = false
                continue
            }

            // Add content to current section
            if inNotesSection, !trimmed.isEmpty {
                currentSection?.content.append(trimmed)
            }
        }

        // Don't forget the last section
        if let section = currentSection, !section.content.isEmpty {
            notesSections.append(section)
        }

        // Format output
        guard !notesSections.isEmpty else {
            return nil
        }

        let formattedSections = notesSections.map { section -> String in
            let contentText = section.content.joined(separator: "\n")
            if notesSections.count > 1 {
                // Multiple sections: include headers
                return "\(section.header):\n\(contentText)"
            } else {
                // Single section: just the content
                return contentText
            }
        }

        let result = formattedSections.joined(separator: "\n\n")
        return result.isEmpty ? nil : result
    }

    /// Check if a line is a notes section header
    ///
    /// - Parameter line: The line to check
    /// - Returns: The normalized header name, or nil if not a notes header
    private static func isNotesSectionHeader(_ line: String) -> String? {
        let lowercased = line.lowercased()

        // Check if line ends with colon (header format)
        let lineWithoutColon = lowercased.hasSuffix(":")
            ? String(lowercased.dropLast()).trimmingCharacters(in: .whitespaces)
            : lowercased

        // Match against known headers
        for header in notesSectionHeaders {
            if lineWithoutColon == header || lineWithoutColon == header + "s" {
                return header.capitalized
            }
        }

        return nil
    }

    /// Check if a line is a section header that would end the notes section
    private static func isOtherSectionHeader(_ line: String) -> Bool {
        let lowercased = line.lowercased()

        // Headers that indicate end of notes
        let otherHeaders = [
            "ingredients",
            "ingredient",
            "instructions",
            "instruction",
            "directions",
            "direction",
            "steps",
            "step",
            "method",
            "preparation",
            "recipe"
        ]

        let lineWithoutColon = lowercased.hasSuffix(":")
            ? String(lowercased.dropLast()).trimmingCharacters(in: .whitespaces)
            : lowercased

        return otherHeaders.contains(lineWithoutColon)
    }

    /// Extract a single notes section from text (simpler version)
    ///
    /// - Parameter text: The full text to search
    /// - Returns: Notes content, or nil if none found
    static func extractNotes(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return extractNotes(from: lines)
    }

    /// Check whether a line starts a notes/tips/variation style section.
    /// Useful for parser section routing before full notes extraction.
    static func looksLikeNotesSectionHeader(_ line: String) -> Bool {
        isNotesSectionHeader(line.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }
}
