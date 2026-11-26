import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Fork: a backup brought back (Settings › Custom › Backup › Restore). A day
/// is chosen, and which parts of it: the settings, the tabs, the bookmarks,
/// the containers, the site rules, or all of them. Or a ZIP of such files,
/// from anywhere: what it holds is what is offered.
///
/// Nothing is copied over a running Relay: it holds all of this in memory
/// and writes it out again as it quits. So the chosen files are set aside
/// at once (the day's own folder is written over at the next quit), Relay
/// quits as it always does, and the files go into place as the last thing
/// it does, after everything else has been written. It then comes back
/// reading them. What was there before is kept as a backup of its own,
/// "Before restore", so a restore can be taken back the same way.
enum ForkRestore {
    enum Part: String, CaseIterable, Identifiable {
        case settings, tabs, bookmarks, containers, rules

        var id: String { rawValue }

        var title: String {
            switch self {
            case .settings: return "Settings"
            case .tabs: return "Tabs, pins and spaces"
            case .bookmarks: return "Bookmarks"
            case .containers: return "Containers"
            case .rules: return "Container site rules"
            }
        }

        /// Which part a backed up file belongs to. Whatever has no part of
        /// its own goes with the tabs: the sessions, the windows, the pins
        /// and the spaces only make sense together.
        static func of(_ name: String) -> Part {
            switch name {
            case "settings.plist": return .settings
            case "bookmarks.json": return .bookmarks
            case "containers.json": return .containers
            case "container-rules.json": return .rules
            default: return .tabs
            }
        }
    }

    /// The copy made of what a restore replaced.
    static let before = "Before restore"

    /// Where the chosen files wait for the quit.
    static var staging: URL { Store.file("restore") }

    /// Set by Restore: the quit under way is the one that puts the staged
    /// files in place.
    @MainActor static var armed = false

    /// The backups there are, the newest first, and after them the copy of
    /// what the last restore replaced.
    static func days(in home: URL = ForkBackup.home) -> [String] {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd"
        let folders = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? []
        let names = folders.filter(\.hasDirectoryPath).map(\.lastPathComponent)
        let dated = names.filter { stamp.date(from: $0) != nil }.sorted(by: >)
        return dated + (names.contains(before) ? [before] : [])
    }

    /// A day's files, without the copies iCloud Drive makes of a file two
    /// Macs wrote at once ("pins 2.json").
    static func files(of day: URL) -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: day, includingPropertiesForKeys: nil)) ?? []
        return all.filter { file in
            guard ["json", "plist"].contains(file.pathExtension) else { return false }
            let name = file.deletingPathExtension().lastPathComponent
            return name.range(of: #" \d+$"#, options: .regularExpression) == nil
        }
    }

    /// Whether a file is one Relay backs up, by its name. A ZIP is somebody
    /// else's folder: only these are taken out of it, whatever else it holds.
    static func known(_ name: String) -> Bool {
        if ["settings.plist", "bookmarks.json", "containers.json", "container-rules.json",
            "pins.json", "spaces.json", "windows.json", "session.json"].contains(name) { return true }
        guard name.hasPrefix("session-"), name.hasSuffix(".json") else { return false }
        return UUID(uuidString: String(name.dropFirst(8).dropLast(5))) != nil
    }

    /// Where a ZIP is unpacked to be chosen from.
    static var unpacked: URL { FileManager.default.temporaryDirectory.appendingPathComponent("relay-restore", isDirectory: true) }

    /// A ZIP of backup files, unpacked into a folder that reads as a day
    /// does: the files Relay backs up, wherever in the ZIP they were, and
    /// nothing else. Nil when it holds none of them or can't be opened.
    static func unpack(_ zip: URL, into folder: URL = unpacked) -> URL? {
        let files = FileManager.default
        let raw = folder.appendingPathComponent("raw", isDirectory: true)
        let flat = folder.appendingPathComponent("files", isDirectory: true)
        try? files.removeItem(at: folder)
        guard (try? files.createDirectory(at: raw, withIntermediateDirectories: true)) != nil,
              (try? files.createDirectory(at: flat, withIntermediateDirectories: true)) != nil else { return nil }
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", "-o", zip.path, "-d", raw.path]
        unzip.standardOutput = FileHandle.nullDevice
        unzip.standardError = FileHandle.nullDevice
        guard (try? unzip.run()) != nil else { return nil }
        unzip.waitUntilExit()
        // Real files only, of a size a settings file has: no links out of
        // the folder, and the copy of a name nearest the top wins.
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        var found: [(file: URL, depth: Int)] = []
        if let walk = files.enumerator(at: raw, includingPropertiesForKeys: keys) {
            for case let file as URL in walk {
                guard known(file.lastPathComponent), !file.pathComponents.contains("__MACOSX"),
                      let values = try? file.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true, values.isSymbolicLink != true,
                      (values.fileSize ?? 0) <= 64 * 1024 * 1024 else { continue }
                found.append((file, file.pathComponents.count))
            }
        }
        var taken = 0
        for item in found.sorted(by: { $0.depth < $1.depth }) {
            let to = flat.appendingPathComponent(item.file.lastPathComponent)
            guard !files.fileExists(atPath: to.path) else { continue }
            if (try? files.copyItem(at: item.file, to: to)) != nil { taken += 1 }
        }
        try? files.removeItem(at: raw)
        guard taken > 0 else {
            try? files.removeItem(at: folder)
            return nil
        }
        return flat
    }

    /// The parts a day holds, in the order they are listed.
    static func parts(of day: URL) -> [Part] {
        let held = Set(files(of: day).map { Part.of($0.lastPathComponent) })
        return Part.allCases.filter(held.contains)
    }

    /// The chosen parts of a day, set aside. How many files.
    @discardableResult
    static func stage(_ day: URL, parts: Set<Part>, into staging: URL) throws -> Int {
        let files = FileManager.default
        try? files.removeItem(at: staging)
        let chosen = Self.files(of: day).filter { parts.contains(Part.of($0.lastPathComponent)) }
        guard !chosen.isEmpty else { return 0 }
        try files.createDirectory(at: staging, withIntermediateDirectories: true)
        for file in chosen {
            try files.copyItem(at: file, to: staging.appendingPathComponent(file.lastPathComponent))
        }
        return chosen.count
    }

    /// The staged files put in place, and the staging folder gone. The
    /// settings are handed over rather than written here: they live in the
    /// Mac's defaults, not in the folder.
    @discardableResult
    static func finish(from staging: URL, into folder: URL, settings: ([String: Any]) -> Void) -> Int {
        let files = FileManager.default
        var placed = 0
        for file in Self.files(of: staging) {
            if file.lastPathComponent == "settings.plist" {
                guard let data = try? Data(contentsOf: file),
                      let read = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                else { continue }
                settings(read)
                placed += 1
                continue
            }
            let to = folder.appendingPathComponent(file.lastPathComponent)
            try? files.removeItem(at: to)
            if (try? files.copyItem(at: file, to: to)) != nil { placed += 1 }
        }
        try? files.removeItem(at: staging)
        return placed
    }

    /// Restore pressed: the files set aside, then quit and come back. What
    /// went wrong, in words for Settings, if nothing could be set aside.
    @MainActor static func begin(from folder: URL, parts: Set<Part>) -> String? {
        guard !Store.testing else { return "Not in a test run." }
        do {
            let staged = try stage(folder, parts: parts, into: staging)
            guard staged > 0 else { return "Nothing to restore in that backup." }
        } catch {
            return "Couldn't restore: \(error.localizedDescription)"
        }
        armed = true
        Updater.shared.relaunch()
        return nil
    }

    /// The last thing a quit does, when it is the quit of a restore: what
    /// is there now is kept as "Before restore", then the staged files go
    /// in. False when this quit is an ordinary one.
    @MainActor static func atQuit() -> Bool {
        guard armed, !Store.testing else { return false }
        ForkBackup.run(into: before)
        finish(from: staging, into: Store.folder) { read in
            guard let name = Bundle.main.bundleIdentifier else { return }
            UserDefaults.standard.setPersistentDomain(read, forName: name)
            UserDefaults.standard.synchronize()
        }
        return true
    }
}

