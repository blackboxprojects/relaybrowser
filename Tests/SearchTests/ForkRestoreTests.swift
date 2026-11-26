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

    private func zip(_ place: URL, as name: String) throws -> URL {
        let made = root.appendingPathComponent(name)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", place.path, made.path]
        try ditto.run()
        ditto.waitUntilExit()
        XCTAssertEqual(ditto.terminationStatus, 0)
        return made
    }

    func testOnlyTheNamesRelayBacksUpAreKnown() {
        for name in ["settings.plist", "containers.json", "container-rules.json", "bookmarks.json", "pins.json",
                     "spaces.json", "windows.json", "session.json", "session-E6CAC9BA-8A2F-4D82-A6BD-C60F17F45905.json"] {
            XCTAssertTrue(ForkRestore.known(name), name)
        }
        for name in ["history.json", "evil.json", "session-nope.json", "settings.plist.json", "Info.plist", "containers 2.json", ""] {
            XCTAssertFalse(ForkRestore.known(name), name)
        }
    }

    func testAZipOfThreeFilesRestoresThoseThreeAndNothingElse() throws {
        let packed = root.appendingPathComponent("My backup", isDirectory: true)
        try write("zip containers", "containers.json", in: packed)
        try write("zip rules", "container-rules.json", in: packed)
        try PropertyListSerialization.data(fromPropertyList: ["fork.icon": "kikko"], format: .xml, options: 0)
            .write(to: packed.appendingPathComponent("settings.plist"))
        // Not Relay's: left in the ZIP.
        try write("no", "evil.json", in: packed)
        try write("no", "notes.txt", in: packed)
        try write("no", "history.json", in: packed)
        let file = try zip(packed, as: "backup.zip")

        let folder = try XCTUnwrap(ForkRestore.unpack(file, into: root.appendingPathComponent("unpacked", isDirectory: true)))
        XCTAssertEqual(Set(ForkRestore.files(of: folder).map(\.lastPathComponent)),
                       ["containers.json", "container-rules.json", "settings.plist"])
        XCTAssertEqual(ForkRestore.parts(of: folder), [.settings, .containers, .rules])

        try write("live", "bookmarks.json", in: self.folder)
        try write("live", "containers.json", in: self.folder)
        XCTAssertEqual(try ForkRestore.stage(folder, parts: Set(ForkRestore.parts(of: folder)), into: staging), 3)
        var settings: [String: Any]?
        XCTAssertEqual(ForkRestore.finish(from: staging, into: self.folder) { settings = $0 }, 3)
        XCTAssertEqual(read("containers.json"), "zip containers")
        XCTAssertEqual(read("container-rules.json"), "zip rules")
        XCTAssertEqual(settings?["fork.icon"] as? String, "kikko")
        XCTAssertEqual(read("bookmarks.json"), "live")
        XCTAssertNil(read("evil.json"))
    }

    func testAZipWithNothingOfRelaysOrNoZipAtAllIsRefused() throws {
        let packed = root.appendingPathComponent("Other", isDirectory: true)
        try write("no", "notes.json", in: packed)
        let file = try zip(packed, as: "other.zip")
        let into = root.appendingPathComponent("unpacked", isDirectory: true)
        XCTAssertNil(ForkRestore.unpack(file, into: into))
        XCTAssertFalse(FileManager.default.fileExists(atPath: into.path))
        try Data("not a zip".utf8).write(to: root.appendingPathComponent("fake.zip"))
        XCTAssertNil(ForkRestore.unpack(root.appendingPathComponent("fake.zip"), into: into))
        XCTAssertNil(ForkRestore.unpack(root.appendingPathComponent("missing.zip"), into: into))
    }

    func testALinkInAZipIsNotFollowed() throws {
        let packed = root.appendingPathComponent("Linked", isDirectory: true)
        try write("secret", "outside.txt", in: root)
        try write("fine", "containers.json", in: packed)
        try FileManager.default.createSymbolicLink(
            at: packed.appendingPathComponent("bookmarks.json"), withDestinationURL: root.appendingPathComponent("outside.txt"))
        let file = try zip(packed, as: "linked.zip")
        let folder = try XCTUnwrap(ForkRestore.unpack(file, into: root.appendingPathComponent("unpacked", isDirectory: true)))
        XCTAssertEqual(ForkRestore.files(of: folder).map(\.lastPathComponent), ["containers.json"])
    }
}
