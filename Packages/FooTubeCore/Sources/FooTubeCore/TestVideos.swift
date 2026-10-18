/// The MVP test cases (SPEC success criterion 1, `tasks/results.md`). Live stream IDs change over time.
public enum TestVideos {
    public struct Entry: Identifiable, Sendable {
        public let label: String
        public let id: VideoID
    }

    public static let all: [Entry] = [
        ("Normal: Big Buck Bunny 1080p60", "aqz-KE-bpKQ"),
        ("Label music video", "dQw4w9WgXcQ"),
        ("Age-restricted (expected to fail)", "HtVdAasjOgU"),
        ("Made for kids", "XqZsoesa55w"),
        ("Livestream", "rFZHOHl-L8A"),
        ("Long: 2 h documentary", "PkcnAB09ZXU"),
        ("Short", "BGQWPY4IigY"),
    ].compactMap { label, raw in VideoID(raw).map { Entry(label: label, id: $0) } }
}
