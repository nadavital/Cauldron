//
//  CloudKitTypes.swift
//  Cauldron
//
//  Shared CloudKit type definitions used across all CloudKit services.
//

import Foundation

/// Account status for iCloud/CloudKit
enum CloudKitAccountStatus: Sendable, CustomStringConvertible, Equatable {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine

    nonisolated var isAvailable: Bool {
        return self == .available
    }

    nonisolated var description: String {
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

    nonisolated static func == (lhs: CloudKitAccountStatus, rhs: CloudKitAccountStatus) -> Bool {
        switch (lhs, rhs) {
        case (.available, .available),
             (.noAccount, .noAccount),
             (.restricted, .restricted),
             (.temporarilyUnavailable, .temporarilyUnavailable),
             (.couldNotDetermine, .couldNotDetermine):
            return true
        default:
            return false
        }
    }
}

// MARK: - Errors

enum CloudKitError: Sendable, LocalizedError, Equatable {
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
    case userNotFound

    nonisolated var errorDescription: String? {
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
        case .userNotFound:
            return "User not found in CloudKit"
        }
    }

    nonisolated var recoverySuggestion: String? {
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

    nonisolated static func == (lhs: CloudKitError, rhs: CloudKitError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidRecord, .invalidRecord),
             (.notAuthenticated, .notAuthenticated),
             (.permissionDenied, .permissionDenied),
             (.notEnabled, .notEnabled),
             (.networkError, .networkError),
             (.quotaExceeded, .quotaExceeded),
             (.syncConflict, .syncConflict),
             (.assetNotFound, .assetNotFound),
             (.assetTooLarge, .assetTooLarge),
             (.compressionFailed, .compressionFailed),
             (.userNotFound, .userNotFound):
            return true
        case let (.accountNotAvailable(lhsStatus), .accountNotAvailable(rhsStatus)):
            return lhsStatus == rhsStatus
        default:
            return false
        }
    }
}
