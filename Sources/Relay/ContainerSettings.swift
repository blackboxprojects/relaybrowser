import AppKit
import SwiftUI
import WebKit

// Fork: the containers' settings, as the SiloTabs extension's page had
// them: the containers, the sites kept to one, whether containers keep to
// their own sites, a tab group per container, and back to normal. The
// containers and rules go into Relay's own backup with everything else.
// Opened from the list's Settings. Every change is kept as it is made.

@MainActor
enum ContainerSettingsWindow {
    private static var window: NSWindow?

    static func show() {
        guard !Store.testing else { return }
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingView(rootView: ContainerSettingsView())
        let made = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        made.title = "Containers"
        made.isReleasedWhenClosed = false
        made.contentView = host
        made.contentMinSize = NSSize(width: 480, height: 360)
        made.center()
        made.makeKeyAndOrderFront(nil)
        window = made
    }
}

struct ContainerSettingsView: View {
    @ObservedObject private var list = ContainerList.shared
    @State private var strict = Containers.strict
    @State private var groups = Containers.groupsTabs
    @State private var host = ""
    @State private var target: UUID?
    @State private var ruleTrouble = ""
    @State private var tick = 0
    @State private var colouring: UUID?
    @State private var deleting: Container?
    @State private var backupSaid = ""
    @State private var resetSaid = ""

