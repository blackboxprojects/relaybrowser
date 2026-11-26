import AppKit
import Network
import SwiftUI
import UniformTypeIdentifiers
import WebKit

// Fork: a VPN for private tabs only (Settings › Custom › Private VPN). A
// WireGuard file, as a VPN provider hands one out, is chosen once; with the
// switch on, every private tab's pages go out through that tunnel and every
// other tab goes out as it always did.
//
// Relay does not speak WireGuard. A helper does: wireproxy, an open-source
// program that holds the tunnel inside its own process and offers it as a
// SOCKS5 proxy on this Mac alone. Relay fetches one pinned release of it,
// checked against its hash, only when asked to in Settings; runs it while
// the switch is on; and gives each private tab's store that proxy. Nothing
// is installed in the system, and no other app's traffic changes.
//
// Closed when in doubt: with the switch on and the tunnel not up (no file,
// no helper, the helper stopped), a private tab's store is pointed at an
// address nothing answers, so its pages fail rather than go out directly.

/// The WireGuard file, read and rewritten for the helper.
enum WireGuardFile {
    /// What the helper is given of each section. Anything else in the file
    /// (wg-quick's PostUp and the like, which would run commands; sections
    /// that open listeners of their own) is left out.
    private static let kept: [String: Set<String>] = [
        "interface": ["privatekey", "address", "dns", "mtu"],
        "peer": ["publickey", "presharedkey", "endpoint", "allowedips", "persistentkeepalive"],
    ]

    private struct Section {
        let name: String
        var lines: [(key: String, value: String)]
    }

    private static func sections(_ text: String) -> [Section] {
        var found: [Section] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";") else { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                found.append(Section(name: String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces).lowercased(), lines: []))
                continue
            }
            guard let equals = line.firstIndex(of: "="), !found.isEmpty else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            found[found.count - 1].lines.append((key, value))
        }
        return found
    }

    private static func value(_ key: String, in section: Section) -> String? {
        section.lines.first { $0.key.lowercased() == key }?.value
    }

    /// Why a file can't be used, or nil when it can.
    static func problem(_ text: String) -> String? {
        let all = sections(text)
        guard let interface = all.first(where: { $0.name == "interface" }),
              let peer = all.first(where: { $0.name == "peer" }) else {
            return "This isn't a WireGuard file: it needs an [Interface] and a [Peer] section."
        }
        guard value("privatekey", in: interface)?.isEmpty == false else { return "The file has no PrivateKey." }
        guard value("address", in: interface)?.isEmpty == false else { return "The file has no Address." }
        guard value("publickey", in: peer)?.isEmpty == false else { return "The file's peer has no PublicKey." }
        guard value("endpoint", in: peer)?.isEmpty == false else { return "The file's peer has no Endpoint." }
        return nil
    }

    /// The server the file connects to, for Settings to show.
    static func endpoint(_ text: String) -> String? {
        sections(text).first { $0.name == "peer" }.flatMap { value("endpoint", in: $0) }
    }

    /// The helper's own file: the tunnel as the WireGuard file has it, and
    /// one SOCKS5 proxy on this Mac alone, behind a name and password made
    /// for this run so no other program here can use the tunnel.
    static func helperConfig(_ text: String, port: UInt16, user: String, password: String) -> String {
        var out: [String] = []
        for section in sections(text) {
            guard let keys = kept[section.name] else { continue }
            out.append(section.name == "interface" ? "[Interface]" : "[Peer]")
            for line in section.lines where keys.contains(line.key.lowercased()) {
                // One line each: a value can't carry a second setting in.
                let value = line.value.components(separatedBy: .newlines).first ?? ""
                out.append("\(line.key) = \(value)")
            }
            out.append("")
        }
        out += ["[Socks5]", "BindAddress = 127.0.0.1:\(port)", "Username = \(user)", "Password = \(password)", ""]
        return out.joined(separator: "\n")
    }
}

/// What a private tab's store, and a private tab's icon fetched off the main
/// thread, is given. Kept apart from the main actor, as ProxyNetwork is.
enum PrivateVPNProxy {
    nonisolated(unsafe) private static var current: ProxyConfiguration?
    private static let lock = NSLock()

