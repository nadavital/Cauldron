//
//  ShareExtensionImportStore.swift
//  Cauldron
//
//  App Group storage for pending recipe URLs sent from Share Extension.
//

import Foundation

enum ShareExtensionImportStore {
    private enum DefaultsInboxAccess {
        case empty
        case items([ShareExtensionInboxItem])
        case unavailable
    }

    private enum FileInboxAccess {
        case emptyOrUnavailable
        case item(ShareExtensionInboxItem)
        case blocked
    }

    struct PendingPreparedSharedRecipe {
        let preparedRecipe: PreparedSharedRecipe
        let payloadData: Data
        let inboxID: UUID?
    }

    static func pendingRecipeURL() -> URL? {
        switch authoritativeInboxAccess() {
        case .item(let item):
            return item.urlString.flatMap(validInboxURL)
        case .blocked:
            return nil
        case .emptyOrUnavailable:
            break
        }
        return pendingRecipeURL(in: UserDefaults(suiteName: ShareExtensionImportContract.appGroupID))
    }

    /// Returns the oldest atomic file handoff without consuming it. The app
    /// persists this into its durable import inbox before acknowledging it.
    static func pendingTransportItem() -> ShareExtensionInboxItem? {
        pendingTransportItem(
            directoryURL: ShareExtensionInboxFiles.directoryURL(),
            defaults: UserDefaults(suiteName: ShareExtensionImportContract.appGroupID),
            fallbackLockURL: ShareExtensionInboxFiles.fallbackLockURL()
        )
    }

    static func pendingTransportItem(
        directoryURL: URL?,
        defaults: UserDefaults?,
        fallbackLockURL: URL?
    ) -> ShareExtensionInboxItem? {
        // Return the raw transport, including malformed payloads. Validation
        // belongs to the durable inbox so failures remain visible/recoverable.
        switch authoritativeInboxAccess(
            directoryURL: directoryURL,
            defaults: defaults,
            fallbackLockURL: fallbackLockURL
        ) {
        case .item(let item):
            return item
        case .blocked:
            return nil
        case .emptyOrUnavailable:
            break
        }
        return nil
    }

    static func acknowledgeTransportItem(id: UUID) {
        let capturedItem = ShareExtensionInboxFiles.items()
            .first(where: { $0.item.id == id })?
            .item
        ShareExtensionInboxFiles.remove(id: id)
        if let defaults = UserDefaults(suiteName: ShareExtensionImportContract.appGroupID) {
            acknowledgeTransportItem(id: id, capturedItem: capturedItem, in: defaults)
        }
    }

    /// Testable defaults-side acknowledgement. The item is captured before its
    /// atomic/defaults representation is removed so matching migration mirrors
    /// can be cleared without touching newer or unrelated legacy values.
    static func acknowledgeTransportItem(
        id: UUID,
        in defaults: UserDefaults,
        fallbackLockURL: URL? = ShareExtensionInboxFiles.fallbackLockURL()
    ) {
        acknowledgeTransportItem(
            id: id,
            capturedItem: nil,
            in: defaults,
            fallbackLockURL: fallbackLockURL
        )
    }

    static func pendingRecipeURL(
        in defaults: UserDefaults?,
        fallbackLockURL: URL? = ShareExtensionInboxFiles.fallbackLockURL()
    ) -> URL? {
        guard let defaults else { return nil }
        switch defaultsInboxAccess(in: defaults, fallbackLockURL: fallbackLockURL) {
        case .items(let items):
            let item = items[0]
            return item.urlString.flatMap(validInboxURL)
        case .unavailable:
            return nil
        case .empty:
            break
        }
        guard
              let urlString = defaults.string(forKey: ShareExtensionImportContract.pendingRecipeURLKey) else {
            return nil
        }
        return validInboxURL(urlString)
    }

    static func pendingRecipeText() -> String? {
        switch authoritativeInboxAccess() {
        case .item(let item):
            return item.text
        case .blocked:
            return nil
        case .emptyOrUnavailable:
            break
        }
        return pendingRecipeText(in: UserDefaults(suiteName: ShareExtensionImportContract.appGroupID))
    }

