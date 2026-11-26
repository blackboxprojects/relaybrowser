import AppKit
import SwiftUI
import WebKit

// Fork: Multi-Account Containers. A container is a named set of sign-ins:
// its own cookies, storage, caches and service workers, in a WebKit store
// of its own. A tab is opened in one and stays there, and so do the tabs
// its links open, so two accounts of one site can be open side by side,
// each tab signed in as its container is.
//
// It takes the place of the SiloTabs extension, which kept one container
// per site signed in at a time by swapping the site's cookies in and out
// and loading its tabs again. Here nothing is swapped: the store is the
// container.
//
// A tab's container is read from its store (the store's identifier is the
// container's id), so nothing has to be kept in step: a tab made from
// another's configuration, a window a page opens, is in its container
// already. A tab in no container is in its space's store, as before.
//
// Shared by every profile and every space, as the extensions are. Kept in
// containers.json; the session file says which container each tab is in.

struct Container: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    /// One of `Spaces.colours`, never the first (none): the dot on its tabs.
    var colour: Int
    /// The space it is offered in (Settings): its list and menus show it
    /// there only. Nil, as every container starts, is every space.
    var space: UUID? = nil

    var tint: Color {
        Spaces.colours.indices.contains(colour) && colour > 0 ? Spaces.colours[colour] : Spaces.colours[1]
    }
}

@MainActor
enum Containers {
    /// The list changed: a container made, renamed, recoloured or deleted.
    static let changed = Notification.Name("RelayContainersChanged")
    /// ⌥⇧A: the window's toolbar button opens its list. The object is the
    /// window's browser.
    static let show = Notification.Name("RelayContainersShow")

    nonisolated static var file: URL { Store.file("containers.json") }

    private(set) static var all: [Container] = read()
    /// Each container's store, made once: WebKit shares processes between
    /// views that ask for the same store object.
    private static var stores: [UUID: WKWebsiteDataStore] = [:]

    nonisolated static func read() -> [Container] {
        guard let data = try? Data(contentsOf: file),
              let list = try? JSONDecoder().decode([Container].self, from: data) else { return [] }
        var seen = Set<UUID>()
        return list.filter { seen.insert($0.id).inserted }
    }

    /// Read again from the file: a test's, after it wrote one.
    static func reload() {
        rules = readRules()
        all = read()
        ContainerList.shared.all = all
        stores = stores.filter { id, _ in all.contains { $0.id == id } }
    }

    private static func write(_ list: [Container]) {
        all = list
        ContainerList.shared.all = list
        if let data = try? JSONEncoder().encode(list) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
        NotificationCenter.default.post(name: changed, object: nil)
    }

    static func named(_ id: UUID?) -> Container? { id.flatMap { id in all.first { $0.id == id } } }

    /// A container's store, or nil for an id that is no container's (one
    /// deleted since the session was written): the tab is an ordinary one.
    static func store(for id: UUID) -> WKWebsiteDataStore? {
        guard all.contains(where: { $0.id == id }) else { return nil }
        if let made = stores[id] { return made }
        let made = WKWebsiteDataStore(forIdentifier: id)
        if Store.keepsSignIns { Store.followSignIns(made) } else { Store.followCookies(made) }
        BrowserProxy.shared.attach(made)
        stores[id] = made
        return made
    }

    /// The container whose store this is.
    static func container(of store: WKWebsiteDataStore) -> Container? {
        guard store.isPersistent, let id = store.identifier else { return nil }
        return all.first { $0.id == id }
    }

    /// The stores made so far this run.
    static var madeStores: [WKWebsiteDataStore] { Array(stores.values) }
    /// Every container's store, made if it wasn't: for clearing them all.
    static var everyStore: [WKWebsiteDataStore] { all.compactMap { store(for: $0.id) } }

