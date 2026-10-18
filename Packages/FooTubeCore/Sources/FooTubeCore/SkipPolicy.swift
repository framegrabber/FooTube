/// Decides what to do with SponsorBlock segments as playback time advances (SPEC success criterion 4):
/// auto-skip `sponsor` once, offer a skip button for every other category while inside it.
public struct SkipPolicy: Sendable {
    public enum Decision: Hashable, Sendable {
        case none
        case autoSkip(SkipSegment)
        case offer(SkipSegment)
    }

    /// Too close to the end to be worth skipping or offering.
    static let endMargin = 0.5

    private let segments: [SkipSegment]
    private var skipped: Set<String> = []

    public init(segments: [SkipSegment]) {
        self.segments = segments
    }

    /// Call on every time update. An `.autoSkip` is returned once per segment; the caller seeks to
    /// its end. Seeking back into it later does not skip again.
    public mutating func evaluate(at time: Double) -> Decision {
        let active = segments.filter { !skipped.contains($0.id) && $0.start <= time && time < $0.end - Self.endMargin }
        if let sponsor = active.first(where: \.category.autoSkips) {
            skipped.insert(sponsor.id)
            return .autoSkip(sponsor)
        }
        return active.first.map(Decision.offer) ?? .none
    }

    /// The user pressed the skip button for an offered segment.
    public mutating func markSkipped(_ segment: SkipSegment) {
        skipped.insert(segment.id)
    }
}
