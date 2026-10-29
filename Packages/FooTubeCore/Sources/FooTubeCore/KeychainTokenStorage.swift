import Foundation
import os
import Security

/// Where `SyncConfigurationStore` keeps the sync token; tests inject an in-memory one.
public protocol SyncTokenStorage: Sendable {
    func load() throws(SyncConfigurationError) -> String?
    func save(_ token: String) throws(SyncConfigurationError)
    /// No error when there is nothing to remove.
    func remove() throws(SyncConfigurationError)
}

/// The Security framework calls `KeychainTokenStorage` makes; tests substitute an in-memory keychain
/// to check the attributes it writes.
protocol KeychainItems: Sendable {
    func copyMatching(_ query: [CFString: Any]) -> (status: OSStatus, result: CFTypeRef?)
    func update(_ query: [CFString: Any], _ attributes: [CFString: Any]) -> OSStatus
    func add(_ attributes: [CFString: Any]) -> OSStatus
    func delete(_ query: [CFString: Any]) -> OSStatus
}

struct SystemKeychain: KeychainItems {
    func copyMatching(_ query: [CFString: Any]) -> (status: OSStatus, result: CFTypeRef?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }

    func update(_ query: [CFString: Any], _ attributes: [CFString: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func add(_ attributes: [CFString: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func delete(_ query: [CFString: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

/// The sync token as a generic password item of this app (default access group, so no other app
/// reads it), readable after the first unlock so background syncs work, and only on this device: it
/// is left out of backups and doesn't move to another device with them.
public struct KeychainTokenStorage: SyncTokenStorage {
    private let service: String
    private let account: String
    private let keychain: any KeychainItems
    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "sync")

    /// Readable after the first unlock (background syncs), never restored from a backup elsewhere.
    static var accessibility: CFString {
        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    }

    public init(service: String = "\(Bundle.main.bundleIdentifier ?? AppInfo.name).sync", account: String = "token") {
        self.init(service: service, account: account, keychain: SystemKeychain())
    }

    init(service: String, account: String, keychain: any KeychainItems) {
        self.service = service
        self.account = account
        self.keychain = keychain
    }

    private var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    /// Also moves an item saved by an older build (`kSecAttrAccessibleAfterFirstUnlock`, which went into
    /// backups) to `accessibility`, once: a failed update keeps the item usable and tries again at the
    /// next load.
    public func load() throws(SyncConfigurationError) -> String? {
        var search = query
        search[kSecReturnData] = true
        search[kSecReturnAttributes] = true
        search[kSecMatchLimit] = kSecMatchLimitOne
        let (status, result) = keychain.copyMatching(search)
        switch status {
        case errSecSuccess:
            let item = result as? [String: Any] ?? [:]
            if item[kSecAttrAccessible as String] as? String != Self.accessibility as String {
                let update = keychain.update(query, [kSecAttrAccessible: Self.accessibility])
                if update != errSecSuccess {
                    logger.error("Sync token stays readable from backups for now: Keychain update failed (OSStatus \(update))")
                }
            }
            return (item[kSecValueData as String] as? Data).flatMap { String(data: $0, encoding: .utf8) }
        case errSecItemNotFound:
            return nil
        default:
            throw .keychain(status: status)
        }
    }

    public func save(_ token: String) throws(SyncConfigurationError) {
        let attributes: [CFString: Any] = [
            kSecValueData: Data(token.utf8),
            kSecAttrAccessible: Self.accessibility,
        ]
        var status = keychain.update(query, attributes)
        if status == errSecItemNotFound {
            status = keychain.add(query.merging(attributes) { $1 })
        }
        guard status == errSecSuccess else { throw .keychain(status: status) }
    }

    public func remove() throws(SyncConfigurationError) {
        let status = keychain.delete(query)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw .keychain(status: status) }
    }
}
