import AppKit
import WebKit
import XCTest
@testable import Relay

/// Fork: Multi-Account Containers (Containers.swift).
@MainActor
final class ContainersTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    func testEachContainerHasAStoreOfItsOwnAndATabSaysWhichItIsIn() throws {
        try withBrowser { browser, tabs in
            let work = Containers.add("Work")
            let home = Containers.add("Home")
            defer { Containers.delete(work.id); Containers.delete(home.id) }
            let a = try XCTUnwrap(Containers.store(for: work.id))
            let b = try XCTUnwrap(Containers.store(for: home.id))
            XCTAssertFalse(a === b)
            XCTAssertTrue(a === Containers.store(for: work.id), "one store object per container")
            XCTAssertFalse(a === Spaces.store(for: browser.spaceID))
            XCTAssertTrue(a.isPersistent)

            XCTAssertNil(tabs[0].container)
            browser.newTab(inContainer: work.id)
            let tab = try XCTUnwrap(browser.active)
            XCTAssertEqual(tab.container, work)
            XCTAssertTrue(tab.store === a)
            XCTAssertTrue(Spaces.everyStore.contains { $0 === a })
        }
    }

    func testNewContainerTabReusesItsOwnEmptyTabAndCommandTLeavesItAlone() throws {
        try withBrowser { browser, _ in
            let work = Containers.add("Work")
            defer { Containers.delete(work.id) }
            browser.newTab(inContainer: work.id)
            let first = try XCTUnwrap(browser.active)
            browser.newTab(inContainer: work.id)
            XCTAssertEqual(browser.activeID, first.id, "never two empty tabs of one container")
            let count = browser.tabs.count
            browser.newTab()
            XCTAssertNotEqual(browser.activeID, first.id, "⌘T's tab is in no container")
            XCTAssertNil(browser.active?.container)
            XCTAssertEqual(browser.tabs.count, count + 1)
        }
    }

    func testATabOpenedFromAContainersTabIsInItsContainer() throws {
        try withBrowser { browser, tabs in
            let work = Containers.add("Work")
            defer { Containers.delete(work.id) }
            let url = try XCTUnwrap(URL(string: "https://container-child.example/"))
            let parent = try XCTUnwrap(browser.open(url, inContainer: work.id, foreground: true))
            XCTAssertEqual(parent.container, work)
            let child = browser.open(try XCTUnwrap(URL(string: "https://container-child.example/next")), foreground: false, from: parent)
            XCTAssertEqual(child.container, work)
            let plain = browser.open(url, foreground: false, from: tabs[0])
            XCTAssertNil(plain.container)
        }
    }

    func testReopenInContainerPutsTheAddressInThatContainerWhereTheTabWas() throws {
        try withBrowser { browser, tabs in
            let work = Containers.add("Work")
            defer { Containers.delete(work.id) }
            let address = try XCTUnwrap(tabs[1].address)
            browser.select(tabs[1])
            browser.reopen(tabs[1], inContainer: work.id)
            XCTAssertFalse(browser.tabs.contains { $0.id == tabs[1].id })
            let moved = try XCTUnwrap(browser.tabs.first { $0.container == work })
            XCTAssertEqual(moved.pending ?? moved.address, address)
            XCTAssertEqual(browser.tabs.firstIndex { $0.id == moved.id }, 1)
            XCTAssertEqual(browser.activeID, moved.id)

            browser.reopen(moved, inContainer: nil)
            XCTAssertFalse(browser.tabs.contains { $0.container != nil })
            XCTAssertEqual(browser.tabs.count, 4)
        }
    }

    func testSessionKeepsATabsContainerAndAnOrdinaryTabWritesNone() throws {
        let work = Containers.add("Work")
        defer { Containers.delete(work.id) }
        let entry = Session.Entry(url: "https://kept.example/", title: "Kept", container: work.id)
        let data = try JSONEncoder().encode([entry, Session.Entry(url: "https://plain.example/", title: "Plain")])
        let objects = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(objects[0]["container"] as? String, work.id.uuidString)
        XCTAssertNil(objects[1]["container"])

        let written = try JSONDecoder().decode(Session.Shape.self, from: JSONSerialization.data(withJSONObject: [
            "tabs": [
                ["url": "https://kept.example/", "title": "Kept", "container": work.id.uuidString],
                ["url": "https://plain.example/", "title": "Plain"],
                // A container deleted since: an ordinary tab.
                ["url": "https://gone.example/", "title": "Gone", "container": UUID().uuidString],
            ],
            "active": 0,
        ] as [String: Any]))
        let browser = makeBrowser()
        defer { browser.closeAll() }
        browser.record.rows[browser.spaceID.uuidString] = written
        let row = browser.loadRow(browser.spaceID)
        func tab(_ url: String) throws -> Tab { try XCTUnwrap(row.tabs.first { $0.address?.absoluteString == url }) }
        XCTAssertEqual(try tab("https://kept.example/").container, work)
        XCTAssertNil(try tab("https://plain.example/").container)
        XCTAssertNil(try tab("https://gone.example/").container)
    }

    func testAClosedContainerTabComesBackInItsContainer() throws {
        try withBrowser { browser, _ in
            let work = Containers.add("Work")
            defer { Containers.delete(work.id) }
            let url = try XCTUnwrap(URL(string: "https://closed-container.example/"))
            let tab = try XCTUnwrap(browser.open(url, inContainer: work.id, foreground: true))
            tab.restore(url: url, title: "Closed")
            browser.close(tab)
            XCTAssertFalse(browser.tabs.contains { $0.container != nil })
            browser.reopen()
            XCTAssertEqual(browser.tabs.first { $0.address == url }?.container, work)
        }
    }

    func testDeletingAContainerClosesItsTabsAndForgetsItsStore() throws {
        try withBrowser { browser, _ in
            // Deleting looks in every window there is.
            Browsers.register(browser)
            let work = Containers.add("Work")
            browser.newTab(inContainer: work.id)
            let count = browser.tabs.count
            XCTAssertEqual(Containers.openTabs(work.id), 1)
            Containers.delete(work.id)
            XCTAssertNil(Containers.named(work.id))
            XCTAssertNil(Containers.store(for: work.id))
            XCTAssertFalse(browser.tabs.contains { $0.store.identifier == work.id }, "its tab is closed, not left on its store")
            XCTAssertEqual(browser.tabs.count, count - 1)
            XCTAssertEqual(Containers.read().contains { $0.id == work.id }, false)
        }
    }

    func testNamesStayApartAndRenameAndRecolourAreKept() throws {
        let work = Containers.add("Work")
        let second = Containers.add("work")
        defer { Containers.delete(work.id); Containers.delete(second.id) }
        XCTAssertEqual(second.name, "work 2")
        XCTAssertNotEqual(work.colour, 0)
        Containers.rename(work.id, to: "  Clients ")
        Containers.rename(work.id, to: "   ")
        Containers.recolour(work.id, to: 3)
        Containers.recolour(work.id, to: 0)
        let kept = try XCTUnwrap(Containers.read().first { $0.id == work.id })
        XCTAssertEqual(kept.name, "Clients")
        XCTAssertEqual(kept.colour, 3)
    }

    func testAContainersTabKeepsItsStoreWhenItsSpaceChanges() throws {
        try withBrowser { browser, _ in
            let work = Containers.add("Work")
            defer { Containers.delete(work.id) }
            browser.newTab(inContainer: work.id)
            let tab = try XCTUnwrap(browser.active)
            let store = tab.store
            tab.rehome(in: UUID())
            XCTAssertTrue(tab.store === store)
            XCTAssertEqual(tab.container, work)
        }
    }

    func testAPrivateWindowHasOnePrivateTabAndItsNewTabsArePrivate() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        browser.leaveFiles()
        defer { browser.closeAll() }
        browser.becomePrivate()
        XCTAssertEqual(browser.tabs.count, 1)
        XCTAssertTrue(browser.tabs.allSatisfy(\.shy))
        XCTAssertEqual(browser.active?.shy, true)
        XCTAssertFalse(try XCTUnwrap(browser.active).store.isPersistent)
        browser.newTab()
        XCTAssertTrue(browser.tabs.allSatisfy(\.shy), "⌘T in a private window is private")
    }

    func testTheCrateIsDrawnAsATemplateAtTheSizeAsked() {
        let image = ContainerGlyph.image(16)
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 16, height: 16))
        XCTAssertNotNil(image.tiffRepresentation)
    }

    func testNoContainerIsMadeUntilOneIsAsked() {
        let before = Containers.all.count
        _ = Containers.listed()
        XCTAssertEqual(Containers.all.count, before, "listing makes none")
    }

    func testASiteKeptToAContainerIsFoundByAnyOfItsHostsAndForgottenWithIt() throws {
        let work = Containers.add("Work")
        let site = try XCTUnwrap(Containers.site(of: URL(string: "https://mail.rule-site.example/inbox")))
        XCTAssertEqual(site, Containers.site(of: URL(string: "https://docs.rule-site.example/")))
        XCTAssertNil(Containers.site(of: URL(string: "about:blank")))
        XCTAssertNil(Containers.rule(for: URL(string: "https://mail.rule-site.example/")))
        Containers.setRule(site, to: work.id)
        XCTAssertEqual(Containers.rule(for: URL(string: "https://docs.rule-site.example/a")), work.id)
        XCTAssertEqual(Containers.readRules()[site], work.id, "kept on disk")
        XCTAssertNil(Containers.rule(for: URL(string: "https://other-site.example/")))
        Containers.delete(work.id)
        XCTAssertNil(Containers.rule(for: URL(string: "https://docs.rule-site.example/a")))
        XCTAssertNil(Containers.readRules()[site])
    }

    func testNextContainerGoesRoundThroughDefault() throws {
        try withBrowser { browser, tabs in
            let work = Containers.add("Work")
            let home = Containers.add("Home")
            defer { Containers.delete(work.id); Containers.delete(home.id) }
            let address = try XCTUnwrap(tabs[2].address)
            browser.select(tabs[2])
            let order = Containers.all.map(\.id)
            for expected in order.map(Optional.some) + [nil] {
                browser.cycleContainer()
                let now = try XCTUnwrap(browser.active)
                XCTAssertEqual(now.container?.id, expected)
                XCTAssertEqual(now.pending ?? now.address, address)
            }
            XCTAssertEqual(browser.tabs.count, 4)
        }
    }

    func testATemporarySessionIsThePageAgainInAPrivateTab() throws {
        try withBrowser { browser, tabs in
            let address = try XCTUnwrap(tabs[1].address)
            browser.select(tabs[1])
            browser.temporarySession()
            let shy = try XCTUnwrap(browser.tabs.first(where: \.shy))
            XCTAssertEqual(shy.pending ?? shy.address, address)
            XCTAssertTrue(browser.tabs.contains { $0.id == tabs[1].id }, "the tab it came from stays")
        }
    }

    func testARuleForOneAddressCoversOnlyItAndWinsOverItsSites() throws {
        let work = Containers.add("Work")
        let home = Containers.add("Home")
        defer { Containers.delete(work.id); Containers.delete(home.id) }
        XCTAssertEqual(Containers.ruleKey("  https://www.Mail.Exact-Rule.example:8443/inbox?x=1 "), "mail.exact-rule.example")
        XCTAssertEqual(Containers.ruleKey("exact-rule.example"), "exact-rule.example")
        for bad in ["", "nodots", "has space.example", ".example.com", "example.com.", "javascript:alert(1)"] {
            XCTAssertNil(Containers.ruleKey(bad), bad)
        }
        Containers.setRule("exact-rule.example", to: home.id)
        Containers.setRule("mail.exact-rule.example", to: work.id)
        XCTAssertEqual(Containers.rule(for: URL(string: "https://mail.exact-rule.example/a")), work.id)
        XCTAssertEqual(Containers.rule(for: URL(string: "https://www.mail.exact-rule.example/a")), work.id)
        XCTAssertEqual(Containers.rule(for: URL(string: "https://docs.exact-rule.example/a")), home.id)
        XCTAssertTrue(Containers.hasRules(work.id))
    }

    func testAContainerGivenASpaceIsOfferedOnlyThereAndKeepsItOnDisk() throws {
        let anywhere = Containers.add("Anywhere")
        let here = Containers.add("Here")
        defer { Containers.delete(anywhere.id); Containers.delete(here.id) }
        let space = UUID()
        Containers.assign(here.id, to: space)
        XCTAssertEqual(Set(Containers.listed(in: space).map(\.id)), [anywhere.id, here.id])
        XCTAssertEqual(Containers.listed(in: UUID()).map(\.id), [anywhere.id])
        XCTAssertEqual(Containers.read().first { $0.id == here.id }?.space, space)
        Containers.assign(here.id, to: nil)
        XCTAssertNil(Containers.read().first { $0.id == here.id }?.space)
        // A list written before containers had spaces still reads.
        let old = try JSONDecoder().decode([Container].self, from: Data(#"[{"id":"\#(UUID().uuidString)","name":"Old","colour":2}]"#.utf8))
        XCTAssertNil(old.first?.space)
    }

    func testTheAddressARuleIsKeptUnderIsTheWholeHost() throws {
        XCTAssertEqual(Containers.host(of: URL(string: "https://www.Acme.Tenant-Host.example/tickets?x=1")), "acme.tenant-host.example")
        XCTAssertNil(Containers.host(of: URL(string: "about:blank")))
        let one = Containers.add("One")
        let two = Containers.add("Two")
        defer { Containers.delete(one.id); Containers.delete(two.id) }
        Containers.setRule("acme.tenant-host.example", to: one.id)
        Containers.setRule("other.tenant-host.example", to: two.id)
        XCTAssertEqual(Containers.rule(for: URL(string: "https://acme.tenant-host.example/a")), one.id)
        XCTAssertEqual(Containers.rule(for: URL(string: "https://other.tenant-host.example/a")), two.id)
        XCTAssertNil(Containers.rule(for: URL(string: "https://third.tenant-host.example/a")), "another tenant has no rule")
    }

    func testAContainersTabJoinsTheGroupNamedAfterItWhenAsked() throws {
        try withBrowser { browser, _ in
            let work = Containers.add("Work")
            defer { Containers.delete(work.id); Containers.groupsTabs = false }
            browser.prefs.usesTabGroups = true
            browser.newTab(inContainer: work.id)
            XCTAssertNil(browser.active?.groupID, "off: no group")
            Containers.groupsTabs = true
            let url = try XCTUnwrap(URL(string: "https://grouped.example/"))
            let first = try XCTUnwrap(browser.open(url, inContainer: work.id, foreground: false))
            let group = try XCTUnwrap(browser.tabGroups.first { $0.name == "Work" })
            XCTAssertEqual(first.groupID, group.id)
            XCTAssertEqual(group.colour, work.colour)
            let second = try XCTUnwrap(browser.open(url, inContainer: work.id, foreground: false))
            XCTAssertEqual(second.groupID, group.id)
            XCTAssertEqual(browser.tabGroups.filter { $0.name == "Work" }.count, 1)
        }
    }

    func testBackToNormalMovesEveryContainersTabToDefaultAndDropsTheRules() throws {
        try withBrowser { browser, _ in
            Browsers.register(browser)
            let work = Containers.add("Work")
            defer { Containers.delete(work.id) }
            let url = try XCTUnwrap(URL(string: "https://normal.example/"))
            let tab = try XCTUnwrap(browser.open(url, inContainer: work.id, foreground: false))
            tab.restore(url: url, title: "Normal")
            Containers.setRule("normal.example", to: work.id)
            XCTAssertEqual(Containers.backToNormal(), 1)
            XCTAssertFalse(browser.tabs.contains { $0.container != nil })
            XCTAssertTrue(browser.tabs.contains { ($0.pending ?? $0.address) == url })
            XCTAssertNil(Containers.rule(for: url))
            XCTAssertNotNil(Containers.named(work.id), "the container is kept")
        }
    }

    func testEveryStoreIsAskedToWriteItsCookiesAndTheAskAlwaysEnds() throws {
        let work = Containers.add("Work")
        defer { Containers.delete(work.id) }
        let store = try XCTUnwrap(Containers.store(for: work.id))
        let written = expectation(description: "the stores answered")
        SignInKeeper.flush([store, store, WKWebsiteDataStore.nonPersistent()]) { written.fulfill() }
        let none = expectation(description: "nothing to ask is done at once")
        SignInKeeper.flush([]) { none.fulfill() }
        wait(for: [written, none], timeout: 10)

        var runs = 0
        let once = SignInKeeper.Once { runs += 1 }
        once.run(); once.run()
        XCTAssertEqual(runs, 1)
    }

    func testSiteRulesAreListedByContainerNameThenSite() {
        let work = Containers.add("Work")
        let bank = Containers.add("bank")
        defer {
            for site in ["zebra.example", "apple.example", "mango.example"] { Containers.setRule(site, to: nil) }
            Containers.delete(work.id)
            Containers.delete(bank.id)
        }
        Containers.setRule("zebra.example", to: work.id)
        Containers.setRule("apple.example", to: work.id)
        Containers.setRule("mango.example", to: bank.id)
        let listed = Containers.rulesListed().filter { [work.id, bank.id].contains($0.container.id) }
        XCTAssertEqual(listed.map(\.site), ["mango.example", "apple.example", "zebra.example"])
        XCTAssertEqual(listed.map(\.container.name), ["bank", "Work", "Work"])
    }

    func testAContainersTabOpenedOnAnotherSpaceGoesToItsOwn() throws {
        try withTwoSpaces { browser, personal, work in
            let job = Containers.add("Job")
            defer { Containers.delete(job.id) }
            Containers.assign(job.id, to: work)
            XCTAssertEqual(browser.home(ofContainer: job.id), work)

            // In front: the window goes to the container's space with it.
            let url = try XCTUnwrap(URL(string: "https://job.example/"))
            let tab = try XCTUnwrap(browser.open(url, inContainer: job.id, foreground: true))
            XCTAssertTrue(browser.sendHome(tab, front: true))
            XCTAssertEqual(browser.spaceID, work)
            XCTAssertEqual(browser.activeID, tab.id)
            XCTAssertTrue(browser.tabs.contains { $0.id == tab.id })
            XCTAssertEqual(tab.container?.id, job.id)
            // There, it is at home: nothing more to do.
            XCTAssertNil(browser.home(ofContainer: job.id))
            XCTAssertFalse(browser.sendHome(tab, front: true))

            // Behind: it goes, and the window stays where it is.
            browser.switchSpace(to: personal)
            XCTAssertEqual(browser.spaceID, personal)
            let behind = try XCTUnwrap(browser.open(url, inContainer: job.id, foreground: false))
            XCTAssertTrue(browser.sendHome(behind, front: false))
            XCTAssertEqual(browser.spaceID, personal)
            XCTAssertFalse(browser.tabs.contains { $0.id == behind.id })
            XCTAssertTrue(browser.parked[work]?.tabs.contains { $0.id == behind.id } == true)
        }
    }

    func testAContainerOfEverySpaceOrOfNoneStaysWhereItOpened() throws {
        try withTwoSpaces { browser, personal, _ in
            let anywhere = Containers.add("Anywhere")
            let gone = Containers.add("Gone")
            defer { Containers.delete(anywhere.id); Containers.delete(gone.id) }
            Containers.assign(gone.id, to: UUID())
            let url = try XCTUnwrap(URL(string: "https://anywhere.example/"))
            for id in [anywhere.id, gone.id] {
                let tab = try XCTUnwrap(browser.open(url, inContainer: id, foreground: true))
                XCTAssertNil(browser.home(ofContainer: id))
                XCTAssertFalse(browser.sendHome(tab, front: true))
                XCTAssertEqual(browser.spaceID, personal)
                XCTAssertTrue(browser.tabs.contains { $0.id == tab.id })
            }
            XCTAssertNil(browser.home(ofContainer: nil))
            let plain = try XCTUnwrap(browser.tabs.first { $0.container == nil })
            XCTAssertFalse(browser.sendHome(plain, front: true))
        }
    }

    func testWithoutSpacesAContainersTabStaysToo() throws {
        try withTwoSpaces { browser, _, work in
            let job = Containers.add("Job")
            defer { Containers.delete(job.id) }
            Containers.assign(job.id, to: work)
            browser.prefs.usesSpaces = false
            XCTAssertNil(browser.home(ofContainer: job.id))
        }
    }

    private func withTwoSpaces(_ body: (Browser, UUID, UUID) throws -> Void) throws {
        try withBrowser { browser, _ in
            let uses = browser.prefs.usesSpaces
            let spaces = browser.spaces
            defer {
                browser.prefs.usesSpaces = uses
                browser.spaces = spaces
            }
            browser.prefs.usesSpaces = true
            let personal = browser.spaceID
            let work = UUID()
            browser.spaces = [Space(id: personal, name: "Personal", colour: 0), Space(id: work, name: "Work", colour: 1)]
            try body(browser, personal, work)
        }
    }

    private func withBrowser(_ body: (Browser, [Tab]) throws -> Void) rethrows {
        let browser = makeBrowser()
        let groups = browser.prefs.usesTabGroups
        defer {
            browser.closeAll()
            browser.prefs.usesTabGroups = groups
        }
        browser.prefs.usesTabGroups = false
        try body(browser, browser.tabs)
    }

    private func makeBrowser() -> Browser {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        browser.leaveFiles()
        browser.closeAll()
        browser.record.rows = [:]
        browser.parked = [:]
        browser.tabGroups = []
        for number in 1...4 {
            browser.newTab()
            browser.tabs.last?.restore(
                url: URL(string: "https://container-\(number).example/")!,
                title: "Tab \(number)"
            )
        }
        return browser
    }
}

/// Fork: the dot or the bar a container's tab wears.
final class ContainerMarkTests: XCTestCase {
    func testTheDotUnlessTheBarWasChosen() {
        XCTAssertEqual(ContainerMark.of(nil), .dot)
        XCTAssertEqual(ContainerMark.of("nonsense"), .dot)
        XCTAssertEqual(ContainerMark.of("dot"), .dot)
        XCTAssertEqual(ContainerMark.of("bar"), .bar)
    }

    func testTheBarIsALittleTallerThanTheIconAndClearOfIt() {
        XCTAssertEqual(ContainerMark.barHeight(icon: 15), 21)
        XCTAssertGreaterThan(ContainerMark.barOut, ContainerMark.barWidth)
    }
}