/// Fork: the Restore row's choices, under the Backup rows.
struct RestorePanel: View {
    @State private var days = ForkRestore.days()
    @State private var day = ""
    @State private var chosen: Set<ForkRestore.Part> = []
    @State private var said: String?
    @State private var asking = false
    /// A ZIP chosen instead of a day: its name, and where it was unpacked.
    @State private var zip: (name: String, folder: URL)?

    private static let fromZip = "zip"

    /// Where the choice is read from: the ZIP's files, or the day's.
    private var source: URL {
        if day == Self.fromZip, let zip { return zip.folder }
        return ForkBackup.home.appendingPathComponent(day, isDirectory: true)
    }

    private var held: [ForkRestore.Part] { ForkRestore.parts(of: source) }

    private func label(_ day: String) -> String {
        if day == Self.fromZip { return zip?.name ?? "ZIP file" }
        return day == ForkRestore.before ? "Before the last restore" : day
    }

    /// From a ZIP…: a file chosen, and what Relay backs up taken out of it.
    private func chooseZip() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a ZIP of Relay backup files, such as settings.plist, containers.json or container-rules.json."
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let file = panel.url else { return }
        guard let folder = ForkRestore.unpack(file) else {
            said = "No Relay backup files in \(file.lastPathComponent)."
            return
        }
        said = nil
        zip = (file.lastPathComponent, folder)
        day = Self.fromZip
        chosen = Set(held)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if days.isEmpty, zip == nil {
                HStack(spacing: 8) {
                    Text(said ?? "No backup yet.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Spacer()
                    Pill("From a ZIP…") { chooseZip() }
                }
            } else {
                HStack(spacing: 8) {
                    Text("Backup").font(.system(size: 12.5))
                    Picker("", selection: $day) {
                        ForEach(days, id: \.self) { Text(label($0)).tag($0) }
                        if zip != nil {
                            Divider()
                            Text(label(Self.fromZip)).tag(Self.fromZip)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                    Pill("From a ZIP…") { chooseZip() }
                    Spacer()
                    Pill(chosen.count == held.count ? "None" : "All") {
                        chosen = chosen.count == held.count ? [] : Set(held)
                    }
                }
                ForEach(held) { part in
                    Toggle(part.title, isOn: Binding(
                        get: { chosen.contains(part) },
                        set: { on in if on { chosen.insert(part) } else { chosen.remove(part) } }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12.5))
                }
                HStack(spacing: 8) {
                    Text(said ?? "Relay restarts to bring them back. What is there now is kept as “Before the last restore”. Sign-ins are not in a backup.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Pill("Restore and Restart", filled: true) { if !chosen.isEmpty { asking = true } }
                        .opacity(chosen.isEmpty ? 0.4 : 1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onAppear {
            days = ForkRestore.days()
            if day.isEmpty, let first = days.first { day = first }
            chosen = Set(held)
        }
        .onChange(of: day) { chosen = Set(held) }
        .alert("Restore from \(label(day))?", isPresented: $asking) {
            Button("Restore and Restart") { said = ForkRestore.begin(from: source, parts: chosen) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(held.filter(chosen.contains).map(\.title).joined(separator: ", ")) will be replaced by the backup's, and Relay will restart.")
        }
    }
}