    static func pendingRecipeText(
        in defaults: UserDefaults?,
        fallbackLockURL: URL? = ShareExtensionInboxFiles.fallbackLockURL()
    ) -> String? {
        guard let defaults else { return nil }
        switch defaultsInboxAccess(in: defaults, fallbackLockURL: fallbackLockURL) {
        case .items(let items):
            return items[0].text
        case .unavailable:
            return nil
        case .empty:
            break
        }
        return defaults.string(forKey: ShareExtensionImportContract.pendingRecipeTextKey)
    }

    static func pendingPreparedRecipe() -> PendingPreparedSharedRecipe? {
        switch authoritativeInboxAccess() {
        case .item(let item):
            guard let payloadData = item.preparedPayload,
                  let preparedRecipe = preparedRecipe(from: payloadData) else { return nil }
            return PendingPreparedSharedRecipe(
                preparedRecipe: preparedRecipe,
                payloadData: payloadData,
                inboxID: item.id
            )
        case .blocked:
            return nil
        case .emptyOrUnavailable:
            break
        }
        return pendingPreparedRecipe(in: UserDefaults(suiteName: ShareExtensionImportContract.appGroupID))
    }

    private static func authoritativeInboxAccess(
        directoryURL: URL? = ShareExtensionInboxFiles.directoryURL(),
        defaults: UserDefaults? = UserDefaults(
            suiteName: ShareExtensionImportContract.appGroupID
        ),
        fallbackLockURL: URL? = ShareExtensionInboxFiles.fallbackLockURL()
    ) -> FileInboxAccess {
        let atomicState = ShareExtensionInboxFiles.atomicInboxState(directoryURL: directoryURL)
        if case .corrupt = atomicState { return .blocked }

        let defaultsAccess: DefaultsInboxAccess
        if let defaults {
            defaultsAccess = defaultsInboxAccess(
                in: defaults,
                fallbackLockURL: fallbackLockURL
            )
        } else {
            defaultsAccess = .empty
        }
        if case .unavailable = defaultsAccess { return .blocked }

        let atomicHead: ShareExtensionInboxItem?
        switch atomicState {
        case .items(let entries):
            atomicHead = entries.first?.item
        case .empty, .unavailable:
            atomicHead = nil
        case .corrupt:
            return .blocked
        }
        let defaultsHead: ShareExtensionInboxItem?
        switch defaultsAccess {
        case .items(let items):
            defaultsHead = items.first
        case .empty:
            defaultsHead = nil
        case .unavailable:
            return .blocked
        }

        switch (atomicHead, defaultsHead) {
        case (.none, .none):
            return .emptyOrUnavailable
        case (.some(let item), .none), (.none, .some(let item)):
            return .item(item)
        case (.some(let atomic), .some(let fallback)):
            return .item(inboxItemPrecedes(atomic, fallback) ? atomic : fallback)
        }
    }

    private static func inboxItemPrecedes(
        _ lhs: ShareExtensionInboxItem,
        _ rhs: ShareExtensionInboxItem
    ) -> Bool {
        if lhs.createdAt == rhs.createdAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.createdAt < rhs.createdAt
    }

    private static func defaultsInboxAccess(
        in defaults: UserDefaults,
        fallbackLockURL: URL? = ShareExtensionInboxFiles.fallbackLockURL()
    ) -> DefaultsInboxAccess {
        do {
            return try ShareExtensionInboxFiles.withFallbackInboxLock(at: fallbackLockURL) {
                switch ShareExtensionInboxFiles.fallbackInboxState(in: defaults) {
                case .empty:
                    return .empty
                case .items(let decodedItems):
                    // Preserve raw entries and FIFO position. Validation occurs
                    // after durable ingestion; a read must never rewrite the
                    // authoritative queue or reveal stale legacy mirrors.
                    return .items(decodedItems)
                case .corrupt:
                    throw ShareExtensionInboxFiles.InboxError.fallbackInboxCorrupt
                }
            }
        } catch {
            return .unavailable
        }
    }

