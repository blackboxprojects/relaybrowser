import AppKit
import SwiftUI

/// Fork: the tab titles' font, read where they are drawn. Kept beside
/// Preferences (tabFontName) so the rows need not each be handed it.
/// Fork: the bar the address has to itself, top or bottom.
enum ForkBar {
    static let height: CGFloat = 38
}

enum TabFont {
    @MainActor static var name = ""
    /// Compact tabs (Preferences.compactTabs), for the column's statics.
    @MainActor static var compact = false
    /// Between one tab and the next (Preferences.tabGap).
    @MainActor static var gap: CGFloat = 2
    @MainActor static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch name {
        case "": return .system(size: size, weight: weight)
        // Apple's own faces, which macOS keeps out of the list of fonts.
        case "system:mono": return .system(size: size, weight: weight, design: .monospaced)
        case "system:rounded": return .system(size: size, weight: weight, design: .rounded)
        case "system:serif": return .system(size: size, weight: weight, design: .serif)
        default: return .custom(name, fixedSize: size).weight(weight)
        }
    }
}

/// Fork: Settings › Custom. What this build adds, in one place.
struct CustomSettings: View {
    @ObservedObject var prefs: Preferences
    @State private var backedUp: String?
    @State private var restoring = false
    private static let families = NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }

    var body: some View {
        GroupBlock(title: "Tab column", icon: "sidebar.left") {
            Card {
                SettingRow(icon: "square.grid.2x2", title: "Icons only",
                           detail: "The tab column shows each tab's icon without its title.") {
                    Switch(on: $prefs.sideIcons)
                }
                Rule()
                SettingRow(icon: "arrow.left.and.right", title: "Widen on hover",
                           detail: "With icons only, the column opens to full tabs while the pointer is over it.") {
                    Switch(on: $prefs.widensOnHover)
                }
            }
        }
        GroupBlock(title: "Lines", icon: "square.dashed") {
            Card {
                SettingRow(icon: "square", title: "Outlines",
                           detail: "A thin line under the address bar and along the tab column's edge.") {
                    Switch(on: $prefs.showsOutlines)
                }
                Rule()
                SettingRow(icon: "line.diagonal", title: "Group bracket",
                           detail: "With icons only, a thin bar beside the tabs of a group.") {
                    Switch(on: $prefs.groupBracket)
                }
            }
        }
        GroupBlock(title: "Tab rows", icon: "list.bullet") {
            Card {
                SettingRow(icon: "text.alignleft", title: "Align grouped tabs left",
                           detail: "Tabs in a group line up with the other tabs instead of being set in under the group's name.") {
                    Switch(on: $prefs.flushTabs)
                }
                Rule()
                SettingRow(icon: "rectangle.compress.vertical", title: "Compact tabs",
                           detail: "Shorter rows, the same height with icons only as when the column is open.") {
                    Switch(on: $prefs.compactTabs)
                }
                Rule()
                SettingRow(icon: "xmark.circle", title: "Close tabs in groups",
                           detail: "Closing a tab in a group removes it. Off, Relay puts it away instead: the page is unloaded and its row stays in the group, shown with a dash.") {
                    Switch(on: $prefs.closesGrouped)
                }
                Rule()
                SettingRow(icon: "arrow.up.and.down", title: "Space between tabs",
                           detail: "The gap between one tab and the next. Press the number to go back to 2 pt.") {
                    Steps(stops: [0, 1, 2, 3, 4, 5, 6, 8], value: $prefs.tabGap, home: 2) { $0.formatted() + " pt" }
                }
            }
        }
        GroupBlock(title: "Expanding the icons column", icon: "arrow.left.and.right") {
            Card {
                SettingRow(icon: "cursorarrow.motionlines", title: "Expand at the screen's edge",
                           detail: "The column opens when the pointer reaches the edge of the screen, not whenever it is over the column.") {
                    Switch(on: $prefs.widensAtEdge)
                }
                Rule()
                SettingRow(icon: "speedometer", title: "Expand speed",
                           detail: "How long the column takes to open and close. 0 is at once.") {
                    Steps(stops: [0, 0.05, 0.1, 0.15, 0.2, 0.3, 0.4, 0.6], value: $prefs.widenTime, home: 0.2) { $0.formatted() + " s" }
                }
                Rule()
                SettingRow(icon: "timer", title: "Wait before expanding",
                           detail: "How long the pointer must stay before the column opens.") {
                    Steps(stops: [0, 0.05, 0.12, 0.2, 0.3, 0.5, 0.8], value: $prefs.widenDelay, home: 0.12) { $0.formatted() + " s" }
                }
            }
        }
        GroupBlock(title: "Top bar", icon: "menubar.rectangle") {
            Card {
                SettingRow(icon: "link", title: "Show the address",
                           detail: "Keeps the page's address in sight.") {
                    Switch(on: $prefs.addressLine)
                }
                Rule()
                SettingRow(icon: "rectangle.topthird.inset.filled", title: "Address bar across the top",
                           detail: "With icons only, the address, back, forward and reload get a bar of their own above the tab column.") {
                    Switch(on: $prefs.topBar)
                }
                Rule()
                SettingRow(icon: "rectangle.bottomthird.inset.filled", title: "Address bar at the bottom",
                           detail: "Puts that bar along the bottom of the window instead of the top.") {
                    Switch(on: $prefs.barAtBottom)
                }
                Rule()
                SettingRow(icon: "puzzlepiece.extension", title: "Buttons beside the address",
                           detail: "Profile, downloads, bookmarks and extensions sit right of the address instead of in the tab column.") {
                    Switch(on: $prefs.topBarDoors)
                }
            }
        }
        GroupBlock(title: "App icon", icon: "app.dashed") {
            Card {
                SettingRow(icon: "app", title: "Icon",
                           detail: "The icon Relay shows in the Dock while it is open.", wide: true) {
                    HStack(spacing: 10) {
                        ForEach(ForkIconKind.allCases) { kind in
                            let chosen = prefs.iconKind == kind.rawValue
                            Button { prefs.iconKind = kind.rawValue } label: {
                                VStack(spacing: 4) {
                                    Image(nsImage: ForkIcon.preview(kind, dark: ForkIcon.dark(prefs.iconLook)))
                                        .resizable()
                                        .interpolation(.high)
                                        .frame(width: 60, height: 60)
                                    Text(kind.title)
                                        .font(.system(size: 10.5, weight: chosen ? .semibold : .regular))
                                        .foregroundStyle(Palette.ink.opacity(chosen ? 1 : 0.7))
                                }
                                .padding(6)
                                .background(chosen ? Palette.faint : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(chosen ? Palette.ink.opacity(0.45) : Color.clear, lineWidth: 1))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Rule()
                SettingRow(icon: "circle.lefthalf.filled", title: "Light or dark",
                           detail: "Match the Mac's appearance, or keep one. Relay's own icon stays as it is.") {
                    Segmented(options: [("auto", "Match"), ("light", "Light"), ("dark", "Dark")], selection: $prefs.iconLook)
                }
            }
        }
        GroupBlock(title: "Backup", icon: "icloud") {
            Card {
                SettingRow(icon: "icloud.and.arrow.up", title: "Back up when Relay quits",
                           detail: "Copies settings, tabs, tab groups, pins, spaces and bookmarks to iCloud Drive › App Data › Relay, one folder a day, the last seven kept.") {
                    Switch(on: $prefs.backsUp)
                }
                Rule()
                SettingRow(icon: "arrow.clockwise.icloud", title: "Back up now", detail: backedUp ?? "Makes a copy now.") {
                    HStack(spacing: 6) {
                        Pill("Show") { NSWorkspace.shared.open(ForkBackup.home) }
                        Pill("Back Up", filled: true) { backedUp = ForkBackup.run() }
                    }
                }
                Rule()
                SettingRow(icon: "arrow.counterclockwise.icloud", title: "Restore",
                           detail: "Bring back a backup, or a ZIP of backup files: all of it, or only the settings, the tabs, the bookmarks, the containers or the site rules.") {
                    Pill(restoring ? "Close" : "Choose…") { restoring.toggle() }
                }
                if restoring { RestorePanel() }
            }
        }
        GroupBlock(title: "Tab text", icon: "textformat") {
            Card {
                SettingRow(icon: "textformat", title: "Font",
                           detail: "The font of tab and group titles in the column.") {
                    Picker("", selection: $prefs.tabFontName) {
                        Text("System (SF Pro)").tag("")
                        Text("SF Mono").tag("system:mono")
                        Text("SF Rounded").tag("system:rounded")
                        Text("New York").tag("system:serif")
                        Divider()
                        ForEach(CustomSettings.families, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
                Rule()
                SettingRow(icon: "textformat.size", title: "Size",
                           detail: "The size of tab titles. Press the number to go back to the standard size.") {
                    Steps(stops: [9, 9.5, 10, 10.5, 11, 11.5, 12, 12.5, 13, 14, 15, 16],
                          value: Binding(get: { Double(prefs.sideTitle) }, set: { prefs.tabFontSize = $0 }),
                          home: prefs.roomyTabs ? 14 : 12.5) { $0.formatted() + " pt" }
                }
            }
        }
    }
}

/// Fork: Relay's settings and what it keeps of the tabs, copied into iCloud
/// Drive. A folder a day, the last seven kept. ForkRestore brings one back.
enum ForkBackup {
    static let home = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/App Data/Relay", isDirectory: true)

    /// What was done, in words for Settings.
    @discardableResult
    static func run(into name: String? = nil) -> String {
        guard !Store.testing else { return "Not in a test run." }
        let files = FileManager.default
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd"
        // Today's folder, or the one named: what a restore replaces goes
        // into a folder of its own (see ForkRestore).
        let day = home.appendingPathComponent(name ?? stamp.string(from: Date()), isDirectory: true)
        do {
            try files.createDirectory(at: day, withIntermediateDirectories: true)
            var copied = 0
            let kept = try files.contentsOfDirectory(at: Store.folder, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" && !["history.json", "downloads.json", "icloud.json"].contains($0.lastPathComponent) }
            for file in kept {
                let to = day.appendingPathComponent(file.lastPathComponent)
                try? files.removeItem(at: to)
                try files.copyItem(at: file, to: to)
                copied += 1
            }
            if let name = Bundle.main.bundleIdentifier, let domain = UserDefaults.standard.persistentDomain(forName: name) {
                let plain = domain.filter { PropertyListSerialization.propertyList($0.value, isValidFor: .xml) }
                try PropertyListSerialization.data(fromPropertyList: plain, format: .xml, options: 0)
                    .write(to: day.appendingPathComponent("settings.plist"), options: .atomic)
                copied += 1
            }
            // The last seven days, the rest let go.
            let days = try files.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)
                .filter { $0.hasDirectoryPath && stamp.date(from: $0.lastPathComponent) != nil }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            for old in days.dropFirst(7) { try? files.trashItem(at: old, resultingItemURL: nil) }
            return "Backed up \(copied) files to \(day.lastPathComponent)."
        } catch {
            return "Couldn't back up: \(error.localizedDescription)"
        }
    }
}

/// Fork: the chosen icon put in the Dock. Only while Relay runs: the icon
/// in Finder and in the Dock when Relay is closed is the bundle's own.
enum ForkIcon {
    @MainActor private static var previews: [String: NSImage] = [:]

    static var systemDark: Bool { UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" }
    static func dark(_ look: String) -> Bool { look == "dark" || look != "light" && systemDark }

    @MainActor static func preview(_ kind: ForkIconKind, dark: Bool) -> NSImage {
        if kind == .standard { return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath) }
        let key = kind.rawValue + (dark ? "-dark" : "-light")
        if let made = previews[key] { return made }
        let made = ForkIconArt.image(kind, dark: dark, size: 256)
        previews[key] = made
        return made
    }

    @MainActor static func apply() {
        let kind = ForkIconKind(rawValue: Store.settings.string(forKey: "fork.icon") ?? "") ?? .standard
        guard kind != .standard else {
            NSApp.applicationIconImage = nil
            NSApp.dockTile.display()
            stamp(nil)
            return
        }
        // Real pixels, not a picture drawn when asked for: the Dock took the
        // latter only at the next launch.
        let drawn = ForkIconArt.image(kind, dark: dark(Store.settings.string(forKey: "fork.iconLook") ?? "auto"))
        let icon: NSImage
        if let tiff = drawn.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            icon = NSImage(size: drawn.size)
            icon.addRepresentation(rep)
        } else {
            icon = drawn
        }
        NSApp.applicationIconImage = icon
        NSApp.dockTile.display()
        stamp(icon)
    }

    /// The icon put on the app itself too, as Finder's Get Info does it, so
    /// Finder and other docks, which read the app on disk and not the Dock's
    /// tile, show it as well. Nil takes it off again.
    private static func stamp(_ icon: NSImage?) {
        guard !Store.testing else { return }
        let app = Bundle.main.bundlePath
        DispatchQueue.global(qos: .utility).async {
            _ = NSWorkspace.shared.setIcon(icon, forFile: app, options: [])
        }
    }

    /// At launch, and again whenever the Mac goes light or dark.
    @MainActor static func start() {
        apply()
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { MainActor.assumeIsolated { apply() } }
        }
    }
}
