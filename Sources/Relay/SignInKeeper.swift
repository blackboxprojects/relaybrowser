import AppKit
import WebKit

// Fork: sign-ins written down before they can be lost. WebKit keeps a
// store's cookies in memory and writes them to its file when it gets round
// to it. The store every app has is written often enough; a store made by
// identifier (a space's own, a profile's, a container's) mostly was not
// before Relay quit, and three containers out of four had no cookie file
// at all: signed in, quit, signed out. So every store is asked to write its
// cookies: every half minute, whenever Relay stops being the app in front,
// and once more on the way out, which the quit waits for (Links.swift).
@MainActor
enum SignInKeeper {
    private static var timer: Timer?
    private static var watching: NSObjectProtocol?
    /// How long a quit waits for the stores to answer.
    static let patience: TimeInterval = 2

    static func start() {
        guard timer == nil, !Store.testing else { return }
        let made = Timer(timeInterval: 30, repeats: true) { _ in MainActor.assumeIsolated { flush() } }
        made.tolerance = 5
        RunLoop.main.add(made, forMode: .common)
        timer = made
        watching = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { flush() }
        }
    }

    /// Every store that keeps anything, asked to write its cookies now.
    /// `done` once each has answered, or straight away if none can be asked.
    static func flush(_ stores: [WKWebsiteDataStore]? = nil, then done: @escaping () -> Void = {}) {
        let selector = NSSelectorFromString("_flushCookiesToDiskWithCompletionHandler:")
        typealias Flush = @convention(c) (AnyObject, Selector, @escaping @convention(block) () -> Void) -> Void
        let group = DispatchGroup()
        var seen: [ObjectIdentifier] = []
        for store in stores ?? Spaces.everyStore where store.isPersistent && !seen.contains(ObjectIdentifier(store)) {
            seen.append(ObjectIdentifier(store))
            let jar = store.httpCookieStore
            guard jar.responds(to: selector) else { continue }
            group.enter()
            let once = Once { group.leave() }
            unsafeBitCast(jar.method(for: selector), to: Flush.self)(jar, selector) { once.run() }
        }
        group.notify(queue: .main, execute: done)
    }

    /// The quit's own flush: `reply` when the stores have answered, or after
    /// `patience` if one never does. Never twice.
    static func flushBeforeQuit(_ reply: @escaping () -> Void) {
        let once = Once(reply)
        flush { once.run() }
        DispatchQueue.main.asyncAfter(deadline: .now() + patience) { once.run() }
    }

    /// A block run the first time it is asked for, from any thread.
    final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var block: (() -> Void)?
        init(_ block: @escaping () -> Void) { self.block = block }
        func run() {
            lock.lock()
            let taken = block
            block = nil
            lock.unlock()
            taken?()
        }
    }
}
