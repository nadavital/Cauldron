//
//  CloudKitService.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import CloudKit
import os
#if canImport(UIKit)
import UIKit
#endif

/// Account status for iCloud/CloudKit
enum CloudKitAccountStatus: CustomStringConvertible {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
    
    var isAvailable: Bool {
        return self == .available
    }
    
    var description: String {
        switch self {
        case .available:
            return "available"
        case .noAccount:
            return "noAccount"
        case .restricted:
            return "restricted"
        case .couldNotDetermine:
            return "couldNotDetermine"
        case .temporarilyUnavailable:
            return "temporarilyUnavailable"
        }
    }
}

/// Service for syncing data with CloudKit
/// Note: CloudKit capability must be enabled in Xcode for this to work
actor CloudKitService {
    internal let container: CKContainer?
    private let privateDatabase: CKDatabase?
    private let publicDatabase: CKDatabase?
    internal let logger = Logger(subsystem: "com.cauldron", category: "CloudKitService")
    
    // Track if CloudKit is enabled/available
    private var isEnabled: Bool = false
    
    // Cache for custom zone
    internal var customZone: CKRecordZone?
    
    // Constants
    internal let customZoneName = "CauldronZone"
    internal let userRecordType = "User"  // PUBLIC database
    internal let recipeRecordType = "Recipe"
    internal let sharedRecipeRecordType = "SharedRecipe"  // PUBLIC database
    internal let collectionRecordType = "Collection"  // PUBLIC database
    internal let collectionReferenceRecordType = "CollectionReference"  // PUBLIC database
    internal let connectionRecordType = "Connection" // PUBLIC database

    init() {
        // Try to initialize CloudKit, but don't crash if it fails
        do {
            // Use explicit container identifier to support multiple bundle IDs (dev/production)
            // This must match the container in the entitlements file
            let container = CKContainer(identifier: "iCloud.Nadav.Cauldron")
            self.container = container
            self.privateDatabase = container.privateCloudDatabase
            self.publicDatabase = container.publicCloudDatabase
            self.isEnabled = true
        } catch {
            logger.error("Failed to initialize CloudKit: \(error.localizedDescription)")
            self.container = nil
            self.privateDatabase = nil
            self.publicDatabase = nil
            self.isEnabled = false
        }
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
    
    // MARK: - Helper

    internal func checkEnabled() throws {
        guard isEnabled, let _ = container else {
            throw CloudKitError.notEnabled
        }
    }

    func getPrivateDatabase() throws -> CKDatabase {
        try checkEnabled()
        guard let privateDatabase = privateDatabase else {
            throw CloudKitError.notEnabled
        }
        return privateDatabase
    }

    func getPublicDatabase() throws -> CKDatabase {
        try checkEnabled()
        guard let publicDatabase = publicDatabase else {
            throw CloudKitError.notEnabled
        }
        return publicDatabase
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
    
    // MARK: - Image Optimization
    
    /// Optimize image data for CloudKit upload
    /// - Parameter imageData: Original image data
    /// - Returns: Optimized image data
    /// - Throws: CloudKitError if optimization fails or image is too large
    internal func optimizeImageForCloudKit(_ imageData: Data) async throws -> Data {
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
}

// MARK: - Errors

enum CloudKitError: LocalizedError {
    case invalidRecord
    case notAuthenticated
    case permissionDenied
    case notEnabled
    case accountNotAvailable(CloudKitAccountStatus)
    case networkError
    case quotaExceeded
    case syncConflict
    case assetNotFound
    case assetTooLarge
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .invalidRecord:
            return "Invalid CloudKit record"
        case .notAuthenticated:
            return "Not signed in to iCloud"
        case .permissionDenied:
            return "Permission denied"
        case .notEnabled:
            return "CloudKit is not enabled. Please enable CloudKit capability in Xcode project settings."
        case .accountNotAvailable(let status):
            switch status {
            case .noAccount:
                return "Please sign in to iCloud in Settings to use cloud features"
            case .restricted:
                return "iCloud access is restricted on this device"
            case .temporarilyUnavailable:
                return "iCloud is temporarily unavailable. Please try again later"
            default:
                return "Could not verify iCloud account status"
            }
        case .networkError:
            return "Network connection error. Please check your internet connection"
        case .quotaExceeded:
            return "iCloud storage is full. Please free up space in Settings"
        case .syncConflict:
            return "Sync conflict detected. Your changes may need to be merged manually"
        case .assetNotFound:
            return "Image not found in iCloud"
        case .assetTooLarge:
            return "Image is too large to upload (max 10MB)"
        case .compressionFailed:
            return "Failed to compress image for upload"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .accountNotAvailable(.noAccount):
            return "Go to Settings > [Your Name] > iCloud to sign in"
        case .accountNotAvailable(.restricted):
            return "Check Settings > Screen Time > Content & Privacy Restrictions"
        case .notEnabled:
            return "This is a developer configuration issue"
        case .quotaExceeded:
            return "Go to Settings > [Your Name] > iCloud > Manage Storage"
        case .networkError:
            return "Check your Wi-Fi or cellular connection"
        default:
            return nil
        }
    }
}
