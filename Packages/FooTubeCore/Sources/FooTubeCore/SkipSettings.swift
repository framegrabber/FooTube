import Foundation

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

/// `SkipSettings` in `UserDefaults`; only differences from the default are stored, so unknown or
/// unreadable values fall back to it.
public struct SkipSettingsStore {
    private let defaults: UserDefaults
    private let key = "skipSettings.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> SkipSettings {
        guard let raw = defaults.dictionary(forKey: key) as? [String: String] else { return .default }
        let pairs = raw.compactMap { key, value in
            SponsorCategory(rawValue: key).flatMap { category in SkipBehavior(rawValue: value).map { (category, $0) } }
        }
        return SkipSettings(Dictionary(pairs) { first, _ in first })
    }

    public func save(_ settings: SkipSettings) {
        let raw = Dictionary(uniqueKeysWithValues: SponsorCategory.allCases.compactMap { category -> (String, String)? in
            let behavior = settings.behavior(for: category)
            return behavior == SkipSettings.defaultBehavior(for: category) ? nil : (category.rawValue, behavior.rawValue)
        })
        defaults.set(raw, forKey: key)
    }
}
