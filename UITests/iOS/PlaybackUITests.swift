import XCTest

/// The basic play path on iPhone/iPad by touch. Needs network (real YouTube). Run:
/// `xcodebuild test -project FooTube.xcodeproj -scheme FooTube -destination 'platform=iOS Simulator,name=iPhone 17'`.
@MainActor
final class PlaybackUITests: XCTestCase {
    private let videoCard = NSPredicate(format: "label CONTAINS[c] ' views'")

    override func setUp() {
        continueAfterFailure = false
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Search, play a result, close the player with its close button, the results are still there.
    func testSearchPlayAndBack() {
        let app = XCUIApplication()
        // English UI and YouTube responses, so label predicates (" views", "Close") don't depend on the Simulator language.
        app.launchArguments = ["-search", "blender open movie", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let card = app.buttons.matching(videoCard).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30), "no search results")
        let title = card.label
        attachScreenshot("results")
        card.tap()

        let player = app.otherElements["player"]
        XCTAssertTrue(player.waitForExistence(timeout: 30), "player did not open")
        sleep(5) // playing for a few seconds
        attachScreenshot("playing")
        let close = app.buttons["Close"]
        if !close.exists || !close.isHittable {
            player.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() // show the controls
        }
        XCTAssertTrue(close.waitForExistence(timeout: 5), "no close button: \(app.buttons.debugDescription.prefix(1500))")
        close.tap()
        XCTAssertTrue(player.waitForNonExistence(timeout: 10), "player did not close")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch.waitForExistence(timeout: 5), "results gone after closing the player")
    }
}
