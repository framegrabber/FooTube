import FooTubeCore
import Foundation
import Testing

@Suite("Artwork URLs")
struct ArtworkURLTests {
    @Test(arguments: [
        // The hosts InnerTube returns in the recorded fixtures (thumbnails, avatars).
        "https://i.ytimg.com/vi/aqz-KE-bpKQ/hqdefault.jpg",
        "https://i9.ytimg.com/vi/aqz-KE-bpKQ/mqdefault.jpg?sqp=abc",
        "https://yt3.ggpht.com/abc=s88-c-k-c0x00ffffff-no-rj",
        "https://yt3.googleusercontent.com/abc=s160-c-k-c0x00ffffff-no-rj",
        "HTTPS://I.YTIMG.COM/vi/aqz-KE-bpKQ/hqdefault.jpg",
        "https://i.ytimg.com:443/vi/aqz-KE-bpKQ/hqdefault.jpg",
    ])
    func `YouTube's image hosts over https load`(string: String) throws {
        #expect(try ArtworkURL.isAllowed(#require(URL(string: string))))
    }

    @Test(arguments: [
        "http://i.ytimg.com/vi/aqz-KE-bpKQ/hqdefault.jpg", // not https
        "file:///etc/passwd",
        "ftp://i.ytimg.com/x.jpg",
        "https://tracker.example/pixel.jpg?who=livingroom",
        "https://ytimg.com/vi/x.jpg", // the domain itself, not a host under it
        "https://i.ytimg.com.example.org/x.jpg",
        "https://evilytimg.com/x.jpg",
        "https://i.ytimg.com@example.org/x.jpg",
        "https://user:pass@i.ytimg.com/x.jpg",
        "https://i.ytimg.com:8443/x.jpg",
        "https://192.168.1.10/x.jpg",
        "data:image/png;base64,iVBORw0KGgo=",
    ])
    func `anything else does not`(string: String) throws {
        #expect(try !ArtworkURL.isAllowed(#require(URL(string: string))))
    }

    @Test func `the standard thumbnail of a bare video is allowed`() throws {
        let video = try VideoSummary.bare(#require(VideoID("aqz-KE-bpKQ")), title: nil)
        #expect(try ArtworkURL.isAllowed(#require(video.thumbnail)))
    }
}