    /// Nil with the switch off: a private tab then goes out as Settings ›
    /// Privacy › Proxy says, like any other tab.
    static var configuration: ProxyConfiguration? {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    static func keep(_ proxy: ProxyConfiguration?) {
        lock.lock()
        current = proxy
        lock.unlock()
    }

    /// A proxy on this Mac. Never a way round: unreachable, the request fails.
    static func local(port: UInt16, user: String? = nil, password: String? = nil) -> ProxyConfiguration {
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? 9)
        var proxy = ProxyConfiguration(socksv5Proxy: endpoint)
        proxy.allowFailover = false
        if let user, let password { proxy.applyCredential(username: user, password: password) }
        return proxy
    }

    /// With the switch on and no tunnel: the discard port, which nothing
    /// answers, so a private page fails instead of going out directly.
    static var closed: ProxyConfiguration { local(port: 9) }
}

@MainActor
final class PrivateVPN: ObservableObject {
    static let shared = PrivateVPN()
    static let onKey = "fork.privateVPN"

    /// The helper, one release of it, by its hash. Published by its author
    /// at github.com/pufferffish/wireproxy (ISC licence).
    struct Pin {
        let version: String
        let url: URL
        let sha256: String
        let size: Int64
    }

    static var pin: Pin {
        #if arch(x86_64)
        return Pin(version: "1.1.3",
                   url: URL(string: "https://github.com/pufferffish/wireproxy/releases/download/v1.1.3/wireproxy_darwin_amd64.tar.gz")!,
                   sha256: "5d89742a0f381d9508d3ad828a0d300dceee24fa49015427eaff42a23f7a50bd", size: 4_146_302)
        #else
        return Pin(version: "1.1.3",
                   url: URL(string: "https://github.com/pufferffish/wireproxy/releases/download/v1.1.3/wireproxy_darwin_arm64.tar.gz")!,
                   sha256: "28d34342c48c309b628d9c06ab4efc05b82fba49821f360605c02139c02547a5", size: 3_877_619)
        #endif
    }

    enum State: Equatable {
        case off, needsFile, needsHelper, starting, running, stopped(String)

        var words: String {
            switch self {
            case .off: return "Off. Private tabs go out like any other tab."
            case .needsFile: return "On, but there is no WireGuard file: private tabs load nothing until one is chosen."
            case .needsHelper: return "On, but the helper isn't downloaded: private tabs load nothing until it is."
            case .starting: return "Connecting…"
            case .running: return "Private tabs go through the VPN."
            case .stopped(let why): return "The VPN stopped, so private tabs load nothing. \(why)"
            }
        }
    }

    @Published private(set) var state: State = .off
    @Published private(set) var endpoint: String?
    @Published private(set) var hasHelper = false
    @Published private(set) var fetching: Double?
    @Published var said: String?
    /// A fetch of the helper failed this run: start() doesn't keep trying.
    private var failed = false

    private let folder = Store.file("PrivateVPN")
    private var file: URL { folder.appendingPathComponent("wireguard.conf") }
    private var helper: URL { folder.appendingPathComponent("wireproxy") }
    private var runFile: URL { folder.appendingPathComponent("run.conf") }
    private var pidFile: URL { folder.appendingPathComponent("helper.pid") }

    private var process: Process?
    private var lastLine = ""
    private let stores = NSHashTable<WKWebsiteDataStore>.weakObjects()

    var on: Bool { Store.settings.bool(forKey: Self.onKey) }
    var hasFile: Bool { endpoint != nil }

    private init() {
        refresh()
    }

    private func refresh() {
        endpoint = (try? String(contentsOf: file, encoding: .utf8)).flatMap { WireGuardFile.problem($0) == nil ? WireGuardFile.endpoint($0) : nil }
        hasHelper = FileManager.default.isExecutableFile(atPath: helper.path)
    }

    // MARK: - the stores

    /// A private tab's store, as it is made (Web.configuration), after the
    /// browser's own proxy was put on it: the VPN's takes its place.
    func attach(_ store: WKWebsiteDataStore) {
        stores.add(store)
        if let proxy = PrivateVPNProxy.configuration { store.proxyConfigurations = [proxy] }
    }

    /// Every private store given what stands now. With the switch off they
    /// are given the browser's own proxy back.
    func restamp() {
        let vpn = PrivateVPNProxy.configuration
        let plain = [ProxyNetwork.configuration].compactMap { $0 }
        for store in stores.allObjects { store.proxyConfigurations = vpn.map { [$0] } ?? plain }
    }

    private func use(_ proxy: ProxyConfiguration?) {
        PrivateVPNProxy.keep(proxy)
        restamp()
    }

    // MARK: - the switch

    func set(on: Bool) {
        Store.settings.set(on, forKey: Self.onKey)
        if on { start() } else { stop(); state = .off; use(nil) }
    }

