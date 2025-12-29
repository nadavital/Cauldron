//
//  RecipeNotesSection.swift
//  Cauldron
//
//  Displays notes for a recipe with clickable links
//

import SwiftUI

struct RecipeNotesSection: View {
    let notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Notes", systemImage: "note.text")
                .font(.title2)
                .fontWeight(.bold)

            // Detect and make URLs clickable
            if let attributedString = makeLinksClickable(notes) {
                Text(attributedString)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .tint(.cauldronOrange)
            } else {
                Text(notes)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .cardStyle()
    }

    private func makeLinksClickable(_ text: String) -> AttributedString? {
        var attributedString = AttributedString(text)

        // Regular expression to detect URLs
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))

        guard let matches = matches, !matches.isEmpty else {
            return nil
        }

        for match in matches.reversed() {
            if let range = Range(match.range, in: text),
               let url = match.url {
                let startIndex = attributedString.characters.index(attributedString.startIndex, offsetBy: match.range.location)
                let endIndex = attributedString.characters.index(startIndex, offsetBy: match.range.length)
                let attributedRange = startIndex..<endIndex

                attributedString[attributedRange].link = url
                attributedString[attributedRange].foregroundColor = .cauldronOrange
                attributedString[attributedRange].underlineStyle = .single
            }
        }

        return attributedString
    }
}

#Preview {
    RecipeNotesSection(notes: "This recipe is from https://example.com/recipe - enjoy!")
        .padding()
}
