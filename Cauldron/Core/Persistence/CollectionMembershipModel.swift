//
//  CollectionMembershipModel.swift
//  Cauldron
//

import Foundation
import SwiftData

enum CollectionMembershipStatus: String, Codable, Sendable {
    case active
    case removed
}

struct CollectionMembershipEdge: Codable, Sendable, Hashable, Identifiable {
    nonisolated static let currentSchemaVersion = 1

    var id: String { "\(collectionId.uuidString):\(recipeId.uuidString)" }
    let collectionId: UUID
    let recipeId: UUID
    let ownerId: UUID
    let status: CollectionMembershipStatus
    let updatedAt: Date
    let sortOrder: Int
    let sourceDeviceId: String?
    let schemaVersion: Int

    nonisolated init(
        collectionId: UUID,
        recipeId: UUID,
        ownerId: UUID,
        status: CollectionMembershipStatus,
        updatedAt: Date = Date(),
        sortOrder: Int,
        sourceDeviceId: String? = nil,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.collectionId = collectionId
        self.recipeId = recipeId
        self.ownerId = ownerId
        self.status = status
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.sourceDeviceId = sourceDeviceId
        self.schemaVersion = schemaVersion
    }
}

@Model
final class CollectionMembershipModel {
    var collectionId: UUID = UUID()
    var recipeId: UUID = UUID()
    var ownerId: UUID = UUID()
    var status: String = CollectionMembershipStatus.active.rawValue
    var updatedAt: Date = Date()
    var sortOrder: Int = 0
    var sourceDeviceId: String?
    var schemaVersion: Int = CollectionMembershipEdge.currentSchemaVersion

    init(
        collectionId: UUID,
        recipeId: UUID,
        ownerId: UUID,
        status: String = CollectionMembershipStatus.active.rawValue,
        updatedAt: Date = Date(),
        sortOrder: Int = 0,
        sourceDeviceId: String? = nil,
        schemaVersion: Int = CollectionMembershipEdge.currentSchemaVersion
    ) {
        self.collectionId = collectionId
        self.recipeId = recipeId
        self.ownerId = ownerId
        self.status = status
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.sourceDeviceId = sourceDeviceId
        self.schemaVersion = schemaVersion
    }

    static func from(_ edge: CollectionMembershipEdge) -> CollectionMembershipModel {
        CollectionMembershipModel(
            collectionId: edge.collectionId,
            recipeId: edge.recipeId,
            ownerId: edge.ownerId,
            status: edge.status.rawValue,
            updatedAt: edge.updatedAt,
            sortOrder: edge.sortOrder,
            sourceDeviceId: edge.sourceDeviceId,
            schemaVersion: edge.schemaVersion
        )
    }

    func toDomain() -> CollectionMembershipEdge {
        CollectionMembershipEdge(
            collectionId: collectionId,
            recipeId: recipeId,
            ownerId: ownerId,
            status: CollectionMembershipStatus(rawValue: status) ?? .removed,
            updatedAt: updatedAt,
            sortOrder: sortOrder,
            sourceDeviceId: sourceDeviceId,
            schemaVersion: schemaVersion
        )
    }
}
