import XCTest
@testable import Relay

/// What `relay://open?profile=<id>&url=<address>` asks for (Links.named):
/// the way another app sends a link to a profile, or, with `space=<id>`, to
/// one space.
final class ProfileLinkTests: XCTestCase {
    private let id = "6F0E4C1A-52B7-4E0B-9C7D-1A2B3C4D5E6F"
    private let other = "E6CAC9BA-8A2F-4D82-A6BD-C60F17F45905"

    private func named(_ text: String) -> (profile: UUID?, space: UUID?, url: URL)? {
        URL(string: text).flatMap(Links.named)
    }

    func testAProfileAndAnEncodedAddress() {
        let link = named("relay://open?profile=\(id)&url=https%3A%2F%2Fexample.com%2Fa%3Fb%3D1%26c%3D2%23d")
        XCTAssertEqual(link?.profile, UUID(uuidString: id))
        XCTAssertEqual(link?.url.absoluteString, "https://example.com/a?b=1&c=2#d")
    }

    func testTheOrderAndTheCaseDoNotMatter() {
        let link = named("RELAY://Open?url=http%3A%2F%2Fexample.com&profile=\(id.lowercased())")
        XCTAssertEqual(link?.profile, UUID(uuidString: id))
        XCTAssertEqual(link?.url.absoluteString, "http://example.com")
    }

    func testAMissingOrBrokenProfileLeavesTheAddress() {
        XCTAssertNil(named("relay://open?url=https%3A%2F%2Fexample.com")?.profile)
        XCTAssertNil(named("relay://open?profile=work&url=https%3A%2F%2Fexample.com")?.profile)
        XCTAssertEqual(named("relay://open?profile=work&url=https%3A%2F%2Fexample.com")?.url.absoluteString,
                       "https://example.com")
    }

    func testASpaceAndAnEncodedAddress() {
        let link = named("relay://open?space=\(other)&url=https%3A%2F%2Fexample.com%2Fa%3Fb%3D1%26c%3D2%23d")
        XCTAssertEqual(link?.space, UUID(uuidString: other))
        XCTAssertNil(link?.profile)
        XCTAssertEqual(link?.url.absoluteString, "https://example.com/a?b=1&c=2#d")
        XCTAssertEqual(named("RELAY://Open?url=http%3A%2F%2Fexample.com&space=\(other.lowercased())")?.space,
                       UUID(uuidString: other))
    }

    func testASpaceAndAProfileAreBothRead() {
        let link = named("relay://open?profile=\(id)&space=\(other)&url=https%3A%2F%2Fexample.com")
        XCTAssertEqual(link?.profile, UUID(uuidString: id))
        XCTAssertEqual(link?.space, UUID(uuidString: other))
    }

    func testAMissingOrBrokenSpaceLeavesTheAddress() {
        XCTAssertNil(named("relay://open?url=https%3A%2F%2Fexample.com")?.space)
        XCTAssertNil(named("relay://open?space=Work&url=https%3A%2F%2Fexample.com")?.space)
        XCTAssertNil(named("relay://open?space=&url=https%3A%2F%2Fexample.com")?.space)
        XCTAssertEqual(named("relay://open?space=Work&url=https%3A%2F%2Fexample.com")?.url.absoluteString,
                       "https://example.com")
    }

    func testASpaceTakesOnlyAWebAddressToo() {
        for address in ["file%3A%2F%2F%2Fetc%2Fpasswd", "javascript%3Aalert(1)", "mailto%3Aa%40example.com",
                        "relay%3A%2F%2Fopen%3Furl%3Dhttps%253A%252F%252Fexample.com", "https%3A%2F%2F", "example.com", ""] {
            XCTAssertNil(named("relay://open?space=\(other)&url=\(address)"), address)
        }
        XCTAssertNil(named("relay://open?space=\(other)"))
    }

    func testOnlyAWebAddressIsTaken() {
        for address in ["file%3A%2F%2F%2Fetc%2Fpasswd", "javascript%3Aalert(1)", "mailto%3Aa%40example.com",
                        "relay%3A%2F%2Fopen%3Furl%3Dhttps%253A%252F%252Fexample.com", "data%3Atext%2Fhtml%2Chi",
                        "https%3A%2F%2F", "example.com", ""] {
            XCTAssertNil(named("relay://open?profile=\(id)&url=\(address)"), address)
        }
        XCTAssertNil(named("relay://open?profile=\(id)"))
        XCTAssertNil(named("relay://open"))
    }

    func testNothingButOpen() {
        XCTAssertNil(named("relay://settings?url=https%3A%2F%2Fexample.com"))
        XCTAssertNil(named("relay:open?url=https%3A%2F%2Fexample.com"))
        XCTAssertNil(named("https://open?url=https%3A%2F%2Fexample.com"))
    }
}
