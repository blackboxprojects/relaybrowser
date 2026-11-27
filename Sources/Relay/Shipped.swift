import Foundation

/// Fork: the extension Relay came with. uBlock Origin Lite was fetched from
/// the Chrome Web Store the first time Relay ran, through the same checked
/// install as any other store extension.
///
/// No longer, while the blocker has its lists (ShieldLists, on unless
/// switched off): the same lists enforced by WebKit itself, with no
/// extension's worker, pages or scripts to carry. With the lists switched
/// off it is fetched as before, once. Installed already, it is yours either
/// way and is left alone.
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
    static func step(done: Bool, installed: [String], testing: Bool, lists: Bool = false) -> Step {
        guard !done, !testing, !lists else { return .nothing }
        return installed.contains(ublockLite) ? .note : .install
    }
}

@available(macOS 15.4, *)
extension Extensions {
    /// After the extensions already there have started (start(for:)).
    func installShipped() async {
        let store = Store.settings
        switch Shipped.step(done: store.bool(forKey: Shipped.doneKey), installed: installed.map(\.id), testing: Store.testing, lists: ShieldLists.on) {
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
