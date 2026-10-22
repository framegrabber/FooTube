@testable import FooTubeCore
import Foundation
import Testing

@Suite("Embedded provisioning profile")
struct ProvisioningProfileTests {
    /// A plist between binary bytes, the way the CMS envelope of `embedded.mobileprovision` holds it.
    private func envelope(_ plist: String) -> Data {
        Data([0x30, 0x82, 0x2F, 0x00, 0x06, 0x09]) + Data(plist.utf8) + Data([0xA0, 0x82, 0x0D, 0x00, 0x30])
    }

    @Test func `reads the expiration date from the embedded plist`() throws {
        let data = envelope("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Name</key><string>iOS Team Provisioning Profile: *</string>
        <key>ExpirationDate</key><date>2026-10-29T18:04:11Z</date>
        </dict></plist>
        """)
        let expected = try Date("2026-10-29T18:04:11Z", strategy: .iso8601)
        #expect(ProvisioningProfile.expirationDate(in: data) == expected)
    }

    @Test func `no date without a plist or without the key`() {
        #expect(ProvisioningProfile.expirationDate(in: Data([0x30, 0x82, 0x00])) == nil)
        #expect(ProvisioningProfile.expirationDate(in: envelope("""
        <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>Name</key><string>x</string></dict></plist>
        """)) == nil)
    }
}
