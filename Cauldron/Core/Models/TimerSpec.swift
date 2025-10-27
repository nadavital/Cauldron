//
//  TimerSpec.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation

/// Represents a timer specification for a cooking step
struct TimerSpec: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let seconds: Int
    let label: String
    
    init(id: UUID = UUID(), seconds: Int, label: String = "Timer") {
        self.id = id
        self.seconds = max(0, seconds)
        self.label = label
    }
    
    var displayDuration: String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            // Show hours and minutes only if minutes > 0
            if minutes > 0 {
                // Show seconds only if present
                if secs > 0 {
                    return "\(hours)h \(minutes)m \(secs)s"
                } else {
                    return "\(hours)h \(minutes)m"
                }
            } else {
                // Show seconds if hours but no minutes
                if secs > 0 {
                    return "\(hours)h \(secs)s"
                } else {
                    return "\(hours)h"
                }
            }
        } else if minutes > 0 {
            // Show minutes and seconds only if seconds > 0
            if secs > 0 {
                return "\(minutes)m \(secs)s"
            } else {
                return "\(minutes)m"
            }
        } else {
            return "\(secs)s"
        }
    }
    
    /// Create a TimerSpec from minutes
    static func minutes(_ minutes: Int, label: String = "Timer") -> TimerSpec {
        TimerSpec(seconds: minutes * 60, label: label)
    }
    
    /// Create a TimerSpec from hours
    static func hours(_ hours: Int, label: String = "Timer") -> TimerSpec {
        TimerSpec(seconds: hours * 3600, label: label)
    }
}
