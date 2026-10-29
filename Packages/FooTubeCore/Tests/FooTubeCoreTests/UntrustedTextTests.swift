import FooTubeCore
import Testing

@Suite("Untrusted titles")
struct UntrustedTextTests {
    @Test(arguments: [nil, "", "   ", "\n\t", "\u{202E}\u{200B}\u{7}", "\u{FEFF}\u{0} \u{2066}"])
    func `nothing visible gives nil`(raw: String?) {
        #expect(UntrustedText.title(raw) == nil)
    }

    @Test(arguments: [
        ("\u{202E}gnp.exe", "gnp.exe"), // right-to-left override (Cf)
        ("a\u{202A}b\u{202B}c\u{202C}d\u{202D}e", "abcde"), // embeddings and pop (Cf)
        ("a\u{2066}b\u{2067}c\u{2068}d\u{2069}e", "abcde"), // isolates (Cf)
        ("a\u{200E}b\u{200F}c\u{200B}d\u{FEFF}e\u{AD}f", "abcdef"), // marks, zero width space, BOM, soft hyphen (Cf)
        ("a\u{0}b\u{7}c\u{1B}[31md\u{7F}e\u{9B}f", "abc[31mdef"), // NUL, BEL, ESC, DEL, CSI (Cc)
    ])
    func `drops control and format characters`(raw: String, expected: String) {
        #expect(UntrustedText.title(raw) == expected)
    }

    @Test func `line breaks and tabs become spaces, the ends are trimmed`() {
        #expect(UntrustedText.title("  \nBig\tBuck\r\nBunny \n") == "Big Buck  Bunny")
    }

    @Test func `keeps ordinary text in any script`() {
        let title = "Größte Höhe – 日本語 · العربية · 🐰🎬"
        #expect(UntrustedText.title(title) == title)
    }

    @Test func `cuts to 200 Unicode scalars like the Worker and trims what the cut leaves`() {
        #expect(UntrustedText.title(String(repeating: "a", count: 1_000_000)) == String(repeating: "a", count: 200))
        #expect(UntrustedText.title(String(repeating: "🐰", count: 201)) == String(repeating: "🐰", count: 200))
        // Leading whitespace and dropped characters don't count; a space at the cut is trimmed.
        let raw = "  \u{202E}" + String(repeating: "b", count: 199) + " tail"
        #expect(UntrustedText.title(raw) == String(repeating: "b", count: 199))
        #expect(UntrustedText.maxTitleLength == 200)
    }
}