    /// At launch, and whenever the switch, the file or the helper changes.
    func start() {
        guard !Store.testing, on else { return }
        stop()
        refresh()
        // Closed first: nothing private goes out until the tunnel is up.
        use(PrivateVPNProxy.closed)
        guard let text = try? String(contentsOf: file, encoding: .utf8), WireGuardFile.problem(text) == nil else {
            state = .needsFile
            return
        }
        // Fetched without being asked for again: choosing a file or turning
        // the switch on is the asking.
        guard hasHelper else { state = .needsHelper; if !failed { fetchHelper() }; return }
        guard let port = Self.freePort() else { state = .stopped("No free port on this Mac."); return }
        let user = "relay", password = UUID().uuidString + UUID().uuidString
        do {
            try Self.writePrivately(WireGuardFile.helperConfig(text, port: port, user: user, password: password), to: runFile)
        } catch {
            state = .stopped(error.localizedDescription)
            return
        }
        Self.endLeftOver(pidFile: pidFile, helper: helper)
        let run = Process()
        run.executableURL = helper
        run.arguments = ["-c", runFile.path]
        let pipe = Pipe()
        run.standardOutput = pipe
        run.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8)?
                .components(separatedBy: .newlines).last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return }
            Task { @MainActor [weak self] in self?.lastLine = String(line.prefix(200)) }
        }
        run.terminationHandler = { [weak self] ended in
            Task { @MainActor [weak self] in
                guard let self, self.process === ended else { return }
                self.process = nil
                try? FileManager.default.removeItem(at: self.runFile)
                self.use(PrivateVPNProxy.closed)
                self.state = .stopped(self.lastLine)
            }
        }
        do {
            try run.run()
        } catch {
            state = .stopped(error.localizedDescription)
            return
        }
        process = run
        try? String(run.processIdentifier).write(to: pidFile, atomically: true, encoding: .utf8)
        state = .starting
        Task { [weak self] in
            // The helper listening: then the stores are given its address.
            for _ in 0..<40 {
                guard let self, self.process === run, run.isRunning else { return }
                if await Self.answers(port: port) {
                    self.use(PrivateVPNProxy.local(port: port, user: user, password: password))
                    self.state = .running
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard let self, self.process === run else { return }
            self.stop()
            self.state = .stopped("The helper never started listening.")
        }
    }

    /// The helper ended, and what it was given gone. Private stores stay
    /// closed while the switch is on.
    func stop() {
        if let process {
            self.process = nil
            process.terminationHandler = nil
            if process.isRunning { process.terminate() }
        }
        try? FileManager.default.removeItem(at: runFile)
        try? FileManager.default.removeItem(at: pidFile)
        if on { use(PrivateVPNProxy.closed) }
    }

    // MARK: - the file

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "conf") ?? .data, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose the WireGuard file from your VPN provider (a .conf file)."
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        do {
            try keep(fileAt: chosen)
            said = nil
        } catch {
            said = error.localizedDescription
        }
    }

    /// The file copied into Relay's folder, readable by this user alone. It
    /// holds the tunnel's private key, and is in no backup.
    func keep(fileAt chosen: URL) throws {
        let size = (try? chosen.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0, size <= 64 * 1024, let text = try? String(contentsOf: chosen, encoding: .utf8) else {
            throw AIDownload.Failure("That file couldn't be read as a WireGuard file.")
        }
        if let problem = WireGuardFile.problem(text) { throw AIDownload.Failure(problem) }
        try Self.writePrivately(text, to: file)
        refresh()
        // The file chosen is the wish to use it: the helper comes with it.
        if !hasHelper { fetchHelper() }
        start()
    }

    func removeFile() {
        stop()
        try? FileManager.default.removeItem(at: file)
        refresh()
        if on { state = .needsFile }
    }

    // MARK: - the helper

    func fetchHelper() {
        guard fetching == nil, !hasHelper, !Store.testing else { return }
        fetching = 0
        said = nil
        Task {
            defer { fetching = nil }
            do {
                let pin = Self.pin
                let archive = try await AIDownload.fetch(pin.url, size: pin.size, sha256: pin.sha256) { [weak self] done in self?.fetching = done }
                defer { try? FileManager.default.removeItem(at: archive) }
                try Self.unpack(archive, to: helper, in: folder)
                refresh()
                start()
            } catch {
                // Not tried again on its own: Download in Settings does.
                failed = true
                said = "Couldn't get the helper: \(error.localizedDescription)"
            }
        }
    }

    func removeHelper() {
        stop()
        try? FileManager.default.removeItem(at: helper)
        refresh()
        if on { state = .needsHelper }
    }

    /// The one program out of the checked archive, made runnable.
    private static func unpack(_ archive: URL, to helper: URL, in folder: URL) throws {
        let files = FileManager.default
        let scratch = folder.appendingPathComponent("unpack-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: scratch, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: scratch) }
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xzf", archive.path, "-C", scratch.path, "wireproxy"]
        tar.standardOutput = FileHandle.nullDevice
        tar.standardError = FileHandle.nullDevice
        try tar.run()
        tar.waitUntilExit()
        let found = scratch.appendingPathComponent("wireproxy")
        let values = try? found.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard tar.terminationStatus == 0, values?.isRegularFile == true, values?.isSymbolicLink != true else {
            throw AIDownload.Failure("The download didn't hold the helper.")
        }
        try? files.removeItem(at: helper)
        try files.moveItem(at: found, to: helper)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
    }

    // MARK: - small things

    /// A file only this user can read, in a folder only this user can open.
    static func writePrivately(_ text: String, to file: URL) throws {
        let files = FileManager.default
        try files.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? files.removeItem(at: file)
        guard files.createFile(atPath: file.path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600]) else {
            throw AIDownload.Failure("Couldn't write in Relay's folder.")
        }
    }

    /// A port nothing on this Mac is listening on, asked of the system.
    static func freePort() -> UInt16? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { plain in
                bind(fd, plain, length) == 0 && getsockname(fd, plain, &length) == 0
            }
        }
        guard bound else { return nil }
        let port = UInt16(bigEndian: address.sin_port)
        return port > 0 ? port : nil
    }

    /// Whether something on this Mac takes a connection on a port.
    nonisolated static func answers(port: UInt16) async -> Bool {
        await Task.detached {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { return false }
            defer { close(fd) }
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            address.sin_port = port.bigEndian
            return withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { plain in
                    connect(fd, plain, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                }
            }
        }.value
    }

    /// A helper left running by a Relay that crashed: ended, if the process
    /// with that number is still this helper and not something else since.
    private static func endLeftOver(pidFile: URL, helper: URL) {
        defer { try? FileManager.default.removeItem(at: pidFile) }
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1 else { return }
        var path = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0,
              URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath().path == helper.resolvingSymlinksInPath().path
        else { return }
        kill(pid, SIGTERM)
    }
}

