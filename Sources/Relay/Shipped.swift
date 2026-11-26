import Foundation

/// Fork: the extension Relay comes with. uBlock Origin Lite is fetched from
/// the Chrome Web Store the first time Relay runs, through the same checked
/// install as any other store extension, so it is the current version and
/// none of its files are in Relay's own download.
///
/// Once only. Installed, it is yours: switch it off or remove it in
/// Settings › Extensions and it is not brought back. A Mac with no network
/// at first launch is tried again at the next one.
enum Shipped {
    /// uBlock Origin Lite's id in the Chrome Web Store.
    static let ublockLite = "ddkjiahejlhfcafbddmgiahcphecmpfh"
    static let doneKey = "fork.shipped.ublock"

    enum Step: Equatable {
        /// Nothing to do, now or later.
        case nothing
        /// There already, by the user's own hand: only noted as done.
        case note
        /// To be fetched and installed.
        case install
    }

    /// What a launch does about it. Never in a test run, which fetches
    /// nothing it wasn't told to.
    static func step(done: Bool, installed: [String], testing: Bool) -> Step {
        guard !done, !testing else { return .nothing }
        return installed.contains(ublockLite) ? .note : .install
    }
}

@available(macOS 15.4, *)
extension Extensions {
    /// After the extensions already there have started (start(for:)).
    func installShipped() async {
        let store = Store.settings
        switch Shipped.step(done: store.bool(forKey: Shipped.doneKey), installed: installed.map(\.id), testing: Store.testing) {
        case .nothing:
            return
        case .note:
            store.set(true, forKey: Shipped.doneKey)
        case .install:
            await installUnasked(id: Shipped.ublockLite)
            // Not there, the fetch failed: left for the next launch.
            if installed.contains(where: { $0.id == Shipped.ublockLite }) { store.set(true, forKey: Shipped.doneKey) }
        }
    }
}
