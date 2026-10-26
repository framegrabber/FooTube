@testable import FooTubeCore
import Foundation
import Testing

@Suite("Sync merge rules")
struct SyncMergeTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 24 * 60 * 60

    private func channel(_ id: String, name: String? = nil, changed: TimeInterval, removed: Bool = false) -> SubscriptionRecord {
        let changedAt = now + changed
        return SubscriptionRecord(id: id, name: name ?? id, avatar: nil, changedAt: changedAt, removedAt: removed ? changedAt : nil)
    }

    private func subscriptions(_ entries: SubscriptionRecord...) -> SubscriptionsDocument {
        SubscriptionsDocument(entries: entries)
    }

    private func video(_ id: String, title: String? = nil) -> VideoSummary {
        VideoSummary(id: VideoID(id)!, title: title ?? id, channel: nil, duration: nil, viewCount: nil, published: nil, thumbnail: nil)
    }

    private func later(_ id: String, added: TimeInterval, changed: TimeInterval? = nil, removed: Bool = false) -> WatchLaterRecord {
        let changedAt = now + (changed ?? added)
        return WatchLaterRecord(video: video(id), addedAt: now + added, changedAt: changedAt, removedAt: removed ? changedAt : nil)
    }

    private func watch(
        _ id: String,
        position: Double,
        updated: TimeInterval,
        watched: Bool = false,
        title: String? = nil,
    ) -> WatchEntry {
        WatchEntry(
            videoID: VideoID(id)!,
            position: position,
            duration: 600,
            updatedAt: now + updated,
            watched: watched,
            video: title.map { video(id, title: $0) },
        )
    }

    private func ids(_ document: SubscriptionsDocument) -> [String] {
        document.entries.map(\.id)
    }

    // MARK: Subscriptions and Watch Later

    @Test func `the later changedAt wins, whether it is the removal or the re-add`() {
        let removedLater = merge(subscriptions(channel("a", changed: -20)), subscriptions(channel("a", changed: -10, removed: true)), lastSyncAt: nil, now: now)
        #expect(removedLater.entries.map(\.removedAt) == [now - 10])

        let readdedLater = merge(subscriptions(channel("a", changed: -5)), subscriptions(channel("a", changed: -10, removed: true)), lastSyncAt: nil, now: now)
        #expect(readdedLater.entries.map(\.removedAt) == [nil])
        #expect(readdedLater.entries.map(\.changedAt) == [now - 5])
    }

    @Test func `a removal wins a tie on changedAt`() {
        let live = channel("a", name: "Zeta", changed: -10)
        let removed = channel("a", name: "Alpha", changed: -10, removed: true)
        #expect(merge(subscriptions(live), subscriptions(removed), lastSyncAt: nil, now: now).entries == [removed])
        #expect(merge(subscriptions(removed), subscriptions(live), lastSyncAt: nil, now: now).entries == [removed])
    }

    @Test func `otherwise the greater canonical JSON wins a tie, on either side`() throws {
        let alpha = channel("a", name: "Alpha", changed: -10)
        let zeta = channel("a", name: "Zeta", changed: -10)
        let forward = merge(subscriptions(alpha), subscriptions(zeta), lastSyncAt: nil, now: now)
        let backward = merge(subscriptions(zeta), subscriptions(alpha), lastSyncAt: nil, now: now)
        #expect(forward.entries == [zeta])
        let forwardBytes = try SyncCoding.encode(forward)
        #expect(try forwardBytes == SyncCoding.encode(backward))
    }

    @Test func `entries on only one side are kept and the result is ordered by id`() {
        let merged = merge(subscriptions(channel("c", changed: -1), channel("a", changed: -3)), subscriptions(channel("b", changed: -2)), lastSyncAt: nil, now: now)
        #expect(ids(merged) == ["a", "b", "c"])
    }

    @Test func `a live local entry missing on the server and unchanged since the last sync was pruned elsewhere`() {
        let local = subscriptions(channel("gone", changed: -100 * day), channel("kept", changed: -100 * day))
        let remote = subscriptions(channel("kept", changed: -100 * day))
        #expect(ids(merge(local, remote, lastSyncAt: now - 50 * day, now: now)) == ["kept"])
        // At the boundary: changed exactly at the last sync still counts as synced.
        #expect(ids(merge(local, remote, lastSyncAt: now - 100 * day, now: now)) == ["kept"])
    }

    @Test func `a local entry changed after the last sync is kept to be pushed`() {
        let local = subscriptions(channel("new", changed: -10))
        #expect(ids(merge(local, subscriptions(), lastSyncAt: now - 60, now: now)) == ["new"])
    }

    @Test func `a device that never synced keeps everything`() {
        let local = subscriptions(channel("old", changed: -100 * day))
        #expect(ids(merge(local, subscriptions(channel("other", changed: -1)), lastSyncAt: nil, now: now)) == ["old", "other"])
    }

    @Test func `without a server document nothing counts as pruned elsewhere`() {
        let local = subscriptions(channel("old", changed: -100 * day))
        #expect(ids(merge(local, nil, lastSyncAt: now - day, now: now)) == ["old"])
    }

    @Test func `a local removal marker missing on the server is kept to be pushed`() {
        let local = subscriptions(channel("a", changed: -100, removed: true))
        #expect(merge(local, subscriptions(), lastSyncAt: now - 10, now: now).entries == local.entries)
    }

    @Test func `removal markers are dropped once older than 90 days`() {
        let boundary = SubscriptionRecord(id: "edge", name: "edge", avatar: nil, changedAt: now - 90 * day, removedAt: now - 90 * day)
        let older = SubscriptionRecord(id: "old", name: "old", avatar: nil, changedAt: now - 90 * day - 0.001, removedAt: now - 90 * day - 0.001)
        let merged = merge(subscriptions(boundary), subscriptions(older), lastSyncAt: nil, now: now)
        #expect(ids(merged) == ["edge"])
        #expect(ids(merge(subscriptions(boundary), nil, lastSyncAt: nil, now: now + 0.001)).isEmpty)
    }

    @Test func `a marker older than 90 days takes the older live entry it beat with it`() {
        // The marker wins the union before pruning, so an offline device's live copy doesn't come back.
        let marker = channel("a", changed: -95 * day, removed: true)
        let live = channel("a", changed: -200 * day)
        #expect(merge(subscriptions(live), subscriptions(marker), lastSyncAt: nil, now: now).entries.isEmpty)
    }

    @Test func `timestamps more than a day in the future count as now`() {
        let future = channel("a", name: "Future", changed: 2 * day)
        let soon = channel("a", name: "Soon", changed: 3600)
        let merged = merge(subscriptions(future), subscriptions(soon), lastSyncAt: nil, now: now)
        #expect(merged.entries.map(\.name) == ["Soon"])

        let alone = merge(subscriptions(future), nil, lastSyncAt: nil, now: now)
        #expect(alone.entries.map(\.changedAt) == [now])
        let withinADay = channel("b", changed: day)
        #expect(merge(subscriptions(withinADay), nil, lastSyncAt: nil, now: now).entries == [withinADay])
    }

    @Test func `watch later unions by video and lists newest added first`() {
        let local = WatchLaterDocument(entries: [later("aaaaaaaaaaa", added: -30), later("bbbbbbbbbbb", added: -10)])
        let remote = WatchLaterDocument(entries: [later("ccccccccccc", added: -20), later("aaaaaaaaaaa", added: -40, changed: -5, removed: true)])
        let merged = merge(local, remote, lastSyncAt: nil, now: now)
        #expect(merged.entries.map(\.video.id.rawValue) == ["bbbbbbbbbbb", "ccccccccccc", "aaaaaaaaaaa"])
        #expect(merged.entries.last?.removedAt == now - 5)
    }

    @Test func `watch later applies the pruned-elsewhere rule and the marker lifetime`() {
        let local = WatchLaterDocument(entries: [later("aaaaaaaaaaa", added: -100 * day), later("bbbbbbbbbbb", added: -10)])
        let remote = WatchLaterDocument(entries: [later("ccccccccccc", added: -91 * day, removed: true)])
        let merged = merge(local, remote, lastSyncAt: now - 60, now: now)
        #expect(merged.entries.map(\.video.id.rawValue) == ["bbbbbbbbbbb"])
    }

    @Test func `watch later clamps a future addedAt`() {
        let merged = merge(WatchLaterDocument(entries: [later("aaaaaaaaaaa", added: 3 * day)]), nil, lastSyncAt: nil, now: now)
        #expect(merged.entries.map(\.addedAt) == [now])
        #expect(merged.entries.map(\.changedAt) == [now])
    }

    // MARK: History

    @Test func `history keeps the later update per video, ties going to the greater position`() {
        let local = HistoryDocument(entries: [watch("aaaaaaaaaaa", position: 100, updated: -10), watch("bbbbbbbbbbb", position: 50, updated: -5)])
        let remote = HistoryDocument(entries: [watch("aaaaaaaaaaa", position: 300, updated: -20), watch("bbbbbbbbbbb", position: 80, updated: -5)])
        let merged = merge(local, remote, lastSyncAt: nil, now: now)
        #expect(merged.entries.map(\.videoID.rawValue) == ["bbbbbbbbbbb", "aaaaaaaaaaa"])
        #expect(merged.entries.map(\.position) == [80, 100])
    }

    @Test func `watched stays set if either side has it`() {
        let local = HistoryDocument(entries: [watch("aaaaaaaaaaa", position: 30, updated: -1)])
        let remote = HistoryDocument(entries: [watch("aaaaaaaaaaa", position: 590, updated: -100, watched: true)])
        let merged = merge(local, remote, lastSyncAt: nil, now: now)
        #expect(merged.entries.map(\.watched) == [true])
        #expect(merged.entries.map(\.position) == [30])
    }

    @Test func `the summary falls back to the other side when the winner has none`() {
        let local = HistoryDocument(entries: [watch("aaaaaaaaaaa", position: 30, updated: -1)])
        let remote = HistoryDocument(entries: [watch("aaaaaaaaaaa", position: 20, updated: -100, title: "Known")])
        #expect(merge(local, remote, lastSyncAt: nil, now: now).entries.first?.video?.title == "Known")

        let titledWinner = HistoryDocument(entries: [watch("aaaaaaaaaaa", position: 30, updated: -1, title: "New")])
        #expect(merge(titledWinner, remote, lastSyncAt: nil, now: now).entries.first?.video?.title == "New")
    }

    @Test func `the later clearedAt drops every entry updated at or before it`() {
        let local = HistoryDocument(clearedAt: now - 100, entries: [watch("aaaaaaaaaaa", position: 30, updated: -200), watch("bbbbbbbbbbb", position: 30, updated: -50)])
        let remote = HistoryDocument(clearedAt: now - 50, entries: [watch("ccccccccccc", position: 30, updated: -10)])
        let merged = merge(local, remote, lastSyncAt: nil, now: now)
        #expect(merged.clearedAt == now - 50)
        #expect(merged.entries.map(\.videoID.rawValue) == ["ccccccccccc"])
    }

    @Test func `history keeps the newest 500 entries`() throws {
        let local = try HistoryDocument(entries: (0 ..< 300).map { index in
            try WatchEntry(videoID: #require(VideoID(String(format: "loc%08d", index))), position: 1, duration: 600, updatedAt: now - Double(2 * index), watched: false)
        })
        let remote = try HistoryDocument(entries: (0 ..< 300).map { index in
            try WatchEntry(videoID: #require(VideoID(String(format: "rem%08d", index))), position: 1, duration: 600, updatedAt: now - Double(2 * index + 1), watched: false)
        })
        let merged = merge(local, remote, lastSyncAt: nil, now: now)
        #expect(merged.entries.count == WatchHistory.capacity)
        #expect(merged.entries.first?.videoID.rawValue == "loc00000000")
        #expect(merged.entries.last?.updatedAt == now - 499)
        #expect(merged.entries.map(\.updatedAt) == merged.entries.map(\.updatedAt).sorted(by: >))
    }

    @Test func `history clamps future updates and a future clearedAt`() {
        let local = HistoryDocument(entries: [watch("aaaaaaaaaaa", position: 30, updated: 5 * day)])
        let remote = HistoryDocument(entries: [watch("aaaaaaaaaaa", position: 40, updated: 3600)])
        #expect(merge(local, remote, lastSyncAt: nil, now: now).entries.map(\.position) == [40])
        #expect(merge(local, nil, lastSyncAt: nil, now: now).entries.map(\.updatedAt) == [now])

        let wiped = HistoryDocument(clearedAt: now + 10 * day, entries: [])
        let merged = merge(wiped, remote, lastSyncAt: nil, now: now)
        #expect(merged.clearedAt == now)
        #expect(merged.entries.map(\.position) == [40])
    }

    // MARK: Settings

    @Test func `settings take the whole document with the later changedAt`() {
        let older = SkipSettingsDocument(changedAt: now - 100, overrides: ["sponsor": "off", "intro": "off"])
        let newer = SkipSettingsDocument(changedAt: now - 10, overrides: ["filler": "off"])
        #expect(merge(older, newer, lastSyncAt: nil, now: now) == newer)
        #expect(merge(newer, older, lastSyncAt: nil, now: now) == newer)
    }

    @Test func `never-changed settings lose to any other`() {
        let never = SkipSettingsDocument.empty
        let changed = SkipSettingsDocument(changedAt: now - 1000 * day, overrides: ["sponsor": "off"])
        #expect(merge(never, changed, lastSyncAt: nil, now: now) == changed)
        #expect(merge(changed, never, lastSyncAt: nil, now: now) == changed)
        #expect(merge(never, nil, lastSyncAt: nil, now: now) == never)
    }

    @Test func `restoring defaults is a change that wins over older overrides`() {
        let restored = SkipSettingsDocument(SkipSettings.default, changedAt: now - 5)
        let older = SkipSettingsDocument(changedAt: now - 50, overrides: ["sponsor": "off"])
        let merged = merge(older, restored, lastSyncAt: nil, now: now)
        #expect(merged.overrides.isEmpty)
        #expect(merged.settings == .default)
    }

    @Test func `settings clamp a future changedAt and break ties canonically`() {
        let future = SkipSettingsDocument(changedAt: now + 2 * day, overrides: ["sponsor": "off"])
        let recent = SkipSettingsDocument(changedAt: now - 1, overrides: ["intro": "off"])
        #expect(merge(future, recent, lastSyncAt: nil, now: now).changedAt == now)

        let first = SkipSettingsDocument(changedAt: now - 1, overrides: ["filler": "off"])
        #expect(merge(first, recent, lastSyncAt: nil, now: now) == merge(recent, first, lastSyncAt: nil, now: now))
    }

    // MARK: Determinism

    @Test func `swapping the inputs gives the same document`() throws {
        let localSubscriptions = subscriptions(channel("a", name: "A1", changed: -10), channel("b", changed: -5, removed: true), channel("c", changed: -1))
        let remoteSubscriptions = subscriptions(channel("a", name: "A2", changed: -10), channel("b", changed: -5), channel("d", changed: -91 * day, removed: true))
        let subscriptionsBytes = try SyncCoding.encode(merge(localSubscriptions, remoteSubscriptions, lastSyncAt: nil, now: now))
        #expect(try subscriptionsBytes == SyncCoding.encode(merge(remoteSubscriptions, localSubscriptions, lastSyncAt: nil, now: now)))

        let localLater = WatchLaterDocument(entries: [later("aaaaaaaaaaa", added: -10), later("bbbbbbbbbbb", added: -10)])
        let remoteLater = WatchLaterDocument(entries: [later("aaaaaaaaaaa", added: -20, changed: -10, removed: true), later("ccccccccccc", added: -10)])
        let laterBytes = try SyncCoding.encode(merge(localLater, remoteLater, lastSyncAt: nil, now: now))
        #expect(try laterBytes == SyncCoding.encode(merge(remoteLater, localLater, lastSyncAt: nil, now: now)))

        let localHistory = HistoryDocument(clearedAt: now - 300, entries: [watch("aaaaaaaaaaa", position: 10, updated: -10, title: "A"), watch("bbbbbbbbbbb", position: 5, updated: -5)])
        let remoteHistory = HistoryDocument(entries: [watch("aaaaaaaaaaa", position: 10, updated: -10, watched: true), watch("ccccccccccc", position: 5, updated: -5)])
        let historyBytes = try SyncCoding.encode(merge(localHistory, remoteHistory, lastSyncAt: nil, now: now))
        #expect(try historyBytes == SyncCoding.encode(merge(remoteHistory, localHistory, lastSyncAt: nil, now: now)))
    }

    @Test func `merging a merged document again changes nothing`() throws {
        let local = subscriptions(channel("a", changed: -10), channel("b", changed: -5, removed: true))
        let remote = subscriptions(channel("c", changed: -3))
        let merged = merge(local, remote, lastSyncAt: nil, now: now)
        let mergedBytes = try SyncCoding.encode(merged)
        #expect(try SyncCoding.encode(merge(merged, merged, lastSyncAt: now, now: now)) == mergedBytes)
    }
}
