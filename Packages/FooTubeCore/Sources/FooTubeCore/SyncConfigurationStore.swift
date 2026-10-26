import Foundation
import os

/// Loads and saves the sync configuration: the Worker URL in `UserDefaults` (`sync.url.v1`), the
/// token in the Keychain. Configured by a file the run scripts copy into the app's data container
/// before launch (`scripts/sync-env.sh`, from `FOOTUBE_SYNC_URL`/`FOOTUBE_SYNC_TOKEN`), so the token
/// never enters the repository, the bundle, the build settings or a launch command (the system logs
/// launch arguments):
/// - `Library/Caches/footube-sync.json`, `{"url": …, "token": …}`: read once at launch and deleted
///   whether valid or not; saved when valid, the old configuration is kept otherwise.
/// - Launch argument `-syncReset YES` (no secret): removes URL, token and the engine's sync state;
///   local data stays.
public struct SyncConfigurationStore {
    public enum LaunchChange: Hashable, Sendable {
        /// No configuration file and no reset.
        case none
        /// The configuration from the file was saved (after a reset, if both were given).
        case configured
        /// `-syncReset YES` removed the configuration.
        case reset
    }

    private static let urlKey = "sync.url.v1"

    /// This launch's arguments (`-name value` pairs) as UserDefaults parsed them.
    public static var launchArguments: [String: Any] {
        UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
    }

    /// Where the run scripts drop the configuration (`Library/Caches` exists and is writable on tvOS;
    /// the file lives only until the launch it is meant for).
    public static var configurationFile: URL {
        URL.cachesDirectory.appending(path: "footube-sync.json")
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
        SyncEngine.resetState(in: defaults)
        try tokens.remove()
    }

    /// Applies the configuration file and `-syncReset`. The file is deleted before it is parsed, so it
    /// never outlives this call. Validates before changing anything: on an error the previous
    /// configuration (and a requested reset) is left alone.
    @discardableResult
    public func applyLaunchChanges(
        arguments: [String: Any] = Self.launchArguments,
        configurationFile: URL = Self.configurationFile,
    ) throws(SyncConfigurationError) -> LaunchChange {
        let shouldReset = Self.isYes(arguments["syncReset"])
        let configuration = try consume(configurationFile)
        if shouldReset {
            try reset()
            logger.info("Sync configuration reset by launch argument")
        }
        guard let configuration else { return shouldReset ? .reset : .none }
        try save(configuration)
        logger.info("Sync configured from file for \(configuration.url.host() ?? "", privacy: .public)")
        return .configured
    }

    /// Reads and deletes the configuration file; nil when there is none.
    private func consume(_ file: URL) throws(SyncConfigurationError) -> SyncConfiguration? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let data = try? Data(contentsOf: file)
        do {
            try FileManager.default.removeItem(at: file)
        } catch {
            logger.error("Couldn't delete the sync configuration file: \(error.localizedDescription, privacy: .public)")
        }
        // No decoding detail: it could quote the file's content.
        guard let data, let file = try? JSONDecoder().decode(ConfigurationFile.self, from: data) else { throw .unreadableFile }
        guard let url = URL(string: file.url) else { throw .invalidURL("unparsable URL") }
        return try SyncConfiguration(url: url, token: file.token)
    }

    private struct ConfigurationFile: Decodable {
        let url: String
        let token: String
    }

    private static func isYes(_ value: Any?) -> Bool {
        switch value {
        case let string as String: ["yes", "true", "1"].contains(string.lowercased())
        case let number as NSNumber: number.boolValue
        default: false
        }
    }
}
