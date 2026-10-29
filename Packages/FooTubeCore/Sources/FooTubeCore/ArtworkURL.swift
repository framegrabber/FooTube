import Foundation

/// Where artwork (thumbnails, avatars, chapter images) may be loaded from. Synced documents carry
/// these URLs from other devices and the Worker: loading any URL would tell its server when each
/// device shows a list (and from which IP), feed ImageIO whatever it serves, or read `file://` URLs.
public enum ArtworkURL {
    /// The image hosts InnerTube returns (`i.ytimg.com`, `i9.ytimg.com`, `yt3.ggpht.com`,
    /// `yt3.googleusercontent.com` in the recorded fixtures); any host under them is allowed.
    public static let domains = ["ytimg.com", "ggpht.com", "googleusercontent.com"]

    /// `https` on the default port, no user info, host under one of `domains`.
    public static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              let host = url.host(percentEncoded: false)?.lowercased()
        else { return false }
        return domains.contains { host.hasSuffix(".\($0)") }
    }
}
