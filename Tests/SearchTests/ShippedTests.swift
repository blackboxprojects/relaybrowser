import XCTest
@testable import Relay

/// Fork: uBlock Origin Lite, fetched once at first launch (Shipped.swift).
final class ShippedTests: XCTestCase {
    func testAFirstLaunchInstallsIt() {
        XCTAssertEqual(Shipped.step(done: false, installed: [], testing: false), .install)
        XCTAssertEqual(Shipped.step(done: false, installed: ["bfogiafebfohielmmehodmfbbebbbpei"], testing: false), .install)
    }

    func testAlreadyThereItIsOnlyNoted() {
        XCTAssertEqual(Shipped.step(done: false, installed: [Shipped.ublockLite], testing: false), .note)
    }

    func testOnceDoneItIsNeverBroughtBack() {
        // Removed since: the list no longer has it, and it stays removed.
        XCTAssertEqual(Shipped.step(done: true, installed: [], testing: false), .nothing)
        XCTAssertEqual(Shipped.step(done: true, installed: [Shipped.ublockLite], testing: false), .nothing)
    }

    func testATestRunFetchesNothing() {
        XCTAssertEqual(Shipped.step(done: false, installed: [], testing: true), .nothing)
    }

    func testTheIdIsAStoreId() {
        XCTAssertEqual(Shipped.ublockLite.count, 32)
        XCTAssertTrue(Shipped.ublockLite.allSatisfy { ("a"..."p").contains($0) })
    }
}

/// Fork: with the blocker's own lists on, nothing is fetched.
final class ShippedListsTests: XCTestCase {
    func testWithTheListsOnTheExtensionIsNotFetched() {
        XCTAssertEqual(Shipped.step(done: false, installed: [], testing: false, lists: true), .nothing)
        XCTAssertEqual(Shipped.step(done: false, installed: [], testing: false, lists: false), .install)
    }
}
