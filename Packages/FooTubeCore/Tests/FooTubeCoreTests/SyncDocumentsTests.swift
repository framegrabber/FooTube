import FooTubeCore
import Foundation
import Testing

@Suite("Sync documents")
struct SyncDocumentsTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000.123)

    @Test func `dates are ISO 8601 with milliseconds in UTC and read back unchanged`() throws {
        #expect(SyncCoding.string(from: now) == "2027-01-15T08:00:00.123Z")
        #expect(SyncCoding.date(from: "2027-01-15T08:00:00.123Z") == now)
        #expect(SyncCoding.date(from: "2027-01-15T08:00:00Z") == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(SyncCoding.date(from: "yesterday") == nil)

        let document = SubscriptionsDocument(entries: [SubscriptionRecord(id: "UC1", name: "One", avatar: nil, changedAt: now)])
        let data = try SyncCoding.encode(document)
        #expect(String(decoding: data, as: UTF8.self) == #"{"entries":[{"changedAt":"2027-01-15T08:00:00.123Z","id":"UC1","name":"One"}],"format":1}"#)
        #expect(try SyncCoding.decode(SubscriptionsDocument.self, from: data) == document)
    }

    @Test func `stamped dates drop sub-millisecond precision and never move forward`() {
        let precise = Date(timeIntervalSince1970: 1_800_000_000.1239)
        let stamped = SyncCoding.timestamp(precise)
        #expect(stamped <= precise)
        #expect(SyncCoding.string(from: stamped) == "2027-01-15T08:00:00.123Z")
        #expect(SyncCoding.date(from: SyncCoding.string(from: stamped)) == stamped)
    }

    @Test func `the canonical encoding sorts keys, so equal documents give equal bytes`() throws {
        let first = SkipSettingsDocument(changedAt: now, overrides: ["sponsor": "off", "intro": "off", "filler": "off"])
        let second = SkipSettingsDocument(changedAt: now, overrides: ["filler": "off", "sponsor": "off", "intro": "off"])
        let data = try SyncCoding.encode(first)
        #expect(try data == SyncCoding.encode(second))
        #expect(String(decoding: data, as: UTF8.self) == #"{"changedAt":"2027-01-15T08:00:00.123Z","format":1,"overrides":{"filler":"off","intro":"off","sponsor":"off"}}"#)
    }

    @Test func `a newer format is unsupported and never decoded`() {
        let newer = Data(#"{"format":2,"entries":[],"somethingNew":true}"#.utf8)
        #expect(throws: SyncDocumentError.unsupportedFormat(2)) {
            try SyncCoding.decode(SubscriptionsDocument.self, from: newer)
        }
    }

    @Test func `documents without a format or with wrong fields are unreadable`() {
        for raw in [#"{"entries":[]}"#, #"{"format":1,"entries":[{"id":"UC1"}]}"#, #"{"format":0,"entries":[]}"#, "not json"] {
            #expect {
                try SyncCoding.decode(SubscriptionsDocument.self, from: Data(raw.utf8))
            } throws: { error in
                if case .unreadable = error as? SyncDocumentError {
                    true
                } else {
                    false
                }
            }
        }
    }

    @Test func `documents of other clients decode with fractional seconds of any length and extra fields`() throws {
        let raw = #"""
        {"format":1,"clearedAt":"2027-01-15T08:00:00Z","entries":[{"videoID":"r1jOsar2zV4","position":12.5,"duration":600,"updatedAt":"2027-01-15T08:00:10.123456Z","watched":true,"extra":1}]}
        """#
        let document = try SyncCoding.decode(HistoryDocument.self, from: Data(raw.utf8))
        #expect(document.clearedAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(document.entries.map(\.updatedAt) == [Date(timeIntervalSince1970: 1_800_000_010.123)])
        #expect(document.entries.map(\.watched) == [true])
    }

    @Test func `settings documents keep only differences from the default and ignore unknown values`() {
        var settings = SkipSettings.default
        settings.set(.off, for: .sponsor)
        settings.set(.showButton, for: .intro)
        let document = SkipSettingsDocument(settings, changedAt: now)
        #expect(document.overrides == ["sponsor": "off"])
        #expect(document.settings == settings)

        let foreign = SkipSettingsDocument(changedAt: now, overrides: ["sponsor": "sometimes", "chapter": "off", "intro": "off"])
        #expect(foreign.settings.behavior(for: .sponsor) == .skipAutomatically)
        #expect(foreign.settings.behavior(for: .intro) == .off)
    }

    @Test func `store names are the Contract's path segments`() {
        #expect(SyncStoreName.allCases.map(\.rawValue) == ["subscriptions", "watchLater", "history", "skipSettings"])
        #expect(HistoryDocument.store == .history)
        #expect(WatchLaterDocument.store == .watchLater)
    }
}
