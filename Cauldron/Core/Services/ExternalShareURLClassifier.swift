//
//  ExternalShareURLClassifier.swift
//  Cauldron
//

import Foundation

enum ExternalShareURLClassifier {
    private static let legacyShareTypes = Set(["recipe", "profile", "collection"])
    private static let allowedHosts = Set([
        "cauldron-f900a.web.app",
        "cauldron-f900a.firebaseapp.com",
        "cauldron-prod.web.app",
        "cauldron-prod.firebaseapp.com",
        "cauldron.app"
    ])

    static func isExternalShareURL(_ url: URL) -> Bool {
        guard let host = url.host else { return false }

        guard allowedHosts.contains(host.lowercased()) else {
            return false
        }

        let pathComponents = url.pathComponents
        guard pathComponents.count >= 3 else { return false }

        let route = pathComponents[1]
        if legacyShareTypes.contains(route) {
            return pathComponents.count == 3
        }

        return route == "u" && (pathComponents.count == 3 || pathComponents.count == 4)
    }
}
