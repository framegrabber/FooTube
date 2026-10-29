@testable import FooTubeCore
import Foundation
import Security
import Synchronization
import Testing

/// One generic password item in memory, answering like `SecItem*` for the queries
/// `KeychainTokenStorage` makes: the real Keychain's data protection, backups and migration to
/// another device can't be observed from `swift test`.
private final class FakeKeychain: KeychainItems {
    struct Item: Equatable {
        var data: Data
        var accessible: String
    }

    private let state = Mutex<(item: Item?, updates: [[String: String]], failUpdates: Bool)>((nil, [], false))

    var item: Item? {
        get { state.withLock { $0.item } }
        set { state.withLock { $0.item = newValue } }
    }

    /// The attributes each `SecItemUpdate` changed (data shown as `<data>`).
    var updates: [[String: String]] {
        state.withLock { $0.updates }
    }

    func failUpdates() {
        state.withLock { $0.failUpdates = true }
    }

    func copyMatching(_ query: [CFString: Any]) -> (status: OSStatus, result: CFTypeRef?) {
        guard let item else { return (errSecItemNotFound, nil) }
        let wantsData = query[kSecReturnData] as? Bool == true
        guard query[kSecReturnAttributes] as? Bool == true else {
            return (errSecSuccess, wantsData ? item.data as CFData : nil)
        }
        var attributes: [String: Any] = [kSecAttrAccessible as String: item.accessible]
        if wantsData {
            attributes[kSecValueData as String] = item.data
        }
        return (errSecSuccess, attributes as CFDictionary)
    }

    func update(_: [CFString: Any], _ attributes: [CFString: Any]) -> OSStatus {
        state.withLock { state in
            guard var item = state.item else { return errSecItemNotFound }
            guard !state.failUpdates else { return errSecInteractionNotAllowed }
            var changed: [String: String] = [:]
            if let data = attributes[kSecValueData] as? Data {
                item.data = data
                changed["data"] = "<data>"
            }
            if let accessible = attributes[kSecAttrAccessible] as? String {
                item.accessible = accessible
                changed["accessible"] = accessible
            }
            state.item = item
            state.updates.append(changed)
            return errSecSuccess
        }
    }

    func add(_ attributes: [CFString: Any]) -> OSStatus {
        state.withLock { state in
            guard state.item == nil else { return errSecDuplicateItem }
            state.item = Item(
                data: attributes[kSecValueData] as? Data ?? Data(),
                accessible: attributes[kSecAttrAccessible] as? String ?? kSecAttrAccessibleWhenUnlocked as String,
            )
            return errSecSuccess
        }
    }

    func delete(_: [CFString: Any]) -> OSStatus {
        state.withLock { state in
            defer { state.item = nil }
            return state.item == nil ? errSecItemNotFound : errSecSuccess
        }
    }
}

@Suite("Keychain token storage")
struct KeychainTokenStorageTests {
    let thisDeviceOnly = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
    private let keychain = FakeKeychain()
    let token = String(repeating: "t", count: 64)

    private var storage: KeychainTokenStorage {
        KeychainTokenStorage(service: "test.sync", account: "token", keychain: keychain)
    }

    @Test func `a saved token stays on this device: readable after first unlock, not in backups`() throws {
        try storage.save(token)
        #expect(keychain.item == FakeKeychain.Item(data: Data(token.utf8), accessible: thisDeviceOnly))
        #expect(try storage.load() == token)

        let rotated = String(repeating: "r", count: 64)
        try storage.save(rotated)
        #expect(keychain.item == FakeKeychain.Item(data: Data(rotated.utf8), accessible: thisDeviceOnly))
    }

    @Test func `a token saved by an older build moves to this device only on the first load, once`() throws {
        keychain.item = FakeKeychain.Item(data: Data(token.utf8), accessible: kSecAttrAccessibleAfterFirstUnlock as String)
        #expect(try storage.load() == token)
        #expect(keychain.item == FakeKeychain.Item(data: Data(token.utf8), accessible: thisDeviceOnly))
        #expect(try storage.load() == token)
        #expect(keychain.updates == [["accessible": thisDeviceOnly]])
    }

    @Test func `a failed move keeps the token usable and tries again next time`() throws {
        keychain.item = FakeKeychain.Item(data: Data(token.utf8), accessible: kSecAttrAccessibleAfterFirstUnlock as String)
        keychain.failUpdates()
        #expect(try storage.load() == token)
        #expect(keychain.item?.accessible == kSecAttrAccessibleAfterFirstUnlock as String)
    }

    @Test func `removing deletes the item; nothing saved loads as nil`() throws {
        try storage.save(token)
        try storage.remove()
        #expect(keychain.item == nil)
        #expect(try storage.load() == nil)
        try storage.remove()
    }
}
