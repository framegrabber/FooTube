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
}