    nonisolated private static func validInboxURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    static func pendingPreparedRecipe(
        in defaults: UserDefaults?,
        fallbackLockURL: URL? = ShareExtensionInboxFiles.fallbackLockURL()
    ) -> PendingPreparedSharedRecipe? {
        guard let defaults else { return nil }
        switch defaultsInboxAccess(in: defaults, fallbackLockURL: fallbackLockURL) {
        case .items(let items):
            let item = items[0]
            guard let payloadData = item.preparedPayload,
                  let preparedRecipe = preparedRecipe(from: payloadData) else { return nil }
            return PendingPreparedSharedRecipe(preparedRecipe: preparedRecipe, payloadData: payloadData, inboxID: item.id)
        case .unavailable:
            return nil
        case .empty:
            break
        }
        guard let payloadData = defaults.data(forKey: ShareExtensionImportContract.preparedRecipePayloadKey) else {
            return nil
        }

        guard let preparedRecipe = preparedRecipe(from: payloadData) else {
            defaults.removeObject(forKey: ShareExtensionImportContract.preparedRecipePayloadKey)
            return nil
        }

        return PendingPreparedSharedRecipe(preparedRecipe: preparedRecipe, payloadData: payloadData, inboxID: nil)
    }

    static func firstHTTPURL(in text: String) -> URL? {
        ShareExtensionImportContract.firstHTTPURL(in: text)
    }

    static func plainTextRecipeShouldTakePrecedenceOverURL(_ text: String) -> Bool {
        ShareExtensionImportContract.plainTextRecipeShouldTakePrecedenceOverURL(text)
    }

    static func consumePendingRecipeURL() -> URL? {
        consumePendingRecipeURL(in: UserDefaults(suiteName: ShareExtensionImportContract.appGroupID))
    }

    static func consumePendingRecipeURL(
        in defaults: UserDefaults?,
        fallbackLockURL: URL? = ShareExtensionInboxFiles.fallbackLockURL()
    ) -> URL? {
        guard let defaults else { return nil }
        return try? ShareExtensionInboxFiles.withFallbackInboxLock(at: fallbackLockURL) {
            guard case .empty = ShareExtensionInboxFiles.fallbackInboxState(in: defaults),
                  let url = defaults.string(forKey: ShareExtensionImportContract.pendingRecipeURLKey)
                    .flatMap(validInboxURL) else {
                return nil
            }
            defaults.removeObject(forKey: ShareExtensionImportContract.pendingRecipeURLKey)
            return url
        }
    }

    static func consumePendingRecipeText() -> String? {
        consumePendingRecipeText(in: UserDefaults(suiteName: ShareExtensionImportContract.appGroupID))
    }

    static func consumePendingRecipeText(
        in defaults: UserDefaults?,
        fallbackLockURL: URL? = ShareExtensionInboxFiles.fallbackLockURL()
    ) -> String? {
        guard let defaults else { return nil }
        return try? ShareExtensionInboxFiles.withFallbackInboxLock(at: fallbackLockURL) {
            guard case .empty = ShareExtensionInboxFiles.fallbackInboxState(in: defaults),
                  let text = defaults.string(forKey: ShareExtensionImportContract.pendingRecipeTextKey) else {
                return nil
            }
            defaults.removeObject(forKey: ShareExtensionImportContract.pendingRecipeTextKey)
            return text
        }
    }

    static func consumePreparedRecipe() -> PreparedSharedRecipe? {
        consumePreparedRecipe(in: UserDefaults(suiteName: ShareExtensionImportContract.appGroupID))
    }

    static func consumePreparedRecipe(
        in defaults: UserDefaults?,
        fallbackLockURL: URL? = ShareExtensionInboxFiles.fallbackLockURL()
    ) -> PreparedSharedRecipe? {
        guard let defaults else { return nil }
        return try? ShareExtensionInboxFiles.withFallbackInboxLock(at: fallbackLockURL) {
            guard case .empty = ShareExtensionInboxFiles.fallbackInboxState(in: defaults),
                  let payloadData = defaults.data(forKey: ShareExtensionImportContract.preparedRecipePayloadKey) else {
                return nil
            }

            guard let preparedRecipe = preparedRecipe(from: payloadData) else {
                defaults.removeObject(forKey: ShareExtensionImportContract.preparedRecipePayloadKey)
                return nil
            }

            defaults.removeObject(forKey: ShareExtensionImportContract.preparedRecipePayloadKey)
            // Prepared payload supersedes a plain pending URL.
            defaults.removeObject(forKey: ShareExtensionImportContract.pendingRecipeURLKey)
            defaults.removeObject(forKey: ShareExtensionImportContract.pendingRecipeTextKey)
            return preparedRecipe
        }
    }

