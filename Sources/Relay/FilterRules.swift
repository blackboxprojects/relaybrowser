import Foundation

/// Fork: a filter list as the lists are written (EasyList, EasyPrivacy:
/// Adblock Plus syntax) turned into the rules WebKit compiles for itself.
///
/// Only what WebKit's rule lists can say is taken, and a filter that asks for
/// more is left out whole: a script put into the page, a header rewritten, a
/// regular expression, a hiding rule that needs to read the page's text.
/// Leaving one out blocks a little less; taking half of one blocks the wrong
/// thing. An exception whose filter was left out is harmless, since there is
/// then nothing for it to except.
///
/// Three kinds come out, kept apart because their order matters to WebKit:
/// what is blocked, what is hidden, and last the exceptions, each of which
/// undoes whatever came before it for the requests it matches.
enum FilterRules {
    struct Converted {
        var block: [[String: Any]] = []
        var hide: [[String: Any]] = []
        var allow: [[String: Any]] = []
        /// Filters left out: more than WebKit can say.
        var skipped = 0

        var count: Int { block.count + hide.count + allow.count }
        /// In the order WebKit must read them.
        var rules: [[String: Any]] { block + hide + allow }
    }

    /// Raised whenever what a list is turned into changes, so the lists a
    /// Relay already has are made again by the next one (ShieldLists).
    static let version = 2

    /// WebKit takes this many rules in one list and no more.
    static let most = 150_000

    static func convert(_ text: String) -> Converted {
        var out = Converted()
        var seen = Set<String>()
        text.enumerateLines { raw, _ in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("!"), !line.hasPrefix("[") else { return }
            guard seen.insert(line).inserted else { return }
            switch rule(for: line) {
            case .block(let rule): out.block.append(rule)
            case .hide(let rule): out.hide.append(rule)
            case .allow(let rule): out.allow.append(rule)
            case nil: out.skipped += 1
            }
        }
        // Over what WebKit takes, hiding gives way first: a request blocked
        // matters more than an empty box hidden.
        let over = out.count - most
        if over > 0 {
            let dropped = min(over, out.hide.count)
            out.hide.removeLast(dropped)
            out.skipped += dropped
        }
        return out
    }

    enum Rule {
        case block([String: Any])
        case hide([String: Any])
        case allow([String: Any])
    }

    static func rule(for line: String) -> Rule? {
        // WebKit's patterns and domains are ASCII; a hiding rule's selector
        // may be anything CSS takes.
        if let marker = line.range(of: "#@#") ?? line.range(of: "#?#") ?? line.range(of: "#$#") ?? line.range(of: "#%#") {
            _ = marker
            return nil
        }
        if let marker = line.range(of: "##") {
            return hiding(sites: String(line[..<marker.lowerBound]), selector: String(line[marker.upperBound...]))
        }
        return network(line)
    }

    // MARK: Hiding

    /// What a hiding rule may not hold: each is uBlock's or Adblock Plus's
    /// own, not CSS, and WebKit refuses a selector it cannot read.
    private static let beyondCSS = [
        "+js(", ":has-text(", ":contains(", ":xpath(", ":-abp-", ":matches-css", ":upward(", ":remove(",
        ":style(", ":matches-path(", ":min-text-length(", ":watch-attr(", ":others(", ":nth-ancestor(",
        ":matches-attr(", ":matches-media(", ":if(", ":if-not(", ":not-has-text(", ":matches-prop(",
    ]

    static func hiding(sites: String, selector: String) -> Rule? {
        let selector = selector.trimmingCharacters(in: .whitespaces)
        guard !selector.isEmpty, !selector.hasPrefix("^"), !selector.hasPrefix("+") else { return nil }
        guard !beyondCSS.contains(where: selector.contains) else { return nil }
        var trigger: [String: Any] = ["url-filter": ".*"]
        if !sites.isEmpty {
            guard let named = domains(sites, separator: ",") else { return nil }
            trigger.merge(named) { _, new in new }
        }
        return .hide(["trigger": trigger, "action": ["type": "css-display-none", "selector": selector]])
    }

