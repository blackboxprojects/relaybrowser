import XCTest
@testable import Relay

/// Fork: a backup brought back, in whole or in part. The chosen files are
/// set aside first and put in place last; nothing outside the choice moves.
final class ForkRestoreTests: XCTestCase {
    private var root: URL!
    private var home: URL { root.appendingPathComponent("backups", isDirectory: true) }
    private var folder: URL { root.appendingPathComponent("live", isDirectory: true) }
    private var staging: URL { folder.appendingPathComponent("restore", isDirectory: true) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ text: String, _ name: String, in place: URL) throws {
        try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: place.appendingPathComponent(name))
    }

    private func read(_ name: String) -> String? {
        (try? Data(contentsOf: folder.appendingPathComponent(name))).map { String(decoding: $0, as: UTF8.self) }
    }

    private func day(_ name: String, settings: [String: Any]? = ["fork.icon": "kikko"]) throws -> URL {
        let day = home.appendingPathComponent(name, isDirectory: true)
        for file in ["bookmarks.json", "containers.json", "container-rules.json", "session.json", "spaces.json", "pins.json"] {
            try write("backup \(file)", file, in: day)
        }
        if let settings {
            try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0)
                .write(to: day.appendingPathComponent("settings.plist"))
        }
        return day
    }

    func testTheNewestBackupComesFirstAndTheOneBeforeARestoreLast() throws {
        _ = try day("2026-11-24")
        _ = try day("2026-11-25")
        _ = try day(ForkRestore.before)
        try write("x", "notes.json", in: home.appendingPathComponent("Something else", isDirectory: true))
        XCTAssertEqual(ForkRestore.days(in: home), ["2026-11-25", "2026-11-24", ForkRestore.before])
        XCTAssertEqual(ForkRestore.days(in: root.appendingPathComponent("nowhere")), [])
    }

    func testEachFileHasItsPart() {
        XCTAssertEqual(ForkRestore.Part.of("settings.plist"), .settings)
        XCTAssertEqual(ForkRestore.Part.of("bookmarks.json"), .bookmarks)
        XCTAssertEqual(ForkRestore.Part.of("containers.json"), .containers)
        XCTAssertEqual(ForkRestore.Part.of("container-rules.json"), .rules)
        for name in ["session.json", "session-E6CAC9BA.json", "windows.json", "spaces.json", "pins.json"] {
            XCTAssertEqual(ForkRestore.Part.of(name), .tabs, name)
        }
    }

    func testADayOffersOnlyThePartsItHolds() throws {
        XCTAssertEqual(ForkRestore.parts(of: try day("2026-11-25")), ForkRestore.Part.allCases)
        let thin = home.appendingPathComponent("2026-11-20", isDirectory: true)
        try write("b", "bookmarks.json", in: thin)
        XCTAssertEqual(ForkRestore.parts(of: thin), [.bookmarks])
    }

    func testICloudsCopiesOfAFileAreLeftOut() throws {
        let day = try day("2026-11-25")
        try write("stale", "pins 2.json", in: day)
        try write("stale", "container-rules 3.json", in: day)
        let names = ForkRestore.files(of: day).map(\.lastPathComponent)
        XCTAssertFalse(names.contains("pins 2.json"))
        XCTAssertFalse(names.contains("container-rules 3.json"))
        XCTAssertTrue(names.contains("pins.json"))
    }

    func testOnlyTheChosenPartsAreBroughtBack() throws {
        let day = try day("2026-11-25")
        for file in ["bookmarks.json", "containers.json", "container-rules.json", "session.json"] {
            try write("live \(file)", file, in: folder)
        }
        XCTAssertEqual(try ForkRestore.stage(day, parts: [.rules], into: staging), 1)
        var settings: [String: Any]?
        XCTAssertEqual(ForkRestore.finish(from: staging, into: folder) { settings = $0 }, 1)
        XCTAssertEqual(read("container-rules.json"), "backup container-rules.json")
        XCTAssertEqual(read("containers.json"), "live containers.json")
        XCTAssertEqual(read("bookmarks.json"), "live bookmarks.json")
        XCTAssertEqual(read("session.json"), "live session.json")
        XCTAssertNil(settings)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
    }

    func testEverythingIsBroughtBackWithTheSettingsHandedOver() throws {
        let day = try day("2026-11-25")
        try write("live", "bookmarks.json", in: folder)
        try write("live", "history.json", in: folder)
        XCTAssertEqual(try ForkRestore.stage(day, parts: Set(ForkRestore.Part.allCases), into: staging), 7)
        var settings: [String: Any]?
        XCTAssertEqual(ForkRestore.finish(from: staging, into: folder) { settings = $0 }, 7)
        XCTAssertEqual(settings?["fork.icon"] as? String, "kikko")
        XCTAssertEqual(read("bookmarks.json"), "backup bookmarks.json")
        XCTAssertEqual(read("spaces.json"), "backup spaces.json")
        // Never in a backup, so never touched, and the settings are not a
        // file in the folder.
        XCTAssertEqual(read("history.json"), "live")
        XCTAssertNil(read("settings.plist"))
    }

    func testSettingsAloneLeaveEveryFileAsItWas() throws {
        let day = try day("2026-11-25")
        try write("live", "bookmarks.json", in: folder)
        XCTAssertEqual(try ForkRestore.stage(day, parts: [.settings], into: staging), 1)
        var settings: [String: Any]?
        ForkRestore.finish(from: staging, into: folder) { settings = $0 }
        XCTAssertNotNil(settings)
        XCTAssertEqual(read("bookmarks.json"), "live")
    }

    func testTheChoiceIsSetAsideSoTheDayCanBeWrittenOver() throws {
        let day = try day("2026-11-25")
        try ForkRestore.stage(day, parts: [.bookmarks], into: staging)
        // The quit backs up over the day it is restoring from.
        try write("written over", "bookmarks.json", in: day)
        ForkRestore.finish(from: staging, into: folder) { _ in }
        XCTAssertEqual(read("bookmarks.json"), "backup bookmarks.json")
    }

    func testAnEarlierChoiceLeftBehindIsNotBroughtBackToo() throws {
        let day = try day("2026-11-25")
        try ForkRestore.stage(day, parts: [.bookmarks], into: staging)
        XCTAssertEqual(try ForkRestore.stage(day, parts: [.containers], into: staging), 1)
        ForkRestore.finish(from: staging, into: folder) { _ in }
        XCTAssertNil(read("bookmarks.json"))
        XCTAssertEqual(read("containers.json"), "backup containers.json")
    }

    func testNothingChosenStagesNothing() throws {
        let day = try day("2026-11-25")
        XCTAssertEqual(try ForkRestore.stage(day, parts: [], into: staging), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertEqual(ForkRestore.finish(from: staging, into: folder) { _ in }, 0)
    }
}