    /// The next colour no container wears yet, or the least worn.
    private static var nextColour: Int {
        let choices = Array(Spaces.colours.indices.dropFirst())
        let worn = Dictionary(grouping: all, by: \.colour).mapValues(\.count)
        return choices.min { (worn[$0] ?? 0, $0) < (worn[$1] ?? 0, $1) } ?? 1
    }

    /// A name no other container has: "Work", then "Work 2".
    static func free(_ wanted: String) -> String {
        let base = wanted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Container"
            : wanted.trimmingCharacters(in: .whitespacesAndNewlines)
        var name = base
        var n = 2
        while all.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            name = "\(base) \(n)"
            n += 1
        }
        return name
    }

    @discardableResult
    static func add(_ name: String = "Container", colour: Int? = nil) -> Container {
        let made = Container(id: UUID(), name: free(name), colour: colour ?? nextColour)
        write(all + [made])
        return made
    }

    /// The list. Empty until a container is made from the toolbar button.
    static func listed() -> [Container] { all }

    /// The containers offered in a space: those given it, and those given none.
    static func listed(in space: UUID) -> [Container] { all.filter { $0.space == nil || $0.space == space } }

    /// nil is every space.
    static func assign(_ id: UUID, to space: UUID?) {
        guard let index = all.firstIndex(where: { $0.id == id }), all[index].space != space else { return }
        var list = all
        list[index].space = space
        write(list)
    }

    // MARK: - Sites that always open in a container

    nonisolated static var rulesFile: URL { Store.file("container-rules.json") }
    /// A site (its registrable domain) to the container it always opens in.
    private(set) static var rules: [String: UUID] = readRules()

    nonisolated static func readRules() -> [String: UUID] {
        guard let data = try? Data(contentsOf: rulesFile) else { return [:] }
        return (try? JSONDecoder().decode([String: UUID].self, from: data)) ?? [:]
    }

    /// The site an address belongs to: mail.example.com is example.com.
    static func site(of url: URL?) -> String? {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host()?.lowercased(), !host.isEmpty
        else { return nil }
        return Vault.registrable(host)
    }

    /// An address's host as a rule names it: lowercased, without www.
    static func host(of url: URL?) -> String? {
        guard site(of: url) != nil, let host = url?.host()?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The container a site always opens in, if it has one that still
    /// exists: the rule for the address itself (mail.example.com), or else
    /// the one for its site (example.com).
    static func rule(for url: URL?) -> UUID? {
        guard let site = site(of: url), let host = url?.host()?.lowercased() else { return nil }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        guard let id = rules[bare] ?? rules[site], all.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    /// What a rule typed in Settings is kept under: the address before the
    /// first slash, without its scheme or www. Nil for what is no address.
    static func ruleKey(_ typed: String) -> String? {
        var text = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let scheme = text.range(of: "://") { text = String(text[scheme.upperBound...]) }
        text = String(text.prefix { $0 != "/" && $0 != "?" && $0 != "#" })
        if let at = text.lastIndex(of: "@") { text = String(text[text.index(after: at)...]) }
        if let port = text.lastIndex(of: ":") { text = String(text[..<port]) }
        if text.hasPrefix("www.") { text = String(text.dropFirst(4)) }
        let fine = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard text.contains("."), !text.hasPrefix("."), !text.hasSuffix("."),
              text.unicodeScalars.allSatisfy(fine.contains) else { return nil }
        return text
    }

    /// Settings › Keep containers to their own sites (Browser.divert).
    static var strict: Bool {
        get { Store.settings.bool(forKey: "containers.strict") }
        set { Store.settings.set(newValue, forKey: "containers.strict") }
    }

    /// Settings › A tab group per container (Browser.joinContainerGroup).
    static var groupsTabs: Bool {
        get { Store.settings.bool(forKey: "containers.groups") }
        set { Store.settings.set(newValue, forKey: "containers.groups") }
    }

    /// Whether any site is kept to this container.
    static func hasRules(_ id: UUID) -> Bool { rules.values.contains(id) }

    /// Settings › Back to normal: every container's tab opened again in no
    /// container, and the site rules removed. The containers and what they
    /// are signed in to stay. Answers how many tabs moved.
    @discardableResult
    static func backToNormal() -> Int {
        for site in rules.keys { setRule(site, to: nil) }
        var moved = 0
        for browser in Browsers.all {
            for tab in browser.tabs where tab.container != nil && browser.recontainable(tab) {
                browser.reopen(tab, inContainer: nil)
                moved += 1
            }
        }
        return moved
    }

    /// nil takes the rule off.
    static func setRule(_ site: String, to id: UUID?) {
        var now = rules
        now[site] = id
        guard now != rules else { return }
        rules = now
        if let data = try? JSONEncoder().encode(now) {
            try? FileManager.default.createDirectory(at: rulesFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: rulesFile, options: .atomic)
        }
        NotificationCenter.default.post(name: changed, object: nil)
    }

    static func rename(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = all.firstIndex(where: { $0.id == id }), all[index].name != name else { return }
        var list = all
        list[index].name = name
        write(list)
    }

    static func recolour(_ id: UUID, to colour: Int) {
        guard colour > 0, Spaces.colours.indices.contains(colour),
              let index = all.firstIndex(where: { $0.id == id }), all[index].colour != colour else { return }
        var list = all
        list[index].colour = colour
        write(list)
    }

    /// How many tabs are open in a container, in every window.
    static func openTabs(_ id: UUID) -> Int {
        Browsers.all.reduce(0) { $0 + $1.tabs.filter { $0.container?.id == id }.count }
    }

    /// A container gone, with its tabs and everything it was signed in to:
    /// its store is emptied now and removed once WebKit lets it go, as a
    /// deleted space's is (Spaces.eraseStore).
    static func delete(_ id: UUID) {
        guard all.contains(where: { $0.id == id }) else { return }
        for browser in Browsers.all {
            for tab in browser.tabs where tab.container?.id == id { browser.close(tab) }
        }
        let store = stores.removeValue(forKey: id)
        for (site, to) in rules where to == id { setRule(site, to: nil) }
        write(all.filter { $0.id != id })
        Spaces.eraseStore(store, id: id)
    }

    /// Signed out everywhere in one container, the container kept.
    static func empty(_ id: UUID, done: @escaping () -> Void = {}) {
        guard let store = store(for: id) else { done(); return }
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { done() }
    }
}

extension Tab {
    /// The container this tab is in, or nil for an ordinary tab. A private
    /// tab is in none: its store is its own and is kept nowhere.
    var container: Container? { shy ? nil : Containers.container(of: store) }
}

/// The list of containers as something a view can watch.
@MainActor
final class ContainerList: ObservableObject {
    static let shared = ContainerList()
    @Published fileprivate(set) var all: [Container] = Containers.all
}

/// The containers' own symbol: a crate seen from the front, its frame
/// mitred at the corners and its panel in slats. Drawn here, in the ink of
/// whatever it sits in, as a symbol is.
enum ContainerGlyph {
    /// In place of a symbol's name, where one is asked for (GroupBlock,
    /// SettingRow): `symbol` gives the crate for it.
    static let name = "relay.containers"

    static func symbol(_ name: String, size: CGFloat) -> Image {
        name == ContainerGlyph.name ? Image(nsImage: image(size)).renderingMode(.template) : Image(systemName: name)
    }

    static func image(_ size: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let line = max(1, size / 24)
            let outer = rect.insetBy(dx: line / 2 + size * 0.04, dy: line / 2 + size * 0.04)
            let inner = outer.insetBy(dx: outer.width * 0.24, dy: outer.height * 0.24)
            NSColor.black.setStroke()
            let path = NSBezierPath(roundedRect: outer, xRadius: size * 0.1, yRadius: size * 0.1)
            path.appendRect(inner)
            // The mitres: each corner of the frame to the panel's.
            let reach = size * 0.03
            for (x, y) in [(0, 0), (1, 0), (0, 1), (1, 1)] as [(CGFloat, CGFloat)] {
                path.move(to: NSPoint(x: outer.minX + x * outer.width + (x == 0 ? reach : -reach),
                                      y: outer.minY + y * outer.height + (y == 0 ? reach : -reach)))
                path.line(to: NSPoint(x: inner.minX + x * inner.width, y: inner.minY + y * inner.height))
            }
            // The slats: five where there is room to tell them apart.
            let slats = size >= 24 ? 5 : 3
            for index in 1..<slats {
                let x = inner.minX + inner.width * CGFloat(index) / CGFloat(slats)
                path.move(to: NSPoint(x: x, y: inner.minY))
                path.line(to: NSPoint(x: x, y: inner.maxY))
            }
            path.lineWidth = line
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// The dot a container's tab wears on its icon, in the container's colour.
struct ContainerDot: View {
    @ObservedObject var tab: Tab
    /// A container recoloured or deleted: its tabs' dots follow.
    @ObservedObject private var list = ContainerList.shared
    var size: CGFloat = 6

    var body: some View {
        if let container = tab.container {
            Circle()
                .fill(container.tint)
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 0.75))
                .offset(x: 2, y: -2)
                .help(container.name)
                .accessibilityLabel("Container: \(container.name)")
        }
    }
}

/// The containers as a menu's rows, each with its colour: New Container
/// Tab, Open Link in Container, Reopen in Container.
struct ContainerMenuRows: View {
    /// The one left out or ticked: the tab's own.
    var current: UUID? = nil
    /// Offers "No Container" too, for a tab that is in one.
    var offersNone = false
    /// The window's space: containers given another space are left out.
    var space: UUID? = nil
    let pick: (UUID?) -> Void
    /// A container made or renamed since the menu was last built.
    @ObservedObject private var list = ContainerList.shared

    var body: some View {
        if offersNone {
            Button("No Container") { pick(nil) }
            Divider()
        }
        ForEach(list.all.filter { space == nil || $0.space == nil || $0.space == space }) { container in
            Button {
                pick(container.id)
            } label: {
                Label {
                    Text(container.name)
                } icon: {
                    Image(nsImage: ContainerMenuRows.swatch(container))
                }
            }
            .disabled(container.id == current)
        }
    }

    /// A menu shows an image as it is and a symbol in the menu's own ink,
    /// so the colour is a picture.
    static func swatch(_ container: Container) -> NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            NSColor(container.tint).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// The toolbar's containers button, beside bookmarks: the crate, with the
/// colour of the container the tab in front is in. A click opens the list.
struct ContainerDoor: View {
    @ObservedObject var browser: Browser
    let arrowEdge: Edge
    @State private var open = false

    var body: some View {
        Door(icon: ContainerGlyph.name, on: open, help: "Containers", shortcut: "containers.list") { open.toggle() }
            .overlay(alignment: .bottomTrailing) {
                if let tab = browser.active { ContainerDot(tab: tab, size: 7).offset(x: -5, y: -3).allowsHitTesting(false) }
            }
            .popover(isPresented: $open, hangingFrom: arrowEdge) {
                ContainersPopup(browser: browser) { open = false }
            }
            .onReceive(NotificationCenter.default.publisher(for: Containers.show)) { note in
                if note.object as? Browser === browser { open.toggle() }
            }
            .accessibilityIdentifier("ContainersDoor")
    }
}

/// The list off the toolbar button. On top, the container the tab in front
/// is in, as a card in that container's colour; under it a field that
/// narrows the list as you type (Return opens the first one left, or makes
/// a container of what was typed when none is); then a row per container,
/// each with its colour down its edge and its open tabs counted in a badge
/// of the same colour. A click on a row opens a new tab in it, Use Here
/// moves the tab in front. The clock is a temporary session, the sliders
/// Settings, where containers are renamed, recoloured and deleted.
struct ContainersPopup: View {
    @ObservedObject var browser: Browser
    let close: () -> Void
    @ObservedObject private var list = ContainerList.shared
    @State private var adding = false
    @State private var name = ""
    @State private var colour = 1
    @State private var query = ""
    @State private var rulesTick = 0
    @FocusState private var naming: Bool
    @FocusState private var searching: Bool

    static let width: CGFloat = 272
    /// The small capitals the card and the rows are labelled in.
    static func label(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .monospaced) }

    private var tab: Tab? { browser.active }
    /// The address in front, as a rule names it: the whole host, so one
    /// tenant of a service (acme.example.com) is kept apart from another.
    private var site: String? { Containers.host(of: tab?.address) }
    private var current: Container? { tab?.container }
    private var movable: Bool { tab.map(browser.recontainable) ?? false }
    private var temporary: Bool { tab?.shy == true }

    /// The containers this space is offered, and those of them the field
    /// leaves: every one whose name has what was typed in it.
    private var offered: [Container] { list.all.filter { $0.space == nil || $0.space == browser.spaceID } }
    private var typed: String { query.trimmingCharacters(in: .whitespaces) }
    private var found: [Container] {
        typed.isEmpty ? offered : offered.filter { $0.name.localizedCaseInsensitiveContains(typed) }
    }
    private var showsDefault: Bool { typed.isEmpty || "Default".localizedCaseInsensitiveContains(typed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            card
            if let site, let current, !temporary {
                let _ = rulesTick
                Toggle(isOn: Binding(get: { Containers.rules[site] == current.id },
                                     set: { Containers.setRule(site, to: $0 ? current.id : nil); rulesTick += 1 })) {
                    Text("Always open \(site) here")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .help("Always open \(site) in \(current.name)")
            }
            search
            VStack(spacing: 3) {
                if showsDefault { row(nil) }
                ForEach(found) { container in row(container) }
                if !showsDefault && found.isEmpty {
                    Text("No container named “\(typed)”. Return makes one.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
            }
            Rectangle().fill(Palette.hairline).frame(height: 1)
            footer
        }
        .padding(10)
        .frame(width: Self.width)
        .onAppear { searching = true }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(nsImage: ContainerGlyph.image(14))
                .renderingMode(.template)
                .foregroundStyle(current?.tint ?? Palette.ink)
            Text("CONTAINERS")
                .font(.system(size: 11, weight: .heavy))
                .kerning(0.6)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
            icon("timer", help: "Temporary session: this site in a tab that starts signed out and keeps nothing") {
                browser.temporarySession(); close()
            }
            icon("slider.horizontal.3", help: "Container Settings") { ContainerSettingsWindow.show(); close() }
        }
    }

    private func icon(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.muted)
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Where the tab in front is, in its container's colour: Default and a
    /// temporary session in grey.
    private var card: some View {
        let tint = temporary ? Color.gray : current?.tint ?? Color(white: 0.42)
        let number = current.flatMap { held in list.all.firstIndex { $0.id == held.id } }.map { $0 + 1 } ?? 0
        let line = tab?.isWeb == true ? (site ?? "This tab") : "New tab"
        return VStack(alignment: .leading, spacing: 0) {
            Text("THIS CONTAINER")
                .font(Self.label(9))
                .kerning(0.8)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(height: 16)
                .background(tint, in: UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6, style: .continuous))
                .padding(.leading, 8)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(line.uppercased())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Text(String(format: "NO. %02d", number))
                }
                .font(Self.label(9))
                .kerning(0.5)
                .foregroundStyle(.white.opacity(0.8))
                Text(temporary ? "Temporary" : current?.name ?? "Default")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("This tab is in " + (temporary ? "a temporary session" : current?.name ?? "no container"))
    }

    private var search: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                TextField("Find or name a container", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searching)
                    .onSubmit(enter)
                if !typed.isEmpty {
                    Text(found.isEmpty && !showsDefault ? "↵ NEW" : "↵ OPEN")
                        .font(Self.label(9))
                        .foregroundStyle(Palette.muted)
                }
            }
            Rectangle().fill(searching ? Palette.muted : Palette.hairline).frame(height: 1)
        }
        .padding(.top, 2)
    }

    @ViewBuilder private var footer: some View {
        if adding {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    TextField("Name, like Work", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($naming)
                        .onSubmit(add)
                    Button("Add", action: add).keyboardShortcut(.defaultAction)
                }
                .controlSize(.small)
                ColourSwatches(selected: colour) { if $0 > 0 { colour = $0 } }
            }
            .onAppear { naming = true }
        } else {
            HStack(spacing: 6) {
                Button { adding = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                        Text("New container").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Palette.ink)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Text(offered.count == 1 ? "1 container" : "\(offered.count) containers")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.muted)
            }
            .frame(height: 20)
        }
    }

    /// Return in the field: a new tab in the first container left, or a
    /// container made of what was typed when none is.
    private func enter() {
        guard !typed.isEmpty else { return }
        if showsDefault && found.isEmpty {
            browser.newTab()
        } else if let first = found.first {
            browser.newTab(inContainer: first.id)
        } else {
            let made = Containers.add(typed)
            browser.newTab(inContainer: made.id)
        }
        close()
    }

    private func add() {
        let made = Containers.add(name, colour: colour)
        name = ""
        adding = false
        colour = made.colour % (Spaces.colours.count - 1) + 1
    }

    /// nil is Default: no container, the space's own sign-ins.
    @ViewBuilder private func row(_ container: Container?) -> some View {
        let here = !temporary && tab?.isWeb == true && current?.id == container?.id
        let tabs = container.map { Containers.openTabs($0.id) }
            ?? browser.tabs.filter { $0.container == nil && !$0.shy }.count
        ContainerRow(container: container, here: here, tabs: tabs, usable: movable && !here,
                     open: {
                         if let container { browser.newTab(inContainer: container.id) } else { browser.newTab() }
                         close()
                     },
                     use: {
                         if let tab { browser.reopen(tab, inContainer: container?.id) }
                         close()
                     })
    }
}