    static func acknowledgePendingRecipeURL(matching url: URL? = nil) {
        // Never acknowledge the atomic file handoff through a legacy URL.
        // It is removed only by `acknowledgeTransportItem` after durable ingest.
        acknowledgePendingRecipeURL(matching: url, in: UserDefaults(suiteName: ShareExtensionImportContract.appGroupID))
    }

    static func acknowledgePendingRecipeURL(
        matching url: URL? = nil,
        in defaults: UserDefaults?,
        fallbackLockURL: URL? = ShareExtensionInboxFiles.fallbackLockURL()
    ) {
        guard let defaults else { return }
        // Legacy acknowledgement must never consume a durable transport item,
        // even if a newer share has an identical payload. Durable items are
        // acknowledged exclusively by their stable transport ID.
        mutateLegacyMirrorsIfInboxIsEmpty(in: defaults, fallbackLockURL: fallbackLockURL) {
            if url == nil || defaults.string(forKey: ShareExtensionImportContract.pendingRecipeURLKey) == url?.absoluteString {
                defaults.removeObject(forKey: ShareExtensionImportContract.pendingRecipeURLKey)
            }
        }
    }

    static func acknowledgePendingRecipeText(matching text: String? = nil) {
        acknowledgePendingRecipeText(matching: text, in: UserDefaults(suiteName: ShareExtensionImportContract.appGroupID))
    }

    static func acknowledgePendingRecipeText(
        matching text: String? = nil,
        in defaults: UserDefaults?,
        fallbackLockURL: URL? = ShareExtensionInboxFiles.fallbackLockURL()
    ) {
        guard let defaults else { return }
        mutateLegacyMirrorsIfInboxIsEmpty(in: defaults, fallbackLockURL: fallbackLockURL) {
            if text == nil || defaults.string(forKey: ShareExtensionImportContract.pendingRecipeTextKey) == text {
                defaults.removeObject(forKey: ShareExtensionImportContract.pendingRecipeTextKey)
            }
        }
    }

    static func acknowledgePreparedRecipe(matching payloadData: Data? = nil) {
        acknowledgePreparedRecipe(matching: payloadData, in: UserDefaults(suiteName: ShareExtensionImportContract.appGroupID))
    }

    static func acknowledgePreparedRecipe(
        matching payloadData: Data? = nil,
        in defaults: UserDefaults?,
        fallbackLockURL: URL? = ShareExtensionInboxFiles.fallbackLockURL()
    ) {
        guard let defaults else { return }
        mutateLegacyMirrorsIfInboxIsEmpty(in: defaults, fallbackLockURL: fallbackLockURL) {
            guard payloadData == nil ||
                    defaults.data(forKey: ShareExtensionImportContract.preparedRecipePayloadKey) == payloadData else {
                return
            }
            defaults.removeObject(forKey: ShareExtensionImportContract.preparedRecipePayloadKey)
            // Prepared payload supersedes a plain pending URL or text from the same share.
            defaults.removeObject(forKey: ShareExtensionImportContract.pendingRecipeURLKey)
            defaults.removeObject(forKey: ShareExtensionImportContract.pendingRecipeTextKey)
        }
    }

    nonisolated static func preparedRecipe(from payloadData: Data) -> PreparedSharedRecipe? {
        do {
            let payload = try JSONDecoder().decode(PreparedShareRecipePayload.self, from: payloadData)
            return payload.toPreparedRecipe()
        } catch {
            AppLogger.general.error("❌ Failed to decode prepared share payload: \(error.localizedDescription)")
            return nil
        }
    }

    static func inbox(
        in defaults: UserDefaults,
        fallbackLockURL: URL? = ShareExtensionInboxFiles.fallbackLockURL()
    ) -> [ShareExtensionInboxItem] {
        switch defaultsInboxAccess(in: defaults, fallbackLockURL: fallbackLockURL) {
        case .empty, .unavailable:
            return []
        case .items(let items):
            return items
        }
    }

    private static func mutateLegacyMirrorsIfInboxIsEmpty(
        in defaults: UserDefaults,
        fallbackLockURL: URL?,
        _ mutation: () -> Void
    ) {
        try? ShareExtensionInboxFiles.withFallbackInboxLock(at: fallbackLockURL) {
            guard case .empty = ShareExtensionInboxFiles.fallbackInboxState(in: defaults) else {
                return
            }
            mutation()
        }
    }

