import XCTest
@testable import Relay

/// Fork: the blocker's fetched lists.
final class ShieldListsTests: XCTestCase {
    func testAListIsDueWhenNeverFetchedOrFourDaysOld() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        XCTAssertTrue(ShieldLists.due(fetched: nil, now: now))
        XCTAssertFalse(ShieldLists.due(fetched: now.addingTimeInterval(-3 * 24 * 3600), now: now))
        XCTAssertTrue(ShieldLists.due(fetched: now.addingTimeInterval(-4 * 24 * 3600), now: now))
        // A clock set back: fetched again rather than waited on for years.
        XCTAssertTrue(ShieldLists.due(fetched: now.addingTimeInterval(3600), now: now))
    }

    func testListsMadeByAnOlderConverterAreMadeAgain() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let yesterday = now.addingTimeInterval(-24 * 3600)
        XCTAssertFalse(ShieldLists.due(fetched: yesterday, version: FilterRules.version, now: now))
        XCTAssertTrue(ShieldLists.due(fetched: yesterday, version: FilterRules.version - 1, now: now))
        XCTAssertTrue(ShieldLists.due(fetched: yesterday, version: nil, now: now))
    }

    func testTheCompiledRulesAreNamedForTheListAndWhatIsInIt() {
        let one = ShieldLists.identifier("easylist", rules: Data("a".utf8))
        XCTAssertTrue(one.hasPrefix(ShieldLists.prefix("easylist")))
        XCTAssertEqual(one, ShieldLists.identifier("easylist", rules: Data("a".utf8)))
        XCTAssertNotEqual(one, ShieldLists.identifier("easylist", rules: Data("b".utf8)))
        XCTAssertFalse(one.hasPrefix(ShieldLists.prefix("easyprivacy")))
    }

    func testAPageThatIsNotAListIsRefused() {
        XCTAssertTrue(ShieldLists.looksLikeAList("[Adblock Plus 2.0]\n! Title: EasyList\n||a.example^"))
        XCTAssertFalse(ShieldLists.looksLikeAList("<!doctype html><html><title>Moved</title>"))
    }

    func testTheListsAreFetchedOverHTTPSFromTheirKeepers() {
        XCTAssertEqual(ShieldLists.sources.map(\.id), ["easylist", "easyprivacy"])
        for source in ShieldLists.sources {
            XCTAssertEqual(source.url.scheme, "https")
            XCTAssertEqual(source.url.host, "easylist.to")
        }
    }
}