/// One container in the list: its colour down the leading edge, its name
/// over where it stands (here, and how many tabs it has open), and that
/// count again in a badge of its colour at the far end.
private struct ContainerRow: View {
    let container: Container?
    let here: Bool
    let tabs: Int
    let usable: Bool
    let open: () -> Void
    let use: () -> Void
    @State private var hovering = false

    private var tint: Color { container?.tint ?? Color(white: 0.5) }
    private var standing: String {
        let count = tabs == 0 ? "NO TABS" : tabs == 1 ? "1 TAB" : "\(tabs) TABS"
        return here ? "HERE · " + count : count
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: open) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(tint)
                        .frame(width: 3, height: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(container?.name ?? "Default")
                            .font(.system(size: 12, weight: here ? .bold : .medium))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Text(standing)
                            .font(ContainersPopup.label(8.5))
                            .kerning(0.4)
                            .foregroundStyle(here ? tint : Palette.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 5)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(container.map { "New tab in \($0.name)" } ?? "New tab in no container")
            if usable && hovering {
                Button("Use Here", action: use)
                    .controlSize(.mini)
                    .padding(.trailing, 6)
                    .help("Open this page again in " + (container?.name ?? "Default"))
            }
            Text("\(tabs)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 26)
                .frame(maxHeight: .infinity)
                .background(tint.opacity(tabs == 0 ? 0.45 : 1),
                            in: UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: 6, style: .continuous))
                .accessibilityLabel(tabs == 1 ? "1 tab open" : "\(tabs) tabs open")
        }
        .frame(height: 32)
        .background((here ? tint.opacity(0.16) : hovering ? Palette.wash : tint.opacity(0.07)),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { hovering = $0 }
    }
}
