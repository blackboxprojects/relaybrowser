import CryptoKit
import XCTest
@testable import Relay

/// Fork: Relay's own release feed. A feed is believed only when the key the
/// build carries signed it, and may only name addresses among the release
/// repository's own releases.
final class ReleaseFeedTests: XCTestCase {
    private let signer = Curve25519.Signing.PrivateKey()
    private var key: String { signer.publicKey.rawRepresentation.base64EncodedString() }

    private func envelope(_ feed: String, signedBy key: Curve25519.Signing.PrivateKey? = nil) throws -> Data {
        let signed = Data(feed.utf8)
        let signature = try (key ?? signer).signature(for: signed)
        return try JSONSerialization.data(withJSONObject: [
            "signed": signed.base64EncodedString(), "signature": signature.base64EncodedString(),
        ])
    }

    func testAFeedTheKeySignedIsOpened() throws {
        let feed = #"{"version":"1.0.21","build":202611251700}"#
        XCTAssertEqual(ReleaseFeed.opened(try envelope(feed), key: key), Data(feed.utf8))
    }

    func testAFeedAnotherKeySignedIsRefused() throws {
        let other = Curve25519.Signing.PrivateKey()
        XCTAssertNil(ReleaseFeed.opened(try envelope(#"{"build":2}"#, signedBy: other), key: key))
    }

    func testAFeedChangedAfterSigningIsRefused() throws {
        let made = try envelope(#"{"build":2}"#)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: made) as? [String: Any])
        json["signed"] = Data(#"{"build":3}"#.utf8).base64EncodedString()
        XCTAssertNil(ReleaseFeed.opened(try JSONSerialization.data(withJSONObject: json), key: key))
    }

    func testWithoutAKeyNoFeedIsBelieved() throws {
        let made = try envelope(#"{"build":2}"#)
        XCTAssertNil(ReleaseFeed.opened(made, key: ""))
        XCTAssertNil(ReleaseFeed.opened(made, key: "not a key"))
    }

    func testGarbageIsNotAFeed() {
        XCTAssertNil(ReleaseFeed.opened(Data(), key: key))
        XCTAssertNil(ReleaseFeed.opened(Data("not json".utf8), key: key))
        XCTAssertNil(ReleaseFeed.opened(Data(#"{"signed":"e30="}"#.utf8), key: key))
    }

    func testTheFeedIsTheLatestReleaseOfTheRepository() {
        let feed = ReleaseFeed.feed.absoluteString
        XCTAssertTrue(feed.hasPrefix("https://github.com/blackboxprojects/relaybrowser/releases/latest/download/appcast"))
        XCTAssertTrue(ReleaseFeed.ours(ReleaseFeed.feed))
    }

    func testOnlyTheRepositorysOwnReleasesAreOurs() throws {
        func ours(_ address: String) throws -> Bool { ReleaseFeed.ours(try XCTUnwrap(URL(string: address))) }
        XCTAssertTrue(try ours("https://github.com/blackboxprojects/relaybrowser/releases/download/v1.0.21/Relay-arm64.zip"))
        XCTAssertTrue(try ours("https://github.com/blackboxprojects/relaybrowser/releases/tag/v1.0.21"))
        XCTAssertFalse(try ours("http://github.com/blackboxprojects/relaybrowser/releases/tag/v1.0.21"))
        XCTAssertFalse(try ours("https://github.com/someone/relaybrowser/releases/download/v9/Relay-arm64.zip"))
        XCTAssertFalse(try ours("https://github.com.example.org/blackboxprojects/relaybrowser/releases/tag/v9"))
        XCTAssertFalse(try ours("https://github.com/blackboxprojects/relaybrowser/releases/../../../someone/else"))
        XCTAssertFalse(try ours("https://officecommun.com/search/Search.zip"))
    }

    func testAnOffSavedBeforeRelaysOwnFeedIsLetGoOnce() throws {
        let name = "relay.test.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        store.set(false, forKey: Updater.installKey)
        Updater.adoptOwnFeed(store)
        XCTAssertNil(store.object(forKey: Updater.installKey), "unset is on")
        // Switched off after that, it stays off.
        store.set(false, forKey: Updater.installKey)
        Updater.adoptOwnFeed(store)
        XCTAssertEqual(store.object(forKey: Updater.installKey) as? Bool, false)
    }
}
