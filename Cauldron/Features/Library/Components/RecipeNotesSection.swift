//
//  RecipeNotesSection.swift
//  Cauldron
//
//  Displays notes for a recipe with clickable links
//

import SwiftUI

struct RecipeNotesSection: View {
    let notes: String

    private var displayNotes: String {
        notes.recipeDetailLineBreakFriendly()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderLabel(title: "Notes", systemImage: "note.text")

            // Detect and make URLs clickable
            if let attributedString = makeLinksClickable(notes) {
                Text(attributedString)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .tint(.cauldronOrange)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(displayNotes)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardStyle()
    }

    private func makeLinksClickable(_ text: String) -> AttributedString? {
        let displayText = text.recipeDetailLineBreakFriendly()
        var attributedString = AttributedString(displayText)

        // Regular expression to detect URLs
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))

        guard let matches = matches, !matches.isEmpty else {
            return nil
        }

        var searchStart = displayText.startIndex
        var didApplyLink = false

        for match in matches {
            guard let sourceRange = Range(match.range, in: text),
                  let url = match.url else {
                continue
            }

            let breakableURLText = String(text[sourceRange]).recipeDetailLineBreakFriendly()
            guard let displayRange = displayText.range(of: breakableURLText, range: searchStart..<displayText.endIndex),
                  let startIndex = AttributedString.Index(displayRange.lowerBound, within: attributedString),
                  let endIndex = AttributedString.Index(displayRange.upperBound, within: attributedString) else {
                continue
            }

            let attributedRange = startIndex..<endIndex
            attributedString[attributedRange].link = url
            attributedString[attributedRange].foregroundColor = .cauldronOrange
            attributedString[attributedRange].underlineStyle = .single
            searchStart = displayRange.upperBound
            didApplyLink = true
        }

        return didApplyLink ? attributedString : nil
    }
}

#Preview {
    RecipeNotesSection(notes: "This recipe is from https://example.com/recipe - enjoy!")
        .padding()
}
