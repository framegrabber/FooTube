import FooTubeCore
import Foundation
import Synchronization
import Testing

/// Token storage in memory, so tests never touch the real Keychain.
private final class MemoryTokenStorage: SyncTokenStorage {
    private let state = Mutex<(token: String?, failure: Int32?)>((nil, nil))

    var token: String? {
        state.withLock { $0.token }
    }

    /// Makes every following call fail with this `OSStatus`.
    func fail(with status: Int32) {
        state.withLock { $0.failure = status }
    }

    func load() throws(SyncConfigurationError) -> String? {
        try state.withLock { state throws(SyncConfigurationError) in
            if let status = state.failure {
                throw .keychain(status: status)
            }
            return state.token
        }
    }

    func save(_ token: String) throws(SyncConfigurationError) {
        try state.withLock { state throws(SyncConfigurationError) in
            if let status = state.failure {
                throw .keychain(status: status)
            }
            state.token = token
        }
    }

    func remove() throws(SyncConfigurationError) {
        try state.withLock { state throws(SyncConfigurationError) in
            if let status = state.failure {
                throw .keychain(status: status)
            }
            state.token = nil
        }
    }
}

@Suite("Sync configuration")
struct SyncConfigurationTests {
    let defaults: UserDefaults
    private let tokens = MemoryTokenStorage()
    /// 64 characters, like `openssl rand -base64 48`.
    let token = Data((0 ..< 48).map { _ in UInt8.random(in: 0 ... 255) }).base64EncodedString()
    let workerURL = "https://footube-sync.household.workers.dev"

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "SyncConfigurationTests-\(UUID().uuidString)"))
    }

    private var store: SyncConfigurationStore {
        SyncConfigurationStore(defaults: defaults, tokens: tokens)
    }

    private func configure() throws {
        try store.applyLaunchArguments(["syncURL": workerURL, "syncToken": token])
    }

    /// Runs `operation` and returns the error it threw, or nil.
    private func configurationError(_ operation: () throws(SyncConfigurationError) -> some Any) -> SyncConfigurationError? {
        do {
            _ = try operation()
            return nil
        } catch {
            return error
        }
    }

    // MARK: Configuring

    @Test func `valid arguments are saved: URL in UserDefaults, token only in the token storage`() throws {
        #expect(try store.applyLaunchArguments(["syncURL": workerURL, "syncToken": token]) == .configured)
        let configuration = try #require(store.load())
        #expect(configuration.url.absoluteString == workerURL)
        #expect(configuration.token == token)
        #expect(tokens.token == token)
        #expect(defaults.string(forKey: "sync.url.v1") == workerURL)
        #expect(defaults.object(forKey: "syncURL") == nil)
        #expect(!defaults.dictionaryRepresentation().values.contains { ($0 as? String)?.contains(token) == true })
    }

    @Test func `a relaunch without arguments keeps the saved configuration`() throws {
        try configure()
        let relaunched = SyncConfigurationStore(defaults: defaults, tokens: tokens)
        #expect(try relaunched.applyLaunchArguments([:]) == .none)
        #expect(relaunched.load()?.url.absoluteString == workerURL)
        #expect(relaunched.load()?.token == token)
    }

    @Test func `new arguments replace the saved configuration`() throws {
        try configure()
        let other = Data((0 ..< 48).map { _ in UInt8.random(in: 0 ... 255) }).base64EncodedString()
        #expect(try store.applyLaunchArguments(["syncURL": "https://other.example.dev", "syncToken": other]) == .configured)
        #expect(store.load()?.url.absoluteString == "https://other.example.dev")
        #expect(store.load()?.token == other)
    }

    @Test func `nothing configured means sync is off`() throws {
        #expect(try store.applyLaunchArguments(["play": "aqz-KE-bpKQ"]) == .none)
        #expect(store.load() == nil)
    }

    @Test func `a URL without its token in the Keychain is off`() throws {
        try configure()
        try tokens.remove()
        #expect(store.load() == nil)
    }

    @Test(arguments: ["http://localhost:8787", "http://127.0.0.1:8787", "HTTP://LOCALHOST:8790/", "https://sync.example.org/footube"])
    func `https and local http URLs are accepted`(url: String) throws {
        #expect(try store.applyLaunchArguments(["syncURL": url, "syncToken": token]) == .configured)
        #expect(store.load()?.url.absoluteString == url)
    }

    // MARK: Rejecting

    @Test(arguments: ["http://footube-sync.household.workers.dev", "http://192.168.1.20:8787", "ftp://localhost", "file:///tmp/sync", "localhost:8787", "https://", "wss://localhost"])
    func `other URLs are rejected and the old configuration stays`(url: String) throws {
        try configure()
        let error = configurationError { () throws(SyncConfigurationError) in
            try store.applyLaunchArguments(["syncURL": url, "syncToken": token])
        }
        guard case .invalidURL = error else {
            Issue.record("expected invalidURL, got \(String(describing: error))")
            return
        }
        #expect(store.load()?.url.absoluteString == workerURL)
        #expect(store.load()?.token == token)
    }

    @Test func `a token shorter than 64 characters is rejected and the old configuration stays`() throws {
        try configure()
        let short = String(token.dropLast())
        #expect(configurationError { () throws(SyncConfigurationError) in
            try store.applyLaunchArguments(["syncURL": "https://other.example.dev", "syncToken": short])
        } == .tokenTooShort(length: 63))
        #expect(store.load()?.url.absoluteString == workerURL)
        #expect(tokens.token == token)
    }

    @Test(arguments: [" ", "\n", "ä", "\u{7F}"])
    func `a token that would break the Authorization header is rejected`(character: String) {
        #expect(configurationError { () throws(SyncConfigurationError) in
            try store.applyLaunchArguments(["syncURL": workerURL, "syncToken": token + character])
        } == .tokenNotHeaderSafe)
        #expect(store.load() == nil)
    }

    @Test(arguments: [["syncURL": "https://sync.example.org"], ["syncToken": "x"]])
    func `URL and token only come together`(arguments: [String: String]) throws {
        try configure()
        #expect(configurationError { () throws(SyncConfigurationError) in try store.applyLaunchArguments(arguments) } == .incompleteArguments)
        #expect(store.load()?.token == token)
    }

    @Test func `a Keychain failure leaves the old configuration`() throws {
        try configure()
        tokens.fail(with: -25308)
        #expect(configurationError { () throws(SyncConfigurationError) in
            try store.applyLaunchArguments(["syncURL": "https://other.example.dev", "syncToken": token])
        } == .keychain(status: -25308))
        #expect(defaults.string(forKey: "sync.url.v1") == workerURL)
        #expect(tokens.token == token)
    }

    // MARK: Reset

    @Test func `reset removes URL, token and sync state but keeps local data`() throws {
        try configure()
        defaults.set(Data("{}".utf8), forKey: "sync.state.v1")
        defaults.set(Data("{}".utf8), forKey: "subscriptions.v2")
        #expect(try store.applyLaunchArguments(["syncReset": "YES"]) == .reset)
        #expect(store.load() == nil)
        #expect(tokens.token == nil)
        #expect(defaults.object(forKey: "sync.url.v1") == nil)
        #expect(defaults.object(forKey: "sync.state.v1") == nil)
        #expect(defaults.object(forKey: "subscriptions.v2") != nil)
    }

    @Test func `syncReset NO changes nothing`() throws {
        try configure()
        #expect(try store.applyLaunchArguments(["syncReset": "NO"]) == .none)
        #expect(store.load()?.token == token)
    }

    @Test func `reset with new arguments starts over with the new configuration`() throws {
        try configure()
        defaults.set(Data("{}".utf8), forKey: "sync.state.v1")
        #expect(try store.applyLaunchArguments(["syncReset": "YES", "syncURL": "http://localhost:8787", "syncToken": token]) == .configured)
        #expect(store.load()?.url.absoluteString == "http://localhost:8787")
        #expect(defaults.object(forKey: "sync.state.v1") == nil)
    }

    @Test func `reset with invalid arguments changes nothing`() throws {
        try configure()
        defaults.set(Data("{}".utf8), forKey: "sync.state.v1")
        #expect(configurationError { () throws(SyncConfigurationError) in
            try store.applyLaunchArguments(["syncReset": "YES", "syncURL": "http://example.com", "syncToken": token])
        } != nil)
        #expect(store.load()?.token == token)
        #expect(defaults.object(forKey: "sync.state.v1") != nil)
    }

    // MARK: Token secrecy

    @Test func `errors never contain the token`() throws {
        let secret = token + " tail"
        let attempts: [[String: String]] = [
            ["syncURL": workerURL, "syncToken": secret],
            ["syncURL": workerURL, "syncToken": String(token.prefix(40))],
            ["syncURL": "http://example.com/\(token)", "syncToken": token],
            ["syncToken": token],
        ]
        for arguments in attempts {
            let error = try #require(configurationError { () throws(SyncConfigurationError) in try store.applyLaunchArguments(arguments) })
            for text in [error.message, String(describing: error), String(reflecting: error), error.localizedDescription] {
                #expect(!text.contains(String(token.prefix(40))), "token leaked: \(error.message)")
            }
        }
    }

    @Test func `a configuration's descriptions and mirror redact the token`() throws {
        let configuration = try SyncConfiguration(url: #require(URL(string: workerURL)), token: token)
        var dumped = ""
        dump(configuration, to: &dumped)
        for text in [String(describing: configuration), String(reflecting: configuration), "\(configuration)", dumped] {
            #expect(!text.contains(token))
            #expect(text.contains("footube-sync.household.workers.dev"))
        }
    }
}
