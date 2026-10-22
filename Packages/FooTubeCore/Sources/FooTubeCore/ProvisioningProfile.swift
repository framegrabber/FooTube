import Foundation

/// The provisioning profile Xcode embeds in a device build (`embedded.mobileprovision`). A
/// sideloaded build stops launching when it expires: after 7 days with a free Apple ID.
public enum ProvisioningProfile {
    /// The profile's `ExpirationDate`. The file is a signed CMS envelope around an XML property list;
    /// the plist is read from between its markers without verifying the signature. Nil when the
    /// data holds no readable profile (Simulator builds have none).
    public static func expirationDate(in data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.upperBound ..< data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound ..< end.upperBound], format: nil),
              let dictionary = plist as? [String: Any] else { return nil }
        return dictionary["ExpirationDate"] as? Date
    }
}
