//
//  ShareExtensionImportStore.swift
//  Cauldron
//
//  App Group storage for pending recipe URLs sent from Share Extension.
//

import Foundation

enum ShareExtensionImportStore {
    static let appGroupID = "group.Nadav.Cauldron"
    static let pendingRecipeURLKey = "shareExtension.pendingRecipeURL"

    static func pendingRecipeURL() -> URL? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let urlString = defaults.string(forKey: pendingRecipeURLKey) else {
            return nil
        }
        return URL(string: urlString)
    }

    static func consumePendingRecipeURL() -> URL? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let url = pendingRecipeURL() else {
            return nil
        }

        defaults.removeObject(forKey: pendingRecipeURLKey)
        return url
    }
}
