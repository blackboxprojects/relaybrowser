import CryptoKit
import SwiftUI
import WebKit

/// Fork: the lists the blocker takes from the people who keep them (EasyList
/// for advertising, EasyPrivacy for tracking), beside Shield's own few rules.
///
/// They are fetched from their keepers, turned into WebKit's rules
/// (FilterRules) and compiled by WebKit once; WebKit keeps the compiled form
/// on disk, so a launch only looks it up. Nothing here runs in a page: the
/// rules are enforced inside WebKit's networking, in private tabs and
/// containers as anywhere, and no extension is asked.
@MainActor
final class ShieldLists: ObservableObject {
    static let shared = ShieldLists()

    struct Source: Identifiable, Equatable {
        let id: String
        let title: String
        let about: String
        let url: URL
    }

    static let sources = [
        Source(id: "easylist", title: "EasyList", about: "Advertising",
               url: URL(string: "https://easylist.to/easylist/easylist.txt")!),
        Source(id: "easyprivacy", title: "EasyPrivacy", about: "Tracking",
               url: URL(string: "https://easylist.to/easylist/easyprivacy.txt")!),
    ]

    static let onKey = "fork.shieldLists"
    /// On unless switched off (Settings › Custom › Blocking lists).
    static var on: Bool {
        get { Store.settings.object(forKey: onKey) as? Bool ?? true }
        set { Store.settings.set(newValue, forKey: onKey) }
    }

    /// A list is asked for again this long after it was last fetched: its
    /// keepers say four days.
    nonisolated static let fresh: TimeInterval = 4 * 24 * 3600
    nonisolated static func due(fetched: Date?, version: Int? = FilterRules.version, now: Date = Date()) -> Bool {
        guard let fetched, version == FilterRules.version else { return true }
        return now.timeIntervalSince(fetched) >= fresh || fetched > now
    }

    /// What is kept about a list between launches.
    struct Kept: Codable, Equatable {
        var fetched: Date
        /// WebKit's name for the compiled rules.
        var identifier: String
        var rules: Int
        var skipped: Int
        /// The FilterRules that made them; nil for the first.
        var version: Int?
    }

