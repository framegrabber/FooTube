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
        app.launchArguments = arguments
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
}
