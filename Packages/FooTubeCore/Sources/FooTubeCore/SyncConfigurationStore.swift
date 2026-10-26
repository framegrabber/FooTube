import Foundation
import os

/// Loads and saves the sync configuration: the Worker URL in `UserDefaults` (`sync.url.v1`), the
/// token in the Keychain. Configured by launch arguments (`scripts/run-sim.sh`/`run-device.sh` add
/// them from `FOOTUBE_SYNC_URL`/`FOOTUBE_SYNC_TOKEN`), so the token never enters the repository,
/// the bundle or the build settings:
/// - `-syncURL <url> -syncToken <token>`: both together; saved when valid, the old configuration is
///   kept otherwise.
/// - `-syncReset YES`: removes URL, token and the engine's sync state; local data stays.
///
/// Arguments are read from UserDefaults' argument domain only, and the URL is persisted under a
/// different key, so a later launch without arguments uses the saved configuration.
public struct SyncConfigurationStore {
    public enum LaunchChange: Hashable, Sendable {
        /// No sync arguments.
        case none
        /// A configuration from the arguments was saved (after a reset, if both were given).
        case configured
        /// `-syncReset YES` removed the configuration.
        case reset
    }

    /// The engine's bookkeeping (`lastSyncAt` per store, `SyncEngine.stateKey`).
    private static let stateKey = "sync.state.v1"
    private static let urlKey = "sync.url.v1"

    /// This launch's arguments (`-name value` pairs) as UserDefaults parsed them.
    public static var launchArguments: [String: Any] {
        UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
    }

    private let defaults: UserDefaults
    private let tokens: any SyncTokenStorage
    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "sync")

    public init(defaults: UserDefaults = .standard, tokens: any SyncTokenStorage = KeychainTokenStorage()) {
        self.defaults = defaults
        self.tokens = tokens
    }

    /// The saved configuration; nil when sync is off (URL or token missing, unreadable or invalid).
    public func load() -> SyncConfiguration? {
        guard let url = defaults.string(forKey: Self.urlKey).flatMap(URL.init(string:)) else { return nil }
        do {
            guard let token = try tokens.load() else { return nil }
            return try SyncConfiguration(url: url, token: token)
        } catch {
            logger.error("Saved sync configuration unusable: \(error.message, privacy: .public)")
            return nil
        }
    }

    /// Token first: if the Keychain fails, nothing changed.
    public func save(_ configuration: SyncConfiguration) throws(SyncConfigurationError) {
        try tokens.save(configuration.token)
        defaults.set(configuration.url.absoluteString, forKey: Self.urlKey)
    }

    /// Turns sync off: URL, token and sync state go; the stores' local data stays.
    public func reset() throws(SyncConfigurationError) {
        defaults.removeObject(forKey: Self.urlKey)
        defaults.removeObject(forKey: Self.stateKey)
        try tokens.remove()
    }

    /// Applies `-syncReset`, `-syncURL` and `-syncToken`. Validates before changing anything: on an
    /// error the previous configuration (and a requested reset) is left alone.
    @discardableResult
    public func applyLaunchArguments(_ arguments: [String: Any] = Self.launchArguments) throws(SyncConfigurationError) -> LaunchChange {
        let shouldReset = Self.isYes(arguments["syncReset"])
        let url = arguments["syncURL"] as? String
        let token = arguments["syncToken"] as? String
        var configuration: SyncConfiguration?
        switch (url, token) {
        case (nil, nil):
            break
        case let (url?, token?):
            guard let parsed = URL(string: url) else { throw .invalidURL("unparsable URL") }
            configuration = try SyncConfiguration(url: parsed, token: token)
        default:
            throw .incompleteArguments
        }
        if shouldReset {
            try reset()
            logger.info("Sync configuration reset by launch argument")
        }
        guard let configuration else { return shouldReset ? .reset : .none }
        try save(configuration)
        logger.info("Sync configured by launch arguments for \(configuration.url.host() ?? "", privacy: .public)")
        return .configured
    }

    private static func isYes(_ value: Any?) -> Bool {
        switch value {
        case let string as String: ["yes", "true", "1"].contains(string.lowercased())
        case let number as NSNumber: number.boolValue
        default: false
        }
    }
}
