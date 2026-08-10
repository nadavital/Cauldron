import Foundation
import Security

enum ShareCapabilityError: Error {
    case keychain(OSStatus)
    case randomGeneration(OSStatus)
    case invalidStoredValue
}

/// Stores the private capability used to manage a user's public web snapshots.
/// The value is synchronized through iCloud Keychain when available and is never
/// included in public links or Firestore responses.
@MainActor
final class ShareCapabilityStore {
    static let shared = ShareCapabilityStore()

    private let service = "com.cauldron.public-recipe-sharing"

    func capability(for ownerID: UUID) throws -> String {
        let account = ownerID.uuidString.lowercased()
        if let existing = try read(account: account) {
            return existing
        }

        let capability = try generateCapability()
        try cacheCapability(capability, for: ownerID)
        return capability
    }

    func generateCapability() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let randomStatus = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            throw ShareCapabilityError.randomGeneration(randomStatus)
        }

        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func cacheCapability(_ capability: String, for ownerID: UUID) throws {
        guard !capability.isEmpty else { throw ShareCapabilityError.invalidStoredValue }
        let account = ownerID.uuidString.lowercased()
        if let existing = try read(account: account), existing == capability {
            return
        }
        try removeCapability(for: ownerID)
        try store(capability, account: account)
    }

    func removeCapability(for ownerID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ownerID.uuidString.lowercased(),
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ShareCapabilityError.keychain(status)
        }
    }

    private func read(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw ShareCapabilityError.keychain(status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            throw ShareCapabilityError.invalidStoredValue
        }
        return value
    }

    private func store(_ capability: String, account: String) throws {
        let data = Data(capability.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        var synchronizedQuery = baseQuery
        synchronizedQuery[kSecAttrSynchronizable as String] = true
        let status = SecItemAdd(synchronizedQuery as CFDictionary, nil)

        if status == errSecDuplicateItem, let existing = try read(account: account), existing == capability {
            return
        }
        guard status == errSecSuccess else {
            throw ShareCapabilityError.keychain(status)
        }
    }
}