    private static func acknowledgeTransportItem(
        id: UUID,
        capturedItem: ShareExtensionInboxItem?,
        in defaults: UserDefaults,
        fallbackLockURL: URL? = ShareExtensionInboxFiles.fallbackLockURL()
    ) {
        try? ShareExtensionInboxFiles.withFallbackInboxLock(at: fallbackLockURL) {
            var items: [ShareExtensionInboxItem]
            switch ShareExtensionInboxFiles.fallbackInboxState(in: defaults) {
            case .empty:
                items = []
            case .items(let decodedItems):
                items = decodedItems
            case .corrupt:
                throw ShareExtensionInboxFiles.InboxError.fallbackInboxCorrupt
            }
            let item = capturedItem ?? items.first(where: { $0.id == id })
            items.removeAll { $0.id == id }
            try ShareExtensionInboxFiles.persistFallbackInbox(items, in: defaults)
            guard let item else { return }

            if let urlString = item.urlString,
               defaults.string(forKey: ShareExtensionImportContract.pendingRecipeURLKey) == urlString {
                defaults.removeObject(forKey: ShareExtensionImportContract.pendingRecipeURLKey)
            }
            if let text = item.text,
               defaults.string(forKey: ShareExtensionImportContract.pendingRecipeTextKey) == text {
                defaults.removeObject(forKey: ShareExtensionImportContract.pendingRecipeTextKey)
            }
            if let payload = item.preparedPayload,
               defaults.data(forKey: ShareExtensionImportContract.preparedRecipePayloadKey) == payload {
                defaults.removeObject(forKey: ShareExtensionImportContract.preparedRecipePayloadKey)
            }
        }
    }

}

struct PreparedSharedRecipe {
    let recipe: Recipe
    let sourceInfo: String
}

extension PreparedSharedRecipe {
    func recipeParserInputText() -> String {
        recipe.recipeParserInputText()
    }

    func recipeMergedWithParsedContent(_ parsedRecipe: Recipe) -> Recipe {
        recipe.mergedWithParsedContent(parsedRecipe)
    }

    /// Runs every prepared Share Extension payload through the same parser used
    /// by text imports, then restores metadata that is authoritative to the
    /// source page (URL, image, tags, nutrition, and source attribution).
    func canonicalized(using textParser: TextRecipeParser) async -> PreparedSharedRecipe {
        do {
            let parsedRecipe = try await textParser.parse(from: recipeParserInputText())
            return PreparedSharedRecipe(
                recipe: recipeMergedWithParsedContent(parsedRecipe),
                sourceInfo: sourceInfo
            )
        } catch {
            AppLogger.general.warning(
                "Failed to canonicalize prepared share recipe; preserving durable payload: \(error.localizedDescription)"
            )
            return self
        }
    }
}

extension Recipe {
    fileprivate func recipeParserInputText() -> String {
        var lines: [String] = [title]

        if let yields = yields.nonEmpty {
            lines.append("Servings: \(yields)")
        }

        if let totalMinutes {
            lines.append("Total Time: \(totalMinutes) minutes")
        }

        lines.append("")
        lines.append("Ingredients:")
        lines.append(contentsOf: parserInputIngredientLines())

        lines.append("")
        lines.append("Instructions:")
        lines.append(contentsOf: parserInputStepLines())

        if let notes = notes?.nonEmpty {
            lines.append("")
            lines.append("Notes:")
            lines.append(
                contentsOf: notes
                    .components(separatedBy: .newlines)
                    .map(\.trimmed)
                    .filter { !$0.isEmpty }
            )
        }

        return lines.joined(separator: "\n")
    }

