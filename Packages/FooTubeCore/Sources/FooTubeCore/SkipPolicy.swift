/// Decides what to do with SponsorBlock segments as playback time advances, per category as set in
/// `SkipSettings`: skip automatically once, offer a skip button while inside, or ignore.
public struct SkipPolicy: Sendable {
    public enum Decision: Hashable, Sendable {
        case none
        case autoSkip(SkipSegment)
        case offer(SkipSegment)
    }

    /// Too close to the end to be worth skipping or offering.
    static let endMargin = 0.5

    private let segments: [SkipSegment]
    private let settings: SkipSettings
    private var skipped: Set<String> = []

    public init(segments: [SkipSegment], settings: SkipSettings = .default) {
        self.segments = segments.filter { settings.behavior(for: $0.category) != .off }
        self.settings = settings
    }

    /// Call on every time update. An `.autoSkip` is returned once per segment; the caller seeks to
    /// its end. Seeking back into it later does not skip again.
    public mutating func evaluate(at time: Double) -> Decision {
        let active = segments.filter { !skipped.contains($0.id) && $0.start <= time && time < $0.end - Self.endMargin }
        if let segment = active.first(where: { settings.behavior(for: $0.category) == .skipAutomatically }) {
            skipped.insert(segment.id)
            return .autoSkip(segment)
        }
        return active.first.map(Decision.offer) ?? .none
    }

    /// The user pressed the skip button for an offered segment.
    public mutating func markSkipped(_ segment: SkipSegment) {
        skipped.insert(segment.id)
    }
}
