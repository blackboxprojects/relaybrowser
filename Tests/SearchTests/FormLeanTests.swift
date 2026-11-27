import JavaScriptCore
import XCTest
@testable import Relay

/// Fork: the sign-in script only where something of it is switched on.
final class FormLeanTests: XCTestCase {
    func testTheWholeScriptOnlyWithSomethingOfItOn() {
        XCTAssertFalse(FormRelay.wanted(saves: false, fills: false, apple: false, contacts: false, passkeys: false))
        XCTAssertTrue(FormRelay.wanted(saves: true, fills: false, apple: false, contacts: false, passkeys: false))
        XCTAssertTrue(FormRelay.wanted(saves: false, fills: true, apple: false, contacts: false, passkeys: false))
        XCTAssertTrue(FormRelay.wanted(saves: false, fills: false, apple: true, contacts: false, passkeys: false))
        XCTAssertTrue(FormRelay.wanted(saves: false, fills: false, apple: false, contacts: true, passkeys: false))
        XCTAssertTrue(FormRelay.wanted(saves: false, fills: false, apple: false, contacts: false, passkeys: true))
    }

    func testTheLeanScriptIsAFractionOfTheWholeAndReadsAsJavaScript() throws {
        XCTAssertLessThan(FormRelay.lean.count, 3_000)
        XCTAssertGreaterThan(FormRelay.script.count, 50_000)
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("new Function(\(String(decoding: try JSONEncoder().encode(FormRelay.lean), as: UTF8.self)))")
        XCTAssertNil(context.exception, context.exception?.toString() ?? "")
    }

    func testItStillSaysWhereTheCaretIsAndWhenThePageFillsTheScreen() {
        for said in ["kind: 'focus'", "typing: typing", "kind: 'fullscreen'", "officeForms"] {
            XCTAssertTrue(FormRelay.lean.contains(said), said)
        }
        // Nothing of a sign-in's.
        for kept in ["password", "submit"] where kept != "password" {
            XCTAssertFalse(FormRelay.lean.contains("kind: '\(kept)'"), kept)
        }
    }
}

/// Fork: the app's icon on disk, written only when it changes.
final class IconStampTests: XCTestCase {
    func testTheStandardIconOnAnAppNeverStampedIsNothingToDo() {
        XCTAssertFalse(ForkIcon.needsStamp(wanted: "", stamped: nil))
        XCTAssertFalse(ForkIcon.needsStamp(wanted: "", stamped: ""))
        // Back to the standard one after another: taken off, once.
        XCTAssertTrue(ForkIcon.needsStamp(wanted: "", stamped: "hexagons-dark@1"))
    }

    func testTheSameIconOnTheSameBuildIsNotWrittenAgain() {
        let name = ForkIcon.stampName("hexagons", dark: true, build: "202611271000")
        XCTAssertTrue(ForkIcon.needsStamp(wanted: name, stamped: nil))
        XCTAssertFalse(ForkIcon.needsStamp(wanted: name, stamped: name))
        XCTAssertTrue(ForkIcon.needsStamp(wanted: name, stamped: ForkIcon.stampName("hexagons", dark: false, build: "202611271000")))
        // An update is a new app, with no icon of yours on it yet.
        XCTAssertTrue(ForkIcon.needsStamp(wanted: name, stamped: ForkIcon.stampName("hexagons", dark: true, build: "202611260000")))
    }
}
