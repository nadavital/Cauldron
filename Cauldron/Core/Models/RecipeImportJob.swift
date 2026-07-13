import Foundation

nonisolated struct RecipeImportJob: Codable, Sendable, Equatable, Identifiable {
    nonisolated static let currentSchemaVersion = 1

    enum Source: Codable, Sendable, Equatable {
        case url(String)
        case text(String)
        case prepared(Data)
        case shareTransport(ShareExtensionInboxItem)
    }

    enum State: String, Codable, Sendable, Equatable {
        case received
        case processing
        case needsReview
        case ready
        case failed
        case completed
    }

    let id: UUID
    let schemaVersion: Int
    let createdAt: Date
    var updatedAt: Date
    var source: Source
    var state: State
    var attemptCount: Int
    var lastErrorCategory: String?
    var processingStartedAt: Date?

    nonisolated init(
        id: UUID = UUID(),
        schemaVersion: Int = RecipeImportJob.currentSchemaVersion,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        source: Source,
        state: State = .received,
        attemptCount: Int = 0,
        lastErrorCategory: String? = nil,
        processingStartedAt: Date? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.source = source
        self.state = state
        self.attemptCount = attemptCount
        self.lastErrorCategory = lastErrorCategory
        self.processingStartedAt = processingStartedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, createdAt, updatedAt, source, state
        case attemptCount, lastErrorCategory, processingStartedAt
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard version >= 1, version <= Self.currentSchemaVersion else {
            throw RecipeImportJobCodingError.unsupportedSchema(version)
        }
        schemaVersion = Self.currentSchemaVersion
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        source = try container.decode(Source.self, forKey: .source)
        state = try container.decodeIfPresent(State.self, forKey: .state) ?? .received
        attemptCount = try container.decodeIfPresent(Int.self, forKey: .attemptCount) ?? 0
        lastErrorCategory = try container.decodeIfPresent(String.self, forKey: .lastErrorCategory)
        processingStartedAt = try container.decodeIfPresent(Date.self, forKey: .processingStartedAt)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(source, forKey: .source)
        try container.encode(state, forKey: .state)
        try container.encode(attemptCount, forKey: .attemptCount)
        try container.encodeIfPresent(lastErrorCategory, forKey: .lastErrorCategory)
        try container.encodeIfPresent(processingStartedAt, forKey: .processingStartedAt)
    }
}

nonisolated enum RecipeImportJobCodingError: Error, Equatable {
    case unsupportedSchema(Int)
}
