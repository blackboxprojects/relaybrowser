import XCTest
@testable import Relay

/// Fork: the window's buttons at the foot of the tab column.
@MainActor
final class FootLightsTests: XCTestCase {
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

    func testOnlyWithTheTabsDownTheSideAndTheChoiceIsKept() {
        let prefs = Preferences()
        let was = (prefs.sidebar, prefs.lightsAtFoot)
        defer { (prefs.sidebar, prefs.lightsAtFoot) = was }
        prefs.lightsAtFoot = true
        prefs.sidebar = true
        XCTAssertTrue(prefs.lightsFoot)
        XCTAssertTrue(Preferences().lightsAtFoot)
        prefs.sidebar = false
        XCTAssertFalse(prefs.lightsFoot)
    }

    func testAtTheFootTheyTakeNoneOfTheColumnsFirstRow() {
        let prefs = Preferences()
        let was = (prefs.sidebar, prefs.lightsAtFoot)
        defer { (prefs.sidebar, prefs.lightsAtFoot) = was }
        prefs.sidebar = true
        prefs.lightsAtFoot = false
        XCTAssertGreaterThan(SideBar.lights(300, fullScreen: false, fold: false, prefs: prefs), 0)
        prefs.lightsAtFoot = true
        XCTAssertEqual(SideBar.lights(300, fullScreen: false, fold: false, prefs: prefs), 0)
    }

    func testSideBySideOrStackedTheyHoldThree() {
        XCTAssertEqual(FootLights.Kind.allCases, [.close, .minimise, .zoom])
        XCTAssertEqual(FootLights.size(stacked: false), CGSize(width: 52, height: 12))
        XCTAssertEqual(FootLights.size(stacked: true), CGSize(width: 12, height: 52))
        XCTAssertEqual(FootLights.room(stacked: true), 52 + FootLights.above + FootLights.below)
        // No window, nothing to press.
        FootLights.press(.close, in: nil, option: false)
    }
}
