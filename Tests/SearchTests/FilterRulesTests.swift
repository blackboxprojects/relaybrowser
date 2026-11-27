import WebKit
import XCTest
@testable import Relay

/// Fork: filter lists turned into WebKit's rules.
final class FilterRulesTests: XCTestCase {
    private func trigger(_ line: String) -> [String: Any]? {
        switch FilterRules.rule(for: line) {
        case .block(let rule), .hide(let rule), .allow(let rule): return rule["trigger"] as? [String: Any]
        case nil: return nil
        }
    }

    private func action(_ line: String) -> String? {
        switch FilterRules.rule(for: line) {
        case .block(let rule), .hide(let rule), .allow(let rule): return (rule["action"] as? [String: Any])?["type"] as? String
        case nil: return nil
        }
    }

    func testAWholeSiteIsBlockedFromElsewhereAndNeverAsThePageGoneTo() throws {
        let made = try XCTUnwrap(trigger("||doubleclick.net^"))
        XCTAssertEqual(made["url-filter"] as? String, "^[a-z-]+://([^/]+\\.)?doubleclick\\.net[:/]")
        XCTAssertEqual(made["load-type"] as? [String], ["third-party"])
        XCTAssertNil(made["resource-type"])
        XCTAssertEqual(action("||doubleclick.net^"), "block")
    }

    func testAPathWithNoKindNamedIsEveryKindButAPage() throws {
        let made = try XCTUnwrap(trigger("/ads/banner_*.js"))
        XCTAssertEqual(made["url-filter"] as? String, "/ads/banner_.*\\.js")
        XCTAssertEqual(made["resource-type"] as? [String], FilterRules.kinds)
        XCTAssertFalse(FilterRules.kinds.contains("document"))
        XCTAssertNil(made["load-type"])
    }

    func testTheOptionsAreWebKitsOwn() throws {
        let made = try XCTUnwrap(trigger("||example.com/track^$script,xmlhttprequest,third-party,domain=news.com|~sub.news.com"))
        XCTAssertEqual(made["url-filter"] as? String, "^[a-z-]+://([^/]+\\.)?example\\.com/track[^a-zA-Z0-9_.%-]")
        XCTAssertEqual(made["resource-type"] as? [String], ["fetch", "script"])
        XCTAssertEqual(made["load-type"] as? [String], ["third-party"])
        XCTAssertEqual(made["if-domain"] as? [String], ["*news.com"])
        XCTAssertNil(made["unless-domain"])
        XCTAssertEqual(trigger("||a-site.com^$~third-party")?["load-type"] as? [String], ["first-party"])
        XCTAssertEqual(trigger("||cdn.example^$image,domain=~shop.example")?["unless-domain"] as? [String], ["*shop.example"])
    }

    func testFramesAloneAreFramesAndNotThePage() throws {
        let made = try XCTUnwrap(trigger("||ads.example.com^$subdocument"))
        XCTAssertEqual(made["resource-type"] as? [String], ["document"])
        XCTAssertEqual(made["load-context"] as? [String], ["child-frame"])
        // Among other kinds, only another site's.
        XCTAssertEqual(trigger("||x.example.com^$script,subdocument")?["resource-type"] as? [String], ["script"])
        XCTAssertEqual(trigger("||x.example.com^$script,subdocument,third-party")?["resource-type"] as? [String], ["script", "document"])
    }

    func testAnExceptionUndoesWhatCameBefore() throws {
        XCTAssertEqual(action("@@||example.com/ads.js$script"), "ignore-previous-rules")
        let whole = try XCTUnwrap(trigger("@@||bank.example^$document"))
        XCTAssertEqual(whole["url-filter"] as? String, ".*")
        XCTAssertEqual(whole["if-domain"] as? [String], ["*bank.example"])
        guard case .allow = FilterRules.rule(for: "@@||bank.example^$document") else { return XCTFail("an exception") }
    }

    func testAWindowAPageOpensIsBlockedAsItsOwnKind() throws {
        let made = try XCTUnwrap(trigger("||popads.example^$popup"))
        XCTAssertEqual(made["resource-type"] as? [String], ["popup"])
        XCTAssertEqual(action("||popads.example^$popup"), "block")
        XCTAssertEqual(trigger("||x.example^$popup,third-party")?["load-type"] as? [String], ["third-party"])
        // A filter that names no kind is never about windows opened.
        XCTAssertFalse(FilterRules.kinds.contains("popup"))
    }

