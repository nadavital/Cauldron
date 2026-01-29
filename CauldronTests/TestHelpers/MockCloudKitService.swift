//
//  MockCloudKitService.swift
//  CauldronTests
//
//  Created on November 13, 2025.
//

import Foundation
import CloudKit
@testable import Cauldron

/// Mock CloudKitService for testing repositories without real CloudKit calls
@MainActor
final class MockCloudKitService {

    // MARK: - Mock State

    private(set) var savedRecipes: [String: CKRecord] = [:]
    private(set) var savedCollections: [UUID: Collection] = [:]
    private(set) var savedUsers: [String: CKRecord] = [:]
    private(set) var savedConnections: [String: CKRecord] = [:]
    private(set) var deletedRecordIDs: Set<CKRecord.ID> = []
    private(set) var deletedCollectionIDs: Set<UUID> = []

    var shouldFailAccountCheck = false
    var shouldFailSave = false
    var shouldFailFetch = false
    var shouldFailDelete = false
    var accountStatus: CloudKitAccountStatus = .available

    // Track calls for verification
    private(set) var checkAccountStatusCalled = false
    private(set) var saveRecordCalled = false
    private(set) var fetchRecordCalled = false
    private(set) var deleteRecordCalled = false

    // MARK: - Account Status

    func checkAccountStatus() async -> CloudKitAccountStatus {
        checkAccountStatusCalled = true
        if shouldFailAccountCheck {
            return .noAccount
        }
        return accountStatus
    }

    func getAccountStatus() async -> CloudKitAccountStatus {
        return await checkAccountStatus()
    }

    func isAvailable() async -> Bool {
        let status = await checkAccountStatus()
        return status.isAvailable
    }

    // MARK: - Recipe Operations

    func saveRecipe(_ record: CKRecord, to database: CKDatabase.Scope) async throws {
        saveRecordCalled = true

        if shouldFailSave {
            throw CloudKitError.networkError
        }

        savedRecipes[record.recordID.recordName] = record
    }

    func fetchRecipe(recordName: String, from database: CKDatabase.Scope) async throws -> CKRecord? {
        fetchRecordCalled = true

        if shouldFailFetch {
            throw CloudKitError.networkError
        }

        return savedRecipes[recordName]
    }

    func deleteRecipe(recordName: String, from database: CKDatabase.Scope) async throws {
        deleteRecordCalled = true

        if shouldFailDelete {
            throw CloudKitError.networkError
        }

        let recordID = CKRecord.ID(recordName: recordName)
        deletedRecordIDs.insert(recordID)
        savedRecipes.removeValue(forKey: recordName)
    }

    // MARK: - User Operations

    func saveUser(_ record: CKRecord) async throws {
        saveRecordCalled = true

        if shouldFailSave {
            throw CloudKitError.networkError
        }

        savedUsers[record.recordID.recordName] = record
    }

    func fetchUser(recordName: String) async throws -> CKRecord? {
        fetchRecordCalled = true

        if shouldFailFetch {
            throw CloudKitError.networkError
        }

        return savedUsers[recordName]
    }

    // MARK: - Collection Operations

    func saveCollection(_ collection: Collection) async throws {
        saveRecordCalled = true

        if shouldFailSave {
            throw CloudKitError.networkError
        }

        savedCollections[collection.id] = collection
    }

    func fetchCollections(forUserId userId: UUID) async throws -> [Collection] {
        fetchRecordCalled = true

        if shouldFailFetch {
            throw CloudKitError.networkError
        }

        return Array(savedCollections.values).filter { $0.userId == userId }
    }

    func deleteCollection(_ collectionId: UUID) async throws {
        deleteRecordCalled = true

        if shouldFailDelete {
            throw CloudKitError.networkError
        }

        deletedCollectionIDs.insert(collectionId)
        savedCollections.removeValue(forKey: collectionId)
    }

    // MARK: - Test Helpers

    func reset() {
        savedRecipes.removeAll()
        savedCollections.removeAll()
        savedUsers.removeAll()
        savedConnections.removeAll()
        deletedRecordIDs.removeAll()
        deletedCollectionIDs.removeAll()

        shouldFailAccountCheck = false
        shouldFailSave = false
        shouldFailFetch = false
        shouldFailDelete = false
        accountStatus = .available

        checkAccountStatusCalled = false
        saveRecordCalled = false
        fetchRecordCalled = false
        deleteRecordCalled = false
    }
}
