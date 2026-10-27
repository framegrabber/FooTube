import XCTest

/// Drives the Siri Remote in the Simulator for focus behaviour that unit tests cannot see.
/// Needs network (real YouTube). Run: `xcodebuild test -project FooTube.xcodeproj -scheme FooTube
/// -destination 'platform=tvOS Simulator,name=Apple TV'`.
@MainActor
final class FocusNavigationUITests: XCTestCase {
    private let remote = XCUIRemote.shared
    private let blender = "UCSMOQeBJ2RAnuFungnQOxLg"
    private let videoCard = NSPredicate(format: "label CONTAINS[c] ' views'")
    private let subscribeButton = NSPredicate(format: "label IN {'Subscribe', 'Unsubscribe'}")

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        // English UI and YouTube responses, so label predicates (" views") don't depend on the Simulator language.
        app.launchArguments = arguments + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func press(_ button: XCUIRemote.Button, times: Int = 1) {
        for _ in 0 ..< times {
            remote.press(button)
            usleep(500_000)
        }
    }

    private func focused(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
    }

    /// Presses `button` until the focused element matches `predicate` (at most `limit` presses).
    private func move(_ button: XCUIRemote.Button, until predicate: NSPredicate, in app: XCUIApplication, limit: Int = 8) -> Bool {
        for _ in 0 ..< limit {
            if predicate.evaluate(with: focused(app)) {
                return true
            }
            press(button)
        }
        return predicate.evaluate(with: focused(app))
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// F2: from each first-row card, pressing up reaches the Subscribe button.
    func testSubscribeIsReachableFromFirstRowCards() {
        let app = launch(["-channel", blender])
        XCTAssertTrue(app.buttons.matching(subscribeButton).firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons.matching(videoCard).firstMatch.waitForExistence(timeout: 20))

        for column in 0 ..< 4 {
            XCTAssertTrue(move(.down, until: videoCard, in: app), "no card focused")
            press(.left, times: 4)
            press(.right, times: column)
            if column == 2 {
                attachScreenshot("focused card")
            }
            press(.up)
            XCTAssertTrue(subscribeButton.evaluate(with: focused(app)), "column \(column): focus went to \(focused(app).label)")
        }
    }

    /// Going up from the results past the keyboard to the tab bar and back keeps the search.
    func testReturningFromTabBarKeepsTheSearch() {
        let app = launch(["-search", "blender open movie"])
        let result = app.buttons.matching(videoCard).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 20))
        XCTAssertTrue(move(.down, until: videoCard, in: app), "no result focused; focus on \(focused(app).debugDescription.prefix(300)); results: \(app.buttons.matching(videoCard).count)")

