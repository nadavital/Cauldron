//
//  CookStep.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation

/// Represents a cooking step in a recipe
struct CookStep: Sendable, Hashable, Identifiable {
    let id: UUID
    let index: Int
    let text: String
    let timers: [TimerSpec]
    let mediaURL: URL?
    let section: String?
    
    nonisolated init(
        id: UUID = UUID(),
        index: Int,
        text: String,
        timers: [TimerSpec] = [],
        mediaURL: URL? = nil,
        section: String? = nil
    ) {
        self.id = id
        self.index = index
        self.text = text
        self.timers = timers
        self.mediaURL = mediaURL
        self.section = section
    }
    
    nonisolated var hasTimers: Bool {
        !timers.isEmpty
    }
    
    nonisolated var displayIndex: String {
        "Step \(index + 1)"
    }
}

extension CookStep: Codable {}
