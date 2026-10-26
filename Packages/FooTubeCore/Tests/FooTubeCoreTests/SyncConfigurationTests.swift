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
    /// Where a test drops the configuration file, like the run scripts drop it into the container.
    let file: URL

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "SyncConfigurationTests-\(UUID().uuidString)"))
        let directory = FileManager.default.temporaryDirectory.appending(path: "SyncConfigurationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appending(path: "footube-sync.json")
    }

    private var store: SyncConfigurationStore {
        SyncConfigurationStore(defaults: defaults, tokens: tokens)
    }

    private func drop(_ contents: [String: String]) throws {
        try JSONSerialization.data(withJSONObject: contents).write(to: file)
    }

    private func drop(url: String, token: String) throws {
        try drop(["url": url, "token": token])
    }

    @discardableResult
    private func apply(_ arguments: [String: String] = [:]) throws(SyncConfigurationError) -> SyncConfigurationStore.LaunchChange {
        try store.applyLaunchChanges(arguments: arguments, configurationFile: file)
    }

    private func configure() throws {
        try drop(url: workerURL, token: token)
        try apply()
    }

    private var fileExists: Bool {
        FileManager.default.fileExists(atPath: file.path)
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

    @Test func `a valid file is saved, URL in UserDefaults and token only in the token storage, and deleted`() throws {
        try drop(url: workerURL, token: token)
        #expect(try apply() == .configured)
        let configuration = try #require(store.load())
        #expect(configuration.url.absoluteString == workerURL)
        #expect(configuration.token == token)
        #expect(tokens.token == token)
        #expect(defaults.string(forKey: "sync.url.v1") == workerURL)
        #expect(!defaults.dictionaryRepresentation().values.contains { ($0 as? String)?.contains(token) == true })
        #expect(!fileExists)
    }

    @Test func `a launch without a file keeps the saved configuration`() throws {
        try configure()
        let relaunched = SyncConfigurationStore(defaults: defaults, tokens: tokens)
        #expect(try relaunched.applyLaunchChanges(arguments: [:], configurationFile: file) == .none)
        #expect(relaunched.load()?.url.absoluteString == workerURL)
        #expect(relaunched.load()?.token == token)
    }

    @Test func `a new file replaces the saved configuration`() throws {
        try configure()
        let other = Data((0 ..< 48).map { _ in UInt8.random(in: 0 ... 255) }).base64EncodedString()
        try drop(url: "https://other.example.dev", token: other)
        #expect(try apply() == .configured)
        #expect(store.load()?.url.absoluteString == "https://other.example.dev")
        #expect(store.load()?.token == other)
    }

    @Test func `nothing configured means sync is off`() throws {
        #expect(try apply(["play": "aqz-KE-bpKQ"]) == .none)
        #expect(store.load() == nil)
    }

    @Test func `a URL without its token in the Keychain is off`() throws {
        try configure()
        try tokens.remove()
        #expect(store.load() == nil)
    }

    @Test(arguments: ["http://localhost:8787", "http://127.0.0.1:8787", "HTTP://LOCALHOST:8790/", "https://sync.example.org/footube"])
    func `https and local http URLs are accepted`(url: String) throws {
        try drop(url: url, token: token)
        #expect(try apply() == .configured)
        #expect(store.load()?.url.absoluteString == url)
    }

    // MARK: Rejecting

    @Test(arguments: ["http://footube-sync.household.workers.dev", "http://192.168.1.20:8787", "ftp://localhost", "file:///tmp/sync", "localhost:8787", "https://", "wss://localhost"])
    func `other URLs are rejected, the file is deleted and the old configuration stays`(url: String) throws {
        try configure()
        try drop(url: url, token: token)
        let error = configurationError { () throws(SyncConfigurationError) in try apply() }
        guard case .invalidURL = error else {
            Issue.record("expected invalidURL, got \(String(describing: error))")
            return
        }
        #expect(!fileExists)
        #expect(store.load()?.url.absoluteString == workerURL)
        #expect(store.load()?.token == token)
    }

    @Test func `a token shorter than 64 characters is rejected and the old configuration stays`() throws {
        try configure()
        try drop(url: "https://other.example.dev", token: String(token.dropLast()))
        #expect(configurationError { () throws(SyncConfigurationError) in try apply() } == .tokenTooShort(length: 63))
        #expect(!fileExists)
        #expect(store.load()?.url.absoluteString == workerURL)
        #expect(tokens.token == token)
    }

    @Test(arguments: [" ", "\n", "ä", "\u{7F}"])
    func `a token that would break the Authorization header is rejected`(character: String) throws {
        try drop(url: workerURL, token: token + character)
        #expect(configurationError { () throws(SyncConfigurationError) in try apply() } == .tokenNotHeaderSafe)
        #expect(!fileExists)
        #expect(store.load() == nil)
    }

    @Test(arguments: [#"{"url":"https://sync.example.org"}"#, #"{"token":"x"}"#, #"{"url":1,"token":2}"#, "not json", ""])
    func `an unreadable file is rejected and deleted`(contents: String) throws {
        try configure()
        try Data(contents.utf8).write(to: file)
        #expect(configurationError { () throws(SyncConfigurationError) in try apply() } == .unreadableFile)
        #expect(!fileExists)
        #expect(store.load()?.token == token)
    }

    @Test func `a Keychain failure leaves the old configuration and still deletes the file`() throws {
        try configure()
        tokens.fail(with: -25308)
        try drop(url: "https://other.example.dev", token: token)
        #expect(configurationError { () throws(SyncConfigurationError) in try apply() } == .keychain(status: -25308))
        #expect(!fileExists)
        #expect(defaults.string(forKey: "sync.url.v1") == workerURL)
        #expect(tokens.token == token)
    }

    // MARK: Reset

    @Test func `reset removes URL, token and sync state but keeps local data`() throws {
        try configure()
        defaults.set(Data("{}".utf8), forKey: "sync.state.v1")
        defaults.set(Data("{}".utf8), forKey: "subscriptions.v2")
        #expect(try apply(["syncReset": "YES"]) == .reset)
        #expect(store.load() == nil)
        #expect(tokens.token == nil)
        #expect(defaults.object(forKey: "sync.url.v1") == nil)
        #expect(defaults.object(forKey: "sync.state.v1") == nil)
        #expect(defaults.object(forKey: "subscriptions.v2") != nil)
    }

    @Test func `syncReset NO changes nothing`() throws {
        try configure()
        #expect(try apply(["syncReset": "NO"]) == .none)
        #expect(store.load()?.token == token)
    }

    @Test func `reset with a new file starts over with the new configuration`() throws {
        try configure()
        defaults.set(Data("{}".utf8), forKey: "sync.state.v1")
        try drop(url: "http://localhost:8787", token: token)
        #expect(try apply(["syncReset": "YES"]) == .configured)
        #expect(store.load()?.url.absoluteString == "http://localhost:8787")
        #expect(defaults.object(forKey: "sync.state.v1") == nil)
    }

    @Test func `reset with an invalid file changes nothing`() throws {
        try configure()
        defaults.set(Data("{}".utf8), forKey: "sync.state.v1")
        try drop(url: "http://example.com", token: token)
        #expect(configurationError { () throws(SyncConfigurationError) in try apply(["syncReset": "YES"]) } != nil)
        #expect(store.load()?.token == token)
        #expect(defaults.object(forKey: "sync.state.v1") != nil)
    }

    // MARK: Token secrecy

    @Test func `errors never contain the token`() throws {
        let attempts: [[String: String]] = [
            ["url": workerURL, "token": token + " tail"],
            ["url": workerURL, "token": String(token.prefix(40))],
            ["url": "http://example.com/\(token)", "token": token],
            ["token": token],
        ]
        for contents in attempts {
            try drop(contents)
            let error = try #require(configurationError { () throws(SyncConfigurationError) in try apply() })
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