    /// `a.com,~b.a.com` as WebKit's if-domain or unless-domain. A rule has
    /// one or the other: with sites named, the ones excepted among them are
    /// let go, which hides or blocks a little more on those few. Nil for a
    /// site WebKit cannot name (a wildcard, a letter outside ASCII).
    static func domains(_ list: String, separator: Character) -> [String: Any]? {
        var named: [String] = []
        var excepted: [String] = []
        for part in list.split(separator: separator) {
            var site = part.trimmingCharacters(in: .whitespaces).lowercased()
            let not = site.hasPrefix("~")
            if not { site.removeFirst() }
            guard !site.isEmpty, site.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }) else { return nil }
            if not { excepted.append("*" + site) } else { named.append("*" + site) }
        }
        if !named.isEmpty { return ["if-domain": named] }
        if !excepted.isEmpty { return ["unless-domain": excepted] }
        return [:]
    }

    // MARK: Requests

    /// Every kind of request but a page itself, and a window opened: a filter
    /// that names no kind is not about pages you go to.
    static let kinds = ["script", "image", "style-sheet", "font", "media", "fetch", "websocket", "ping", "raw", "svg-document", "other"]

    private static let kindNames: [String: String] = [
        "script": "script", "image": "image", "stylesheet": "style-sheet", "css": "style-sheet",
        "font": "font", "media": "media", "xmlhttprequest": "fetch", "xhr": "fetch",
        "websocket": "websocket", "ping": "ping", "beacon": "ping", "other": "other",
        // A window or tab a page opens: most of what an advertising site
        // throws up on a click is one of these.
        "popup": "popup",
    ]

    static func network(_ line: String) -> Rule? {
        var filter = line
        let excepts = filter.hasPrefix("@@")
        if excepts { filter.removeFirst(2) }

        var options: [String] = []
        if let dollar = filter.lastIndex(of: "$") {
            let tail = filter[filter.index(after: dollar)...]
            // The last $ starts the options only when what follows reads as
            // options; a $ can also be part of the address matched.
            if !tail.isEmpty, tail.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "_,~=|.-*".contains($0)) }) {
                options = tail.split(separator: ",").map(String.init)
                filter = String(filter[..<dollar])
            }
        }
        // A regular expression of the list's own: WebKit's are not the same.
        if filter.count > 1, filter.hasPrefix("/"), filter.hasSuffix("/") { return nil }

        var trigger: [String: Any] = [:]
        var named: [String] = []
        var refused: [String] = []
        var frames = false
        var party: String?
        var wholePage = false
        for option in options {
            let not = option.hasPrefix("~")
            let name = (not ? String(option.dropFirst()) : option).lowercased()
            if name.hasPrefix("domain=") || name.hasPrefix("from=") {
                guard !not, let value = name.split(separator: "=", maxSplits: 1).last,
                      let sites = domains(String(value), separator: "|"), !sites.isEmpty else { return nil }
                trigger.merge(sites) { _, new in new }
                continue
            }
            switch name {
            case "third-party", "3p": party = not ? "first-party" : "third-party"
            case "first-party", "1p": party = not ? "third-party" : "first-party"
            case "match-case": trigger["url-filter-is-case-sensitive"] = true
            case "important", "all": break
            case "subdocument", "frame":
                if not { refused.append("document") } else { frames = true }
            case "document", "doc":
                // An exception for the whole page; a filter that blocks a
                // page you go to is uBlock's strict blocking, not taken.
                guard excepts, !not else { return nil }
                wholePage = true
            default:
                guard let kind = kindNames[name] else { return nil }
                if not { refused.append(kind) } else { named.append(kind) }
            }
        }

        guard let pattern = pattern(for: filter) else { return nil }
        trigger["url-filter"] = pattern.expression
        if let party { trigger["load-type"] = [party] }

        if wholePage {
            // Everything loaded on that site: only said of a site by name.
            guard pattern.host != nil, named.isEmpty, !frames, trigger["if-domain"] == nil, trigger["unless-domain"] == nil,
                  let host = pattern.host else { return nil }
            return .allow(["trigger": ["url-filter": ".*", "if-domain": ["*" + host]], "action": ["type": "ignore-previous-rules"]])
        }

        if frames, named.isEmpty {
            // Frames only: a page of that address gone to is not one.
            trigger["resource-type"] = ["document"]
            trigger["load-context"] = ["child-frame"]
        } else if !named.isEmpty {
            // Frames among other kinds: the page gone to cannot be told
            // from a frame there, so only another site's are taken.
            trigger["resource-type"] = Array(Set(named)).sorted() + (frames && party == "third-party" ? ["document"] : [])
        } else if !excepts {
            if pattern.host != nil, party == nil, refused.isEmpty {
                // A whole site, no kind named: everything of it loaded from
                // elsewhere, its frames included, and never the site gone to.
                trigger["load-type"] = ["third-party"]
            } else {
                trigger["resource-type"] = kinds.filter { !refused.contains($0) }
            }
        } else if !refused.isEmpty {
            trigger["resource-type"] = kinds.filter { !refused.contains($0) }
        }

        let action = excepts ? "ignore-previous-rules" : "block"
        let rule: [String: Any] = ["trigger": trigger, "action": ["type": action]]
        return excepts ? .allow(rule) : .block(rule)
    }

    struct Pattern: Equatable {
        var expression: String
        /// The site, when the filter is a whole site and nothing more
        /// (`||ads.example.com^`).
        var host: String?
    }

    /// Any scheme, and any name ending in the site's.
    static let anyHost = "^[a-z-]+://([^/]+\\.)?"
    /// What `^` stands for in a filter: whatever ends a name or a word of an
    /// address. An address WebKit sees always has something after its host,
    /// so one is asked for.
    static let separator = "[^a-zA-Z0-9_.%-]"

    /// A filter's address as WebKit's own kind of expression: literal but
    /// for `*`, `^` and the anchors. Nil for one too broad to mean anything
    /// or with letters outside ASCII.
    static func pattern(for filter: String) -> Pattern? {
        var body = filter
        guard body.allSatisfy({ $0.isASCII && !$0.isWhitespace }) else { return nil }
        var start = ""
        var hosted = false
        if body.hasPrefix("||") {
            body.removeFirst(2)
            start = anyHost
            hosted = true
        } else if body.hasPrefix("|") {
            body.removeFirst()
            start = "^"
        }
        var end = ""
        if body.hasSuffix("|") {
            body.removeLast()
            end = "$"
        }
        while body.hasPrefix("*") { body.removeFirst() }
        while body.hasSuffix("*") { body.removeLast() }
        guard body.filter({ $0 != "*" && $0 != "^" }).count >= 3 else { return nil }

        if hosted {
            var name = body
            if name.hasSuffix("^") { name.removeLast() }
            if !name.isEmpty, name.contains("."), name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) {
                let host = name.lowercased()
                return Pattern(expression: anyHost + escaped(host) + "[:/]", host: host)
            }
        }
        var expression = start
        for character in body {
            switch character {
            case "*": expression += ".*"
            case "^": expression += separator
            default: expression += escaped(String(character))
            }
        }
        return Pattern(expression: expression + end, host: nil)
    }

    private static func escaped(_ text: String) -> String {
        var out = ""
        for character in text {
            if "\\.+?()[]{}|$^*".contains(character) { out += "\\" }
            out.append(character)
        }
        return out
    }
}
