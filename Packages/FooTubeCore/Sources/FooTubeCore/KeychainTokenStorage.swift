import Foundation
import Security

/// Where `SyncConfigurationStore` keeps the sync token; tests inject an in-memory one.
public protocol SyncTokenStorage: Sendable {
    func load() throws(SyncConfigurationError) -> String?
    func save(_ token: String) throws(SyncConfigurationError)
    /// No error when there is nothing to remove.
    func remove() throws(SyncConfigurationError)
}

/// The sync token as a generic password item of this app (default access group, so no other app
/// reads it), readable after the first unlock so background syncs work.
public struct KeychainTokenStorage: SyncTokenStorage {
    private let service: String
    private let account: String

    public init(service: String = "\(Bundle.main.bundleIdentifier ?? AppInfo.name).sync", account: String = "token") {
        self.service = service
        self.account = account
    }

    private var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    public func load() throws(SyncConfigurationError) -> String? {
        var search = query
        search[kSecReturnData] = true
        search[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return (result as? Data).flatMap { String(data: $0, encoding: .utf8) }
        case errSecItemNotFound:
            return nil
        default:
            throw .keychain(status: status)
        }
    }

    public func save(_ token: String) throws(SyncConfigurationError) {
        let attributes: [CFString: Any] = [
            kSecValueData: Data(token.utf8),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw .keychain(status: status) }
    }

    public func remove() throws(SyncConfigurationError) {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw .keychain(status: status) }
    }
}
