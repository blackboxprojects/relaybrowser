import AppKit
import SwiftUI

/// Fork: a backup brought back (Settings › Custom › Backup › Restore). A day
/// is chosen, and which parts of it: the settings, the tabs, the bookmarks,
/// the containers, the site rules, or all of them.
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
    @MainActor static func begin(day: String, parts: Set<Part>) -> String? {
        guard !Store.testing else { return "Not in a test run." }
        do {
            let staged = try stage(ForkBackup.home.appendingPathComponent(day, isDirectory: true), parts: parts, into: staging)
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

    private var held: [ForkRestore.Part] {
        ForkRestore.parts(of: ForkBackup.home.appendingPathComponent(day, isDirectory: true))
    }

    private func label(_ day: String) -> String {
        day == ForkRestore.before ? "Before the last restore" : day
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if days.isEmpty {
                Text("No backup yet.").font(.system(size: 12)).foregroundStyle(Palette.muted)
            } else {
                HStack(spacing: 8) {
                    Text("Backup").font(.system(size: 12.5))
                    Picker("", selection: $day) {
                        ForEach(days, id: \.self) { Text(label($0)).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 200)
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
            Button("Restore and Restart") { said = ForkRestore.begin(day: day, parts: chosen) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(held.filter(chosen.contains).map(\.title).joined(separator: ", ")) will be replaced by the backup's, and Relay will restart.")
        }
    }
}
