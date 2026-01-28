//
//  CloudKitCore.swift
//  Cauldron
//
//  Shared CloudKit infrastructure actor providing common functionality
//  for all domain-specific CloudKit services.
//

import Foundation
import CloudKit
import os
#if canImport(UIKit)
import UIKit
#endif

// NOTE: CloudKitAccountStatus and CloudKitError are defined in CloudKitTypes.swift

/// Shared CloudKit infrastructure providing common functionality
/// for all domain-specific CloudKit services.
///
/// This actor manages:
/// - CloudKit container and database access
/// - Custom zone management for private database
/// - Account status checking
/// - Image optimization for CloudKit uploads
///
/// Domain-specific services (RecipeCloudService, UserCloudService, etc.)
/// depend on this actor for shared infrastructure.
actor CloudKitCore {
    // MARK: - Properties

    internal let container: CKContainer?
    private let _privateDatabase: CKDatabase?
    private let _publicDatabase: CKDatabase?
    internal let logger = Logger(subsystem: "com.cauldron", category: "CloudKitCore")

    /// Track if CloudKit is enabled/available
    private var isEnabled: Bool = false

    /// Cache for custom zone
    internal var customZone: CKRecordZone?

    // MARK: - Constants

    /// Custom zone name for private database
    internal let customZoneName = "CauldronZone"

    /// CloudKit record type constants
    enum RecordType {
        static let user = "User"
        static let recipe = "Recipe"
        static let sharedRecipe = "SharedRecipe"
        static let collection = "Collection"
        static let connection = "Connection"
        static let profileImage = "ProfileImage"
        static let referralSignup = "ReferralSignup"
    }

    // MARK: - Initialization

    init() {
        // CloudKit will SIGTRAP if entitlements are missing (common in CI tests).
        // Skip CloudKit initialization in tests/CI to avoid crashing the test host app.
        let env = ProcessInfo.processInfo.environment
        let isRunningTests = env["XCTestConfigurationFilePath"] != nil
        let isCI = env["CI"] == "true"
        if isRunningTests || isCI {
            self.container = nil
            self._privateDatabase = nil
            self._publicDatabase = nil
            self.isEnabled = false
            logger.notice("CloudKit disabled for tests/CI environment")
            return
        }

        // Use explicit container identifier to support multiple bundle IDs (dev/production)
        // This must match the container in the entitlements file
        let container = CKContainer(identifier: "iCloud.Nadav.Cauldron")
        self.container = container
        self._privateDatabase = container.privateCloudDatabase
        self._publicDatabase = container.publicCloudDatabase
        self.isEnabled = true
    }

    // MARK: - Account Status

    /// Check if the user is signed into iCloud and has CloudKit access
    func checkAccountStatus() async -> CloudKitAccountStatus {
        guard isEnabled, let container = container else {
            logger.warning("CloudKit not enabled")
            return .couldNotDetermine
        }

        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                return .available
            case .noAccount:
                return .noAccount
            case .restricted:
                return .restricted
            case .temporarilyUnavailable:
                return .temporarilyUnavailable
            case .couldNotDetermine:
                return .couldNotDetermine
            @unknown default:
                return .couldNotDetermine
            }
        } catch {
            logger.error("Error checking account status: \(error.localizedDescription)")
            return .couldNotDetermine
        }
    }

    /// Helper to check if CloudKit is available (bool)
    func isAvailable() async -> Bool {
        let status = await checkAccountStatus()
        return status.isAvailable
    }

    // MARK: - Database Access

    /// Check if CloudKit is enabled
    internal func checkEnabled() throws {
        guard isEnabled, let _ = container else {
            throw CloudKitError.notEnabled
        }
    }

    /// Get the private database
    func getPrivateDatabase() throws -> CKDatabase {
        try checkEnabled()
        guard let privateDatabase = _privateDatabase else {
            throw CloudKitError.notEnabled
        }
        return privateDatabase
    }

    /// Get the public database
    func getPublicDatabase() throws -> CKDatabase {
        try checkEnabled()
        guard let publicDatabase = _publicDatabase else {
            throw CloudKitError.notEnabled
        }
        return publicDatabase
    }

    /// Get the CKContainer
    func getContainer() throws -> CKContainer {
        try checkEnabled()
        guard let container = container else {
            throw CloudKitError.notEnabled
        }
        return container
    }

    /// Get the current user's record ID from CloudKit
    func getCurrentUserRecordID() async throws -> CKRecord.ID {
        let container = try getContainer()
        return try await container.userRecordID()
    }

    // MARK: - Custom Zone Management

    /// Create or fetch the custom zone (required for sharing)
    internal func ensureCustomZone() async throws -> CKRecordZone {
        // Return cached zone if available
        if let zone = customZone {
            return zone
        }

        let db = try getPrivateDatabase()

        do {
            // Check if zone exists
            let zoneID = CKRecordZone.ID(zoneName: customZoneName, ownerName: CKCurrentUserDefaultName)
            let zones = try await db.allRecordZones()

            if let existingZone = zones.first(where: { $0.zoneID == zoneID }) {
                self.customZone = existingZone
                return existingZone
            }

            // Create new zone
            let newZone = CKRecordZone(zoneName: customZoneName)
            let savedZone = try await db.save(newZone)
            self.customZone = savedZone
            logger.info("Created custom CloudKit zone: \(self.customZoneName)")
            return savedZone
        } catch {
            logger.error("Failed to ensure custom zone: \(error.localizedDescription)")
            throw error
        }
    }

    /// Get the custom zone ID
    func getCustomZoneID() async throws -> CKRecordZone.ID {
        let zone = try await ensureCustomZone()
        return zone.zoneID
    }

    // MARK: - Image Optimization

    /// Optimize image data for CloudKit upload
    /// - Parameter imageData: Original image data
    /// - Returns: Optimized image data
    /// - Throws: CloudKitError if optimization fails or image is too large
    func optimizeImageForCloudKit(_ imageData: Data) async throws -> Data {
        #if canImport(UIKit)
        guard let image = UIImage(data: imageData) else {
            throw CloudKitError.compressionFailed
        }

        let maxSizeBytes = 10_000_000 // 10MB max for CloudKit
        let compressionThreshold = 5_000_000 // 5MB - compress if larger

        // Try 80% quality compression first
        if let data = image.jpegData(compressionQuality: 0.8) {
            if data.count <= compressionThreshold {
                return data
            }
            if data.count <= maxSizeBytes {
                return data
            }
        }

        // Try 60% compression
        if let compressedData = image.jpegData(compressionQuality: 0.6),
           compressedData.count <= maxSizeBytes {
            return compressedData
        }

        // If still too large, resize and compress
        let maxDimension: CGFloat = 2000
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)

        if scale < 1.0 {
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            if let resizedImage = resizedImage,
               let compressedData = resizedImage.jpegData(compressionQuality: 0.8),
               compressedData.count <= maxSizeBytes {
                return compressedData
            }
        }

        throw CloudKitError.assetTooLarge
        #else
        // macOS or other platforms
        throw CloudKitError.compressionFailed
        #endif
    }

    /// Optimize image for specific max dimension (for profile/collection images)
    /// - Parameters:
    ///   - imageData: Original image data
    ///   - maxDimension: Maximum width/height
    ///   - targetSize: Target file size in bytes
    /// - Returns: Optimized image data
    func optimizeImageForCloudKit(
        _ imageData: Data,
        maxDimension: CGFloat,
        targetSize: Int
    ) async throws -> Data {
        #if canImport(UIKit)
        guard let image = UIImage(data: imageData) else {
            throw CloudKitError.compressionFailed
        }

        let maxSizeBytes = 10_000_000 // 10MB absolute max for CloudKit

        // Resize to max dimension
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)

        var processedImage = image
        if scale < 1.0 {
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            if let resizedImage = UIGraphicsGetImageFromCurrentImageContext() {
                processedImage = resizedImage
            }
            UIGraphicsEndImageContext()
        }

        // Try 80% quality compression first
        if let data = processedImage.jpegData(compressionQuality: 0.8) {
            if data.count <= targetSize {
                return data
            }
        }

        // Try 60% compression
        if let compressedData = processedImage.jpegData(compressionQuality: 0.6),
           compressedData.count <= maxSizeBytes {
            return compressedData
        }

        // Try 40% compression as last resort
        if let compressedData = processedImage.jpegData(compressionQuality: 0.4),
           compressedData.count <= maxSizeBytes {
            return compressedData
        }

        throw CloudKitError.compressionFailed
        #else
        throw CloudKitError.compressionFailed
        #endif
    }
}
