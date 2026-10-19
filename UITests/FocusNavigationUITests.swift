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

    /// F9: going back up to the tab bar and choosing Search again clears the previous search.
    func testChoosingSearchAgainResetsTheSearch() {
        let app = launch(["-search", "blender open movie"])
        let result = app.buttons.matching(videoCard).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 20))
        XCTAssertTrue(move(.down, until: videoCard, in: app), "no result focused; focus on \(focused(app).debugDescription.prefix(300)); results: \(app.buttons.matching(videoCard).count)")

        press(.up, times: 8) // results → channels → keyboard → tab bar (extra presses are no-ops there)
        press(.select) // choose Search
        usleep(1_500_000)
        attachScreenshot("after choosing Search again")
        XCTAssertFalse(app.buttons.matching(videoCard).firstMatch.exists, "previous results still shown")
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
    /// the tab to its root (and clears the search).
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
}