    func testAnchorsAndSeparators() {
        XCTAssertEqual(FilterRules.pattern(for: "|https://ads.example/")?.expression, "^https://ads\\.example/")
        XCTAssertEqual(FilterRules.pattern(for: "/banner.gif|")?.expression, "/banner\\.gif$")
        XCTAssertEqual(FilterRules.pattern(for: "*/ad?size=*")?.expression, "/ad\\?size=")
        XCTAssertEqual(FilterRules.pattern(for: "||ads.example.com^")?.host, "ads.example.com")
        XCTAssertNil(FilterRules.pattern(for: "||ads.example.com/x")?.host)
        // Too broad to mean anything, or not ASCII.
        XCTAssertNil(FilterRules.pattern(for: "ad"))
        XCTAssertNil(FilterRules.pattern(for: "||реклама.рф^"))
    }

    func testWhatWebKitCannotSayIsLeftOutWhole() {
        for line in [
            "/^https?:\\/\\/ads[0-9]+\\./", "||example.com^$redirect=noop.js", "||example.com^$csp=script-src 'none'",
            "||example.com^$removeparam=utm", "||example.com^$popunder", "||example.com^$document", "||example.com^$domain=example.*",
            "example.com##+js(abort-on-property-read, ads)", "example.com##.ad:has-text(Sponsored)", "example.com#@#.ad",
            "example.com#?#div:-abp-has(.ad)", "example.com##^script:has-text(ads)", "@@||example.com^$generichide",
        ] {
            XCTAssertNil(FilterRules.rule(for: line), line)
        }
    }

    func testHidingByCSSEverywhereOrOnTheSitesNamed() throws {
        let everywhere = try XCTUnwrap(FilterRules.hiding(sites: "", selector: ".ad-banner"))
        guard case .hide(let rule) = everywhere else { return XCTFail("a hiding rule") }
        XCTAssertEqual((rule["trigger"] as? [String: Any])?["url-filter"] as? String, ".*")
        XCTAssertEqual((rule["action"] as? [String: Any])?["selector"] as? String, ".ad-banner")
        XCTAssertEqual(trigger("news.com,blog.org##.promo")?["if-domain"] as? [String], ["*news.com", "*blog.org"])
        XCTAssertEqual(trigger("~news.com##.promo")?["unless-domain"] as? [String], ["*news.com"])
        XCTAssertEqual(action("news.com##.promo"), "css-display-none")
    }

    func testAListKeepsItsThreeKindsApartAndInOrder() throws {
        let made = FilterRules.convert("""
        [Adblock Plus 2.0]
        ! Title: a test
        ||tracker.example^
        ||tracker.example^
        ##.ad
        @@||tracker.example/ok.js$script
        ||odd.example^$redirect=x
        """)
        XCTAssertEqual(made.block.count, 1)
        XCTAssertEqual(made.hide.count, 1)
        XCTAssertEqual(made.allow.count, 1)
        XCTAssertEqual(made.skipped, 1)
        let kinds = made.rules.compactMap { ($0["action"] as? [String: Any])?["type"] as? String }
        XCTAssertEqual(kinds, ["block", "css-display-none", "ignore-previous-rules"])
        // What WebKit is handed is JSON it reads.
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: made.rules))
    }

    /// The real lists, when a folder of them is named: every rule made from
    /// them compiles. RELAY_FILTER_LISTS=/folder/of/txt swift test --filter FilterRulesTests
    @MainActor
    func testTheRealListsCompile() async throws {
        guard let folder = ProcessInfo.processInfo.environment["RELAY_FILTER_LISTS"] else { throw XCTSkip("no lists named") }
        let place = FileManager.default.temporaryDirectory.appendingPathComponent("rules-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: place) }
        let store = try XCTUnwrap(WKContentRuleListStore(url: place))
        for file in try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil)
        where file.pathExtension == "txt" {
            let started = Date()
            let made = FilterRules.convert(try String(contentsOf: file, encoding: .utf8))
            let converted = Date().timeIntervalSince(started)
            let json = String(decoding: try JSONSerialization.data(withJSONObject: made.rules), as: UTF8.self)
            let compiling = Date()
            _ = try await store.compileContentRuleList(forIdentifier: file.lastPathComponent, encodedContentRuleList: json)
            let size = (try? FileManager.default.subpathsOfDirectory(atPath: place.path))?.reduce(0) { total, name in
                total + ((try? FileManager.default.attributesOfItem(atPath: place.appendingPathComponent(name).path)[.size] as? Int) ?? 0)
            } ?? 0
            print("LIST \(file.lastPathComponent): block \(made.block.count) hide \(made.hide.count) allow \(made.allow.count) skipped \(made.skipped) convert \(String(format: "%.2f", converted))s compile \(String(format: "%.2f", Date().timeIntervalSince(compiling)))s store \(size / 1024) KB")
        }
    }
}