    nonisolated static func identifier(_ id: String, rules data: Data) -> String {
        prefix(id) + SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
    nonisolated static func prefix(_ id: String) -> String { "relay-list-\(id)-" }

    @Published private(set) var kept: [String: Kept] = [:]
    /// What is going on, or went wrong, by list; for Settings.
    @Published private(set) var saying: [String: String] = [:]
    @Published private(set) var busy = false

    private let folder: URL
    private let store: WKContentRuleListStore?
    private var started = false

    init(folder: URL = Store.file("Shield"), store: WKContentRuleListStore? = WKContentRuleListStore.default()) {
        self.folder = folder
        self.store = store
        if let data = try? Data(contentsOf: folder.appendingPathComponent("lists.json")),
           let read = try? JSONDecoder().decode([String: Kept].self, from: data) {
            kept = read
        }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(kept) {
            try? data.write(to: folder.appendingPathComponent("lists.json"), options: .atomic)
        }
    }

    /// At launch, after Shield's own list: what was compiled before is
    /// looked up and put on, and a list never fetched or gone stale is
    /// fetched a little later, when the window is up and its page loading.
    func start() {
        guard Self.on, !started, let store else { return }
        started = true
        for source in Self.sources {
            guard let known = kept[source.id] else { continue }
            store.lookUpContentRuleList(forIdentifier: known.identifier) { found, _ in
                MainActor.assumeIsolated {
                    if let found, Self.on { Shield.shared.install(found, as: source.id) }
                    // Gone from WebKit's store: fetched and compiled again.
                    else if found == nil { self.kept[source.id] = nil }
                }
            }
        }
        guard !Store.testing else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    /// Fetches what is due, or with `all` every list, one after another.
    func update(all: Bool = false) {
        guard Self.on, !busy else { return }
        let wanted = Self.sources.filter { all || Self.due(fetched: kept[$0.id]?.fetched, version: kept[$0.id]?.version) }
        guard !wanted.isEmpty else { return }
        busy = true
        Task {
            for source in wanted { await fetch(source) }
            busy = false
        }
    }

    private func fetch(_ source: Source) async {
        saying[source.id] = "Fetching…"
        var request = URLRequest(url: source.url)
        request.timeoutInterval = 60
        guard let (data, response) = try? await ProxyNetwork.session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8), Self.looksLikeAList(text)
        else {
            saying[source.id] = "Couldn't be fetched"
            return
        }
        saying[source.id] = "Preparing…"
        let made = await Task.detached(priority: .utility) { () -> (json: String, identifier: String, rules: Int, skipped: Int)? in
            let converted = FilterRules.convert(text)
            guard let data = try? JSONSerialization.data(withJSONObject: converted.rules, options: [.sortedKeys]) else { return nil }
            return (String(decoding: data, as: UTF8.self), Self.identifier(source.id, rules: data), converted.count, converted.skipped)
        }.value
        guard let made, made.rules > 0, let store else {
            saying[source.id] = "Couldn't be read"
            return
        }
        let was = kept[source.id]
        if was?.identifier == made.identifier {
            // The same rules as before: only the date moves.
            kept[source.id]?.fetched = Date()
            kept[source.id]?.version = FilterRules.version
            saying[source.id] = nil
            save()
            return
        }
        do {
            let compiled = try await store.compileContentRuleList(forIdentifier: made.identifier, encodedContentRuleList: made.json)
            kept[source.id] = Kept(fetched: Date(), identifier: made.identifier, rules: made.rules, skipped: made.skipped, version: FilterRules.version)
            saying[source.id] = nil
            save()
            if Self.on { Shield.shared.install(compiled, as: source.id) }
            sweep(source.id, keeping: made.identifier)
        } catch {
            saying[source.id] = "WebKit refused it: \(error.localizedDescription)"
        }
    }

    /// A page saying the list is elsewhere is not the list.
    nonisolated static func looksLikeAList(_ text: String) -> Bool {
        let head = text.prefix(400)
        return head.contains("[Adblock") || head.contains("! Title:")
    }

    /// The compiled rules of that list from before, out of WebKit's store.
    private func sweep(_ id: String, keeping identifier: String) {
        guard let store else { return }
        store.getAvailableContentRuleListIdentifiers { identifiers in
            for old in identifiers ?? [] where old != identifier && old.hasPrefix(Self.prefix(id)) {
                store.removeContentRuleList(forIdentifier: old) { _ in }
            }
        }
    }

    /// The switch in Settings: off, the lists come off every page at once
    /// and are kept for the next time; on, they go back or are fetched.
    func set(on: Bool) {
        Self.on = on
        if on {
            started = false
            start()
            if !Store.testing { update() }
        } else {
            for source in Self.sources { Shield.shared.install(nil, as: source.id) }
        }
    }

    /// For Settings: how a list stands.
    func status(of source: Source) -> String {
        if let saying = saying[source.id] { return saying }
        guard let known = kept[source.id] else { return "Not fetched yet" }
        let day = known.fetched.formatted(date: .abbreviated, time: .omitted)
        return "\(known.rules.formatted()) rules, fetched \(day)"
    }
}

/// Settings › Custom › Blocking lists.
struct ShieldListsSettings: View {
    @ObservedObject private var lists = ShieldLists.shared
    @State private var on = ShieldLists.on

    var body: some View {
        GroupBlock(title: "Blocking lists", icon: "shield.lefthalf.filled") {
            Card {
                SettingRow(icon: "list.bullet.rectangle", title: "Block with EasyList and EasyPrivacy",
                           detail: "The lists most blockers use, fetched from their keepers and enforced by WebKit itself, in private tabs and containers too. No extension is needed. Needs Block ads and trackers on in Settings › Privacy.") {
                    Switch(on: Binding(get: { on }, set: { on = $0; lists.set(on: $0) }))
                }
                if on {
                    ForEach(ShieldLists.sources) { source in
                        Rule()
                        SettingRow(icon: "doc.text", title: source.title, detail: "\(source.about). \(lists.status(of: source))") {
                            EmptyView()
                        }
                    }
                    Rule()
                    SettingRow(icon: "arrow.clockwise", title: "Update the lists",
                               detail: "They update on their own every four days.") {
                        Button(lists.busy ? "Updating…" : "Update Now") { lists.update(all: true) }
                            .disabled(lists.busy)
                    }
                }
            }
        }
    }
}
