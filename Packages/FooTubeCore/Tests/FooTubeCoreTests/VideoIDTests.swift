import FooTubeCore
import Testing

@Suite("VideoID validation")
struct VideoIDTests {
    @Test(arguments: ["dQw4w9WgXcQ", "aqz-KE-bpKQ", "_-_-_-_-_-_"])
    func `accepts eleven character IDs`(raw: String) {
        #expect(VideoID(raw)?.rawValue == raw)
    }

    @Test(arguments: ["", "dQw4w9WgXc", "dQw4w9WgXcQQ", "dQw4w9WgX!Q", "dQw4w9 gXcQ"])
    func `rejects malformed IDs`(raw: String) {
        #expect(VideoID(raw) == nil)
    }

    @Test(arguments: [
        ("dQw4w9WgXcQ", "dQw4w9WgXcQ"),
        ("  dQw4w9WgXcQ\n", "dQw4w9WgXcQ"),
        ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
        ("https://www.youtube.com/watch?feature=share&v=dQw4w9WgXcQ&t=42s", "dQw4w9WgXcQ"),
        ("youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
        ("https://m.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
        ("https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=RDAMVM", "dQw4w9WgXcQ"),
        ("https://youtu.be/dQw4w9WgXcQ?si=abc", "dQw4w9WgXcQ"),
        ("https://www.youtube.com/shorts/BGQWPY4IigY", "BGQWPY4IigY"),
        ("https://www.youtube.com/live/rFZHOHl-L8A?feature=shared", "rFZHOHl-L8A"),
        ("https://www.youtube.com/embed/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
    ])
    func `parses IDs and YouTube URLs`(input: String, expected: String) {
        #expect(VideoID(parsing: input)?.rawValue == expected)
    }

    @Test(arguments: [
        "",
        "not a video",
        "https://example.com/watch?v=dQw4w9WgXcQ",
        "https://www.youtube.com/watch?v=short",
        "https://www.youtube.com/channel/UC38IQsAvIsxxjztdMZQtwHA",
        "https://youtu.be/",
    ])
    func `rejects input without a valid video`(input: String) {
        #expect(VideoID(parsing: input) == nil)
    }
}
