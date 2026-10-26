import Foundation
import os

/// What playback does with a SponsorBlock segment of one category.
public enum SkipBehavior: String, CaseIterable, Codable, Hashable, Sendable {
    /// Seek past it once when playback enters it.
    case skipAutomatically
    /// Offer a Skip button while inside it.
    case showButton
    /// Ignore the category.
    case off
}

/// Skip behavior per category (SPEC success criterion 4 is the default: `sponsor` skips
/// automatically, every other category shows a button).
public struct SkipSettings: Hashable, Sendable {
    public static let `default` = SkipSettings()

    private var overrides: [SponsorCategory: SkipBehavior]

    public init(_ overrides: [SponsorCategory: SkipBehavior] = [:]) {
        self.overrides = overrides.filter { $0.value != Self.defaultBehavior(for: $0.key) }
    }

    public static func defaultBehavior(for category: SponsorCategory) -> SkipBehavior {
        category.autoSkips ? .skipAutomatically : .showButton
    }

    public func behavior(for category: SponsorCategory) -> SkipBehavior {
        overrides[category] ?? Self.defaultBehavior(for: category)
    }

    public mutating func set(_ behavior: SkipBehavior, for category: SponsorCategory) {
        overrides[category] = behavior == Self.defaultBehavior(for: category) ? nil : behavior
    }

    public var isDefault: Bool {
        overrides.isEmpty
    }
}

/// `SkipSettings` in `UserDefaults` as a `SkipSettingsDocument`; only differences from the default
/// are stored, so unknown or unreadable values fall back to it. Every `save` is a change for sync,
/// also saving the default ("Restore Defaults").
public struct SkipSettingsStore: SyncableStore {
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let key = "skipSettings.v2"
    private let legacyKey = "skipSettings.v1"
    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "storage")

    /// `now` stamps changes and the one-time migration from `skipSettings.v1`.
    public init(defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { .now }) {
        self.defaults = defaults
        self.now = now
    }

    public func load() -> SkipSettings {
        document().settings
    }

    public func save(_ settings: SkipSettings) {
        do {
            try replace(SkipSettingsDocument(settings, changedAt: SyncCoding.timestamp(now())))
        } catch {
            logger.error("Couldn't save skip settings: \(error.message, privacy: .public)")
        }
    }

    /// For sync. Migrates `skipSettings.v1` on first use; settings that differ from the default get
    /// `changedAt` = migration time, default ones stay "never changed".
    public func document() -> SkipSettingsDocument {
        defaults.syncDocument(SkipSettingsDocument.self, forKey: key, migratingFrom: legacyKey, logger: logger) {
            let raw = defaults.dictionary(forKey: legacyKey) as? [String: String] ?? [:]
            let settings = SkipSettingsDocument(changedAt: nil, overrides: raw).settings
            return SkipSettingsDocument(settings, changedAt: settings.isDefault ? nil : SyncCoding.timestamp(now()))
        }
    }

    /// For sync: saves a merged document as is.
    public func replace(_ document: SkipSettingsDocument) throws(SyncDocumentError) {
        try defaults.setSyncDocument(document, forKey: key)
    }
}
