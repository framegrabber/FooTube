import Foundation

/// Text that reaches the app from outside: `footube://` links, the browser inbox and anything else
/// stored through `VideoSummary.bare`. Applies the Worker's inbox rule (`FooTubeSyncBackend` `inbox.ts`)
/// so a title from any of these sources looks the same and stays small.
public enum UntrustedText {
    /// Unicode scalars, like the Worker's `Array.from(title).slice(0, 200)`.
    public static let maxTitleLength = 200

    /// The title without control (`Cc`) and format (`Cf`, including bidi overrides and zero-width
    /// characters) characters, trimmed and cut to `maxTitleLength` Unicode scalars; nil when nothing is
    /// left. Line breaks and tabs become spaces so the words around them stay apart. Reads only as much of
    /// `raw` as the result needs.
    public static func title(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var scalars = String.UnicodeScalarView()
        var count = 0
        for scalar in raw.unicodeScalars {
            let kept: Unicode.Scalar
            switch scalar.properties.generalCategory {
            case .control where scalar.properties.isWhitespace: kept = " "
            case .control, .format: continue
            default: kept = scalar
            }
            if count == 0, kept.properties.isWhitespace {
                continue
            }
            scalars.append(kept)
            count += 1
            if count == maxTitleLength {
                break
            }
        }
        let title = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }
}