/// Fork: Settings › Custom › Private VPN.
struct PrivateVPNSettings: View {
    @ObservedObject private var vpn = PrivateVPN.shared

    private var helperDetail: String {
        let pin = PrivateVPN.pin
        if let done = vpn.fetching { return "Downloading… \(Int(done * 100))%" }
        if vpn.hasHelper { return "wireproxy \(pin.version) is downloaded. It runs only while the switch is on." }
        return "Relay needs wireproxy \(pin.version) to open the tunnel: an open-source program, \(ByteCountFormatter.string(fromByteCount: pin.size, countStyle: .file)), from its GitHub releases, checked before use. It downloads on its own when you choose a file or turn the switch on."
    }

    var body: some View {
        GroupBlock(title: "Private VPN", icon: "lock.shield") {
            Card {
                SettingRow(icon: "eye.slash", title: "Private tabs use a VPN",
                           detail: vpn.said ?? vpn.state.words) {
                    Switch(on: Binding(get: { vpn.on }, set: { vpn.set(on: $0) }))
                }
                Rule()
                SettingRow(icon: "doc.badge.gearshape", title: "WireGuard file",
                           detail: vpn.endpoint.map { "Connects to \($0). Kept in Relay's folder, readable only by you, and in no backup." }
                               ?? "The .conf file from your VPN provider. Only private tabs use it.") {
                    HStack(spacing: 6) {
                        if vpn.hasFile { Pill("Remove") { vpn.removeFile() } }
                        Pill(vpn.hasFile ? "Replace…" : "Choose…", filled: !vpn.hasFile) { vpn.chooseFile() }
                    }
                }
                Rule()
                SettingRow(icon: "shippingbox", title: "Helper", detail: helperDetail) {
                    if vpn.hasHelper {
                        Pill("Remove") { vpn.removeHelper() }
                    } else {
                        Pill(vpn.fetching == nil ? "Download" : "Downloading…", filled: true) { vpn.fetchHelper() }.opacity(vpn.fetching == nil ? 1 : 0.4)
                    }
                }
            }
        }
    }
}
