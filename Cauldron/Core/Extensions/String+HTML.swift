//
//  String+HTML.swift
//  Cauldron
//
//  Created by Cauldron AI.
//

import Foundation
import SwiftUI

extension String {
    /// Decodes HTML entities in the string (e.g. "&deg;" -> "°")
    var decodingHTMLEntities: String {
        // NSAttributedString HTML import is heavy and can crash if not on main thread.
        // For our use case (recipes), we mainly care about specific symbols.
        var result = self
        
        let entities = [
            "&deg;": "°",
            "&amp;": "&",
            "&quot;": "\"",
            "&apos;": "'",
            "&#39;": "'",
            "&nbsp;": " ",
            "&lt;": "<",
            "&gt;": ">",
            "&frac12;": "½",
            "&frac14;": "¼",
            "&frac34;": "¾",
            "&frac13;": "⅓",
            "&frac23;": "⅔",
            "&frac18;": "⅛",
            "&frac38;": "⅜",
            "&frac58;": "⅝",
            "&frac78;": "⅞"
        ]
        
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        
        return result
    }
}