        press(.up, times: 8) // results → channels → keyboard → tab bar (extra presses are no-ops there)
        press(.down)
        usleep(1_500_000)
        attachScreenshot("after returning from the tab bar")
        XCTAssertTrue(app.buttons.matching(videoCard).firstMatch.exists, "search results were cleared")
    }

    /// Settings: the Sync section shows a known state (whatever this Simulator is configured for: Off
    /// without a sync configuration) and Sync Now only while sync is configured.
    func testSettingsShowsSyncStatus() {
        let app = launch([])
        press(.up, times: 2) // tab bar
        XCTAssertTrue(move(.right, until: NSPredicate(format: "label == 'Settings'"), in: app), "Settings tab not reached: \(focused(app).label)")
        press(.down)
        let status = NSPredicate(format: "label BEGINSWITH 'Status,'")
        XCTAssertTrue(move(.down, until: status, in: app, limit: 15), "Status row not reached: \(focused(app).label)")
        let settled = NSPredicate(format: "NOT (label CONTAINS 'Syncing')")
        XCTAssertTrue(settled.evaluate(with: focused(app)) || XCTWaiter().wait(for: [expectation(for: settled, evaluatedWith: focused(app))], timeout: 15) == .completed)
        let label = focused(app).label
        let known = ["Off", "Synced", "Offline, will retry", "Sync failed, will retry", "Token rejected", "Update FooTube on this device"]
        XCTAssertTrue(known.contains { label.contains($0) }, "unexpected sync state: \(label)")
        XCTAssertEqual(app.buttons["Sync Now"].exists, label != "Status, Off", "Sync Now visibility doesn't match \(label)")
        attachScreenshot("settings sync")
    }

    /// Settings: a SponsorBlock category's page changes its behavior, Restore Defaults resets it,
    /// and returning from the tab bar goes back to the first Settings page.
    func testSettingsChangeAndRestoreSkipBehavior() {
        let app = launch([])
        let sponsorRow = NSPredicate(format: "label BEGINSWITH 'Sponsor,'")
        press(.up, times: 2) // tab bar
        XCTAssertTrue(move(.right, until: NSPredicate(format: "label == 'Settings'"), in: app), "Settings tab not reached: \(focused(app).label)")
        press(.down)
        XCTAssertTrue(move(.up, until: sponsorRow, in: app), "Sponsor row not focused: \(focused(app).label)")
        XCTAssertTrue(focused(app).label.contains("Skip Automatically"), "unexpected default: \(focused(app).label)")
        attachScreenshot("settings")

        press(.select)
        XCTAssertTrue(move(.down, until: NSPredicate(format: "label == 'Skip Automatically'"), in: app, limit: 1), "current behavior not focused: \(focused(app).label)")
        XCTAssertTrue(move(.down, until: NSPredicate(format: "label == 'Off'"), in: app), "Off not reached")
        attachScreenshot("sponsor behavior page")
        press(.select)
        press(.menu)
        XCTAssertTrue(move(.up, until: sponsorRow, in: app), "back on the first page: \(focused(app).label)")
        XCTAssertTrue(focused(app).label.contains("Off"), "Sponsor not set to Off: \(focused(app).label)")

        let restore = NSPredicate(format: "label == 'Restore Defaults'")
        XCTAssertTrue(move(.down, until: restore, in: app, limit: 10), "Restore Defaults not reached")
        press(.select)
        XCTAssertTrue(app.buttons.matching(sponsorRow).firstMatch.label.contains("Skip Automatically"), "defaults not restored")

        XCTAssertTrue(move(.down, until: NSPredicate(format: "label BEGINSWITH 'SponsorBlock,'"), in: app, limit: 12), "About not reached")
        attachScreenshot("settings about")

        XCTAssertTrue(move(.up, until: sponsorRow, in: app, limit: 20), "Sponsor row not reached again")
        press(.select)
        press(.up, times: 4) // options → tab bar
        press(.down)
        usleep(1_000_000)
        XCTAssertTrue(app.buttons["Restore Defaults"].exists, "Settings did not return to its first page")
    }

    /// F11: long-pressing a card shows "Open <channel>", which opens the channel page.
    func testContextMenuOpensChannel() {
        let app = launch(["-search", "blender open movie"])
        XCTAssertTrue(app.buttons.matching(videoCard).firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(move(.down, until: videoCard, in: app), "no result focused; focus on \(focused(app).debugDescription.prefix(300)); results: \(app.buttons.matching(videoCard).count)")
        remote.press(.select, forDuration: 2)
        usleep(1_500_000)
        attachScreenshot("context menu")
        let open = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Open '")).firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5), "context menu did not appear")
        press(.select)
        XCTAssertTrue(app.buttons.matching(subscribeButton).firstMatch.waitForExistence(timeout: 20))
    }

    /// F12: the Subscriptions sidebar lists subscribed channels.
    func testSubscriptionsSidebar() {
        let app = launch(["-subscribe", "\(blender),UCe1Aj6VEO299Yq4WkXdoD3Q"])
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Alexandre Chappel'")).firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Blender'")).firstMatch.exists)
        usleep(3_000_000)
        attachScreenshot("subscriptions with sidebar")
    }

    /// G2: on a channel page pushed in the Search tab, going up to the tab bar and back down returns
    /// the tab to its root.
    func testReturningFromTabBarPopsChannelPage() {
        let app = launch(["-channel", blender])
        XCTAssertTrue(app.buttons.matching(subscribeButton).firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(move(.down, until: videoCard, in: app), "no card focused")
        press(.up, times: 6) // card → Subscribe → tab bar
        press(.down)
        usleep(1_500_000)
        attachScreenshot("after returning from the tab bar")
        XCTAssertFalse(app.buttons.matching(subscribeButton).firstMatch.exists, "channel page still shown")
    }

    /// A channel opened from the search results stays open while moving focus around it, so its
    /// Subscribe button and videos are reachable.
    func testChannelOpenedFromSearchStaysOpen() {
        let app = launch(["-search", "brickstory"])
        // The channel tile shows the subscriber count; the suggestion row above has "brickstory" too.
        let channel = NSPredicate(format: "label CONTAINS[c] 'brickstory' AND label CONTAINS[c] 'subscribers'")
        XCTAssertTrue(app.buttons.matching(channel).firstMatch.waitForExistence(timeout: 20), "no channel result")
        XCTAssertTrue(move(.down, until: channel, in: app), "channel result not focused: \(focused(app).label)")
        press(.select)
        let subscribe = app.buttons.matching(subscribeButton).firstMatch
        XCTAssertTrue(subscribe.waitForExistence(timeout: 20), "channel page did not open")
        XCTAssertTrue(app.buttons.matching(videoCard).firstMatch.waitForExistence(timeout: 20))

        XCTAssertTrue(move(.down, until: videoCard, in: app), "no video focused on the channel page: \(focused(app).label)")
        XCTAssertTrue(subscribe.exists, "channel page closed after moving to a video")
        XCTAssertTrue(move(.up, until: subscribeButton, in: app), "Subscribe not reachable: \(focused(app).label)")
        XCTAssertTrue(subscribe.exists, "channel page closed after moving to Subscribe")
    }

    /// G1 + G5: subscribing shows the channel (with avatar, see screenshot) in Subscriptions right
    /// away; "Add to Watch Later" from the long-press menu lists the video in Watch Later.
    func testSubscribeAndWatchLaterShowUpImmediately() {
        let app = launch(["-channel", "UCe1Aj6VEO299Yq4WkXdoD3Q"])
        let button = app.buttons.matching(subscribeButton).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons.matching(videoCard).firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(move(.down, until: videoCard, in: app), "no card focused")
        let title = focused(app).label

        let removeLater = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Remove from Watch Later'")).firstMatch
        let addLater = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Add to Watch Later'")).firstMatch
        remote.press(.select, forDuration: 2)
        if removeLater.waitForExistence(timeout: 3) { // left over from an earlier run: remove, reopen
            press(.select)
            remote.press(.select, forDuration: 2)
        }
        attachScreenshot("card menu")
        XCTAssertTrue(addLater.waitForExistence(timeout: 5), "no Watch Later item in the menu")
        press(.select)
        usleep(1_000_000)
        XCTAssertTrue(videoCard.evaluate(with: focused(app)), "menu did not close back to the card: \(focused(app).label)")

        press(.up)
        XCTAssertTrue(subscribeButton.evaluate(with: focused(app)), "Subscribe not focused: \(focused(app).label)")
        if focused(app).label == "Unsubscribe" { // start from "not subscribed"
            press(.select)
            XCTAssertTrue(app.buttons["Subscribe"].waitForExistence(timeout: 5))
        }
        press(.select)
        XCTAssertTrue(app.buttons["Unsubscribe"].waitForExistence(timeout: 5))

        press(.up) // tab bar (Search)
        press(.left) // Subscriptions
        press(.down)
        usleep(2_000_000)
        attachScreenshot("subscriptions right after subscribing")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Alexandre Chappel'")).firstMatch.exists)
        XCTAssertFalse(app.buttons.matching(subscribeButton).firstMatch.exists, "still on the channel page")

        press(.up, times: 3)
        press(.right, times: 2) // Watch Later
        press(.down)
        usleep(1_500_000)
        attachScreenshot("watch later")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch.exists, "video not in Watch Later")
    }

    /// The basic play path: search, play a result, Menu closes the player, the results are still there.
    func testSearchPlayAndBack() {
        let app = launch(["-search", "blender open movie"])
        XCTAssertTrue(app.buttons.matching(videoCard).firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(move(.down, until: videoCard, in: app), "no result focused: \(focused(app).label)")
        let title = focused(app).label
        press(.select)
        let player = app.otherElements["player"]
        XCTAssertTrue(player.waitForExistence(timeout: 30), "player did not open")
        usleep(5_000_000) // playing for a few seconds
        attachScreenshot("playing")
        for _ in 0 ..< 3 where player.exists { // a first Menu may only hide the transport bar
            press(.menu)
            usleep(1_000_000)
        }
        XCTAssertFalse(player.exists, "player did not close")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch.exists, "results gone after closing the player")
    }
}
