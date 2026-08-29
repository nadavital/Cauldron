//
//  ExternalShareURLClassifier.swift
//  Cauldron
//

import Foundation

enum ExternalShareURLClassifier {
    enum Route: Equatable {
        case recipe(String)
        case profile(String)
        case collection(String)
    }

    private static let allowedHosts = Set([
        "cauldronrecipes.com",
        "cauldron-f900a.web.app",
        "cauldron-f900a.firebaseapp.com"
    ])

    static func isExternalShareURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host else { return false }

        guard allowedHosts.contains(host.lowercased()) else {
            return false
        }

        return route(from: url) != nil
    }

    static func route(from url: URL) -> Route? {
        let components = url.pathComponents.filter { $0 != "/" }
        switch url.scheme?.lowercased() {
        case "https":
            guard let host = url.host?.lowercased(), allowedHosts.contains(host) else { return nil }
            if components.count == 3, components[0] == "u" {
                let recipeID = components[2]
                return recipeID.isEmpty ? nil : .recipe(recipeID)
            }
            guard components.count == 2 else { return nil }
            let identity = components[1]
            guard !identity.isEmpty else { return nil }
            if components[0] == "u" { return .profile(identity) }
            return legacyRoute(type: components[0], identity: identity)
        case "cauldron":
            guard url.host?.lowercased() == "import", components.count == 2 else { return nil }
            return legacyRoute(type: components[0], identity: components[1])
        default:
            return nil
        }
    }

    private static func legacyRoute(type: String, identity: String) -> Route? {
        guard !identity.isEmpty else { return nil }
        switch type {
        case "recipe":
            return .recipe(identity)
        case "profile":
            return .profile(identity)
        case "collection":
            return .collection(identity)
        default:
            return nil
        }
    }
}
