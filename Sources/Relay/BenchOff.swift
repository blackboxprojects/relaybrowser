#if !RELAY_BENCH
import AppKit

/// Fork: what the rest of Relay says to the bench, in a build without it.
///
/// The bench (Bench.swift, 7,000 lines, and the frame timers and stand-ins
/// beside it) is how the tests drive a running Relay: a socket, some four
/// hundred commands, hooks that count what is drawn. A release carried all
/// of it and used none. Debug and test builds still have it, and a release
/// built with RELAY_BENCH=1 does too, for the probes that copy the
/// installed app (probe.sh).
///
/// Here every hook is nothing, the switch cannot be turned on, and the two
/// small helpers the agent feature borrows are kept whole.
@MainActor
final class Bench {
    static let shared = Bench()
    /// False in a build without the bench: Settings leaves its row out.
    nonisolated static let built = false
    static let edgeHeld = Notification.Name("search.bench.edgeHeld")
    static var bodies: [String: Int] = [:]
    static var foldCovers = 0

    static func count(_ name: String) {}
    static func barLaid(_ id: Bookmark.ID, _ frame: CGRect) {}
    static func barHides(_ browser: Browser, _ hidden: [Bookmark]) {}
    static func rowAppeared(_ id: Tab.ID, hover: @escaping (Bool) -> Void) {}
    static func rowDisappeared(_ id: Tab.ID) {}
    static func keepOff(_ window: NSWindow) {}

    /// The key code of a letter on a US keyboard, which is what WebKit reads
    /// alongside the characters; anything else goes as the space bar's.
    static func keyCode(for character: Character) -> UInt16 {
        let codes: [Character: UInt16] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32,
            "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        ]
        return codes[Character(character.lowercased())] ?? 49
    }

    static func short(_ tab: Tab) -> String {
        String(tab.id.uuidString.prefix(8)).lowercased()
    }

    /// Never given: with no bench to open, the setting is put back to off.
    @MainActor
    enum Consent {
        static var given: Bool { false }
        static func grant() {}
        static func revoke() {}
    }

    func start(for browser: Browser) {}
    func stop() {}
}
#endif