    private var rules: [(site: String, container: Container)] {
        let _ = tick
        return Containers.rules.compactMap { site, id in Containers.named(id).map { (site, $0) } }.sorted { $0.site < $1.site }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                GroupBlock(title: "Containers", icon: ContainerGlyph.name) {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            if list.all.isEmpty {
                                Text("No containers yet.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                            }
                            ForEach(list.all) { container in containerRow(container) }
                            Button("New Container") { Containers.add() }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    note("Each container keeps its own sign-ins. Two tabs of one site in different containers are signed in separately. A container given a space is listed only in that space.")
                }
                GroupBlock(title: "Site rules", icon: "arrow.triangle.branch") {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                TextField("Site, like mail.example.com", text: $host)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit(addRule)
                                Picker("", selection: $target) {
                                    ForEach(list.all) { Text($0.name).tag(Optional($0.id)) }
                                }
                                .labelsHidden()
                                .frame(width: 130)
                                Button("Add Rule", action: addRule).disabled(list.all.isEmpty)
                            }
                            if !ruleTrouble.isEmpty {
                                Text(ruleTrouble).font(.system(size: 11)).foregroundStyle(.red)
                            }
                            ForEach(rules, id: \.site) { rule in
                                HStack(spacing: 8) {
                                    Text(rule.site).font(.system(size: 12)).foregroundStyle(Palette.ink)
                                    Spacer(minLength: 0)
                                    Circle().fill(rule.container.tint).frame(width: 9, height: 9)
                                    Text(rule.container.name).font(.system(size: 12)).foregroundStyle(Palette.muted)
                                    Button {
                                        Containers.setRule(rule.site, to: nil)
                                        tick += 1
                                    } label: { Image(systemName: "xmark") }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(Palette.muted)
                                        .help("Remove the rule")
                                }
                            }
                        }
                        .padding(12)
                    }
                    note("A site with a rule always opens in its container, whichever tab the link came from. A rule for example.com covers mail.example.com too; a rule for mail.example.com covers only that address.")
                    Card {
                        SettingRow(icon: "lock.square", title: "Keep containers to their own sites",
                                   detail: "A tab in a container that goes to a site with a rule for another container moves there, and a link to a site with no rule leaves the container, if that container has rules of its own. Off: only new tabs and tabs outside any container follow the rules.") {
                            Switch(on: Binding(get: { strict }, set: { strict = $0; Containers.strict = $0 }))
                        }
                    }
                }
                GroupBlock(title: "Tab groups", icon: "rectangle.3.group") {
                    Card {
                        SettingRow(icon: "rectangle.3.group", title: "A tab group per container",
                                   detail: "A tab opened in a container joins a tab group named after it. Needs tab groups turned on in Settings › Tabs.") {
                            Switch(on: Binding(get: { groups }, set: { groups = $0; Containers.groupsTabs = $0 }))
                        }
                    }
                }
                GroupBlock(title: "Backup", icon: "icloud") {
                    note("Your containers, the space each is in and the site rules are part of Relay's own backup (Settings › Custom › Backup): copied to iCloud Drive › App Data › Relay with everything else, when Relay quits. Sign-ins are not copied; after restoring, sign in again in each container.")
                    HStack(spacing: 8) {
                        Button("Back Up Now") { backupSaid = ForkBackup.run() }
                        Button("Show Backups") { NSWorkspace.shared.open(ForkBackup.home) }
                        if !backupSaid.isEmpty { Text(backupSaid).font(.system(size: 11)).foregroundStyle(Palette.muted) }
                    }
                }
                GroupBlock(title: "Back to normal", icon: "arrow.uturn.backward") {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Button("Put Every Tab Back on Default") {
                                let moved = Containers.backToNormal()
                                tick += 1
                                resetSaid = "\(moved) tab\(moved == 1 ? "" : "s") moved to Default, and the site rules removed."
                            }
                            if !resetSaid.isEmpty {
                                Text(resetSaid).font(.system(size: 11)).foregroundStyle(Palette.muted)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    note("Opens every container's tab again in no container and removes the site rules. The containers and their sign-ins are kept.")
                }
                note("Keys: ⌥⇧A opens the list, ⌥⇧S the next container, ⌥⇧T a temporary session, ⌥⇧D back to Default. Change them in Settings › Shortcuts.")
            }
            .padding(22)
        }
        .frame(minWidth: 480, minHeight: 360)
        .onAppear { target = target ?? list.all.first?.id }
        .onReceive(NotificationCenter.default.publisher(for: Containers.changed)) { _ in
            tick += 1
            if Containers.named(target) == nil { target = list.all.first?.id }
        }
        .alert("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let deleting { Containers.delete(deleting.id) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            let open = deleting.map { Containers.openTabs($0.id) } ?? 0
            Text("Its sign-ins and site data are erased" + (open > 0 ? ", and its \(open) open tab\(open == 1 ? "" : "s") closed." : "."))
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func containerRow(_ container: Container) -> some View {
        HStack(spacing: 8) {
            Button { colouring = container.id } label: {
                Circle().fill(container.tint).frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help("Colour")
            .popover(isPresented: Binding(get: { colouring == container.id }, set: { if !$0 { colouring = nil } })) {
                ColourSwatches(selected: container.colour) {
                    if $0 > 0 { Containers.recolour(container.id, to: $0) }
                    colouring = nil
                }
                .padding(16)
            }
            ContainerNameField(container: container)
            // The space it is offered in: its list and menus there only.
            Picker("", selection: Binding(get: { container.space }, set: { Containers.assign(container.id, to: $0) })) {
                Text("Every Space").tag(UUID?.none)
                Divider()
                ForEach(Spaces.read()) { space in Text(space.name).tag(Optional(space.id)) }
            }
            .labelsHidden()
            .frame(width: 140)
            .help("The space this container is offered in")
            Spacer(minLength: 0)
            Button { deleting = container } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.muted)
                .help("Delete the container and its sign-ins")
        }
    }

    private func addRule() {
        guard let target, let site = Containers.ruleKey(host) else {
            ruleTrouble = list.all.isEmpty ? "Make a container first." : "That isn't a site's address."
            return
        }
        Containers.setRule(site, to: target)
        host = ""
        ruleTrouble = ""
        tick += 1
    }
}

/// A container's name, typed in place: its own text while typing, so the
/// box can be emptied on the way to another name; kept once there is one.
struct ContainerNameField: View {
    let container: Container
    @State private var text = ""

    var body: some View {
        TextField("Name", text: $text)
            .textFieldStyle(.roundedBorder)
            .frame(width: 190)
            .onAppear { text = container.name }
            .onChange(of: text) { _, new in Containers.rename(container.id, to: new) }
    }
}