    fileprivate func mergedWithParsedContent(_ parsed: Recipe) -> Recipe {
        let mergedTitle = parsed.title.nonEmpty ?? title
        let mergedYields = parsed.yields.nonEmpty ?? yields
        let mergedNotes = parsed.notes?.nonEmpty ?? notes?.nonEmpty

        return Recipe(
            id: id,
            title: mergedTitle,
            ingredients: parsed.ingredients,
            steps: parsed.steps,
            yields: mergedYields,
            totalMinutes: parsed.totalMinutes ?? totalMinutes,
            tags: tags,
            nutrition: nutrition,
            sourceURL: sourceURL ?? parsed.sourceURL,
            sourceTitle: sourceTitle ?? parsed.sourceTitle,
            notes: mergedNotes,
            imageURL: imageURL ?? parsed.imageURL,
            isFavorite: isFavorite,
            visibility: visibility,
            ownerId: ownerId,
            cloudRecordName: cloudRecordName,
            cloudImageRecordName: cloudImageRecordName,
            imageModifiedAt: imageModifiedAt,
            createdAt: createdAt,
            updatedAt: Date(),
            originalRecipeId: originalRecipeId,
            originalCreatorId: originalCreatorId,
            originalCreatorName: originalCreatorName,
            savedAt: savedAt,
            sourceRecipeUpdatedAt: self.sourceRecipeUpdatedAt,
            followsSourceUpdates: self.followsSourceUpdates,
            relatedRecipeIds: relatedRecipeIds,
            isPreview: isPreview
        )
    }

    private func parserInputIngredientLines() -> [String] {
        var lines: [String] = []
        var currentSection: String?

        for ingredient in ingredients {
            let section = ingredient.section?.nonEmpty
            if section != currentSection {
                currentSection = section
                if let section {
                    lines.append("\(section):")
                }
            }
            lines.append(ingredient.displayString)
        }

        return lines
    }

    private func parserInputStepLines() -> [String] {
        var lines: [String] = []
        var currentSection: String?

        for step in steps.sorted(by: { $0.index < $1.index }) {
            let section = step.section?.nonEmpty
            if section != currentSection {
                currentSection = section
                if let section {
                    lines.append("\(section):")
                }
            }

            lines.append("\(step.index + 1). \(step.text.trimmed)")
        }

        return lines
    }
}

extension PreparedShareRecipePayload {
    nonisolated func toPreparedRecipe() -> PreparedSharedRecipe? {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedIngredients = ingredients
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let cleanedSteps = steps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleanedTitle.isEmpty,
              !cleanedIngredients.isEmpty,
              !cleanedSteps.isEmpty else {
            return nil
        }

        let parsedSourceURL = sourceURL.flatMap { URL(string: $0) }
        let parsedImageURL = imageURL.flatMap { URL(string: $0) }
        let ingredientModels = sectionedIngredients(from: cleanedIngredients)
        let stepModels = sectionedSteps(from: cleanedSteps)
        guard !ingredientModels.isEmpty, !stepModels.isEmpty else {
            return nil
        }
        let tags = tagNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { Tag(name: $0) }
        let resolvedYields: String = {
            guard let yields else { return "4 servings" }
            let cleaned = yields.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "4 servings" : cleaned
        }()

        let recipe = Recipe(
            title: cleanedTitle,
            ingredients: ingredientModels,
            steps: stepModels,
            yields: resolvedYields,
            totalMinutes: totalMinutes,
            tags: tags,
            sourceURL: parsedSourceURL,
            sourceTitle: sourceTitle,
            notes: cleanedNotes?.isEmpty == false ? cleanedNotes : nil,
            imageURL: parsedImageURL
        )

        let sourceInfo: String
        if let url = parsedSourceURL {
            sourceInfo = "Imported from \(url.absoluteString)"
        } else {
            sourceInfo = "Imported from shared webpage"
        }

        return PreparedSharedRecipe(recipe: recipe, sourceInfo: sourceInfo)
    }

    nonisolated private func sectionedIngredients(from lines: [String]) -> [Ingredient] {
        var currentSection: String?
        var ingredients: [Ingredient] = []
        for line in lines {
            if let header = RecipeSubsectionHeaderPolicy.title(from: line) {
                currentSection = header
            } else {
                ingredients.append(Ingredient(name: line, section: currentSection))
            }
        }
        return ingredients
    }

    nonisolated private func sectionedSteps(from lines: [String]) -> [CookStep] {
        var currentSection: String?
        var steps: [CookStep] = []
        for line in lines {
            if let header = RecipeSubsectionHeaderPolicy.title(from: line) {
                currentSection = header
            } else {
                steps.append(CookStep(index: steps.count, text: line, section: currentSection))
            }
        }
        return steps
    }

}
