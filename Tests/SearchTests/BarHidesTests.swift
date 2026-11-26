import XCTest
@testable import Relay

/// Fork: the address bar tucked away, and what brings it back.
@MainActor
final class BarHidesTests: XCTestCase {
    override class func setUp() { TestWorld.enter() }

    /// The run's settings as they were, put back whole: a key these tests
    /// wrote that was not there before is taken away again, since a setting
    /// never saved and one saved at its default are not the same to the
    /// tests that come after.
    private var before: [String: Any] = [:]
    override func setUp() { before = Store.settings.dictionaryRepresentation() }
    override func tearDown() {
        let store = Store.settings
        for key in store.dictionaryRepresentation().keys where key.hasPrefix("fork.") || key.hasPrefix("sidebar") || key.hasPrefix("address") {
            if let was = before[key] { store.set(was, forKey: key) } else { store.removeObject(forKey: key) }
        }
    }

    func testOnlyTheEdgeBringsTheBarOut() {
        XCTAssertTrue(ForkBar.holds(distance: 0, out: false))
        XCTAssertTrue(ForkBar.holds(distance: ForkBar.edge, out: false))
        XCTAssertFalse(ForkBar.holds(distance: ForkBar.edge + 1, out: false))
        XCTAssertFalse(ForkBar.holds(distance: 400, out: false))
    }

    func testOutItStaysWhileThePointerIsOnItOrJustOffIt() {
        XCTAssertTrue(ForkBar.holds(distance: 20, out: true))
        XCTAssertTrue(ForkBar.holds(distance: ForkBar.height + ForkBar.slack, out: true))
        XCTAssertFalse(ForkBar.holds(distance: ForkBar.height + ForkBar.slack + 1, out: true))
    }

    func testPastTheEdgeAndOutOfTheWindowStillHoldsIt() {
        XCTAssertTrue(ForkBar.holds(distance: -30, out: false))
        XCTAssertTrue(ForkBar.holds(distance: -30, out: true))
    }

    func testTuckedAwayTheBarIsNoRowOfTheWindowsAndTheChoiceIsKept() {
        let prefs = Preferences()
        let was = (prefs.sidebar, prefs.sideIcons, prefs.addressLine, prefs.topBar, prefs.barAtBottom, prefs.barHides)
        defer { (prefs.sidebar, prefs.sideIcons, prefs.addressLine, prefs.topBar, prefs.barAtBottom, prefs.barHides) = was }
        prefs.sidebar = true
        prefs.sideIcons = true
        prefs.addressLine = true
        prefs.topBar = true
        prefs.barAtBottom = false
        prefs.barHides = false
        XCTAssertTrue(prefs.barTop)
        prefs.barHides = true
        XCTAssertFalse(prefs.barTop)
        XCTAssertTrue(prefs.topRow)
        XCTAssertTrue(Preferences().barHides)
    }
}
