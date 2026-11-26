import CryptoKit
import Foundation

// Fork: where Relay's own releases are, and how one is known to be Relay's.
//
// Search's updater trusts a feed and a bundle because Office Commun's
// Developer ID signed them. Relay has no Developer ID: it is signed ad hoc,
// which says nothing about who built it. So the trust is a key of its own
// instead, the way Sparkle does it: release.sh signs the feed with an Ed25519
// key that never leaves the keychain of the Mac that makes the releases, and
// every build carries the public half (ReleaseKey). The feed names the ZIP's
// SHA-256, so a feed that checks out vouches for the one ZIP it names and no
// other.
//
// The files are assets of a GitHub release in `repository`:
//
//   appcast.json       {"signed": base64 of the feed, "signature": base64}
//   Relay-arm64.zip    the app, as the feed's "url" names it
//
// One file for the feed and its signature, so a release that is half
// uploaded is never read as a feed whose signature doesn't match.
enum ReleaseFeed {
    static let repository = "blackboxprojects/relaybrowser"

    /// The latest release's feed. GitHub answers "latest" with the newest
    /// release that is neither a draft nor a pre-release, so one can be put
    /// up and tried before any Relay is offered it. An Intel Mac reads a
    /// feed of its own, as it does with Search.
    static var feed: URL {
        #if arch(x86_64)
        let name = "appcast-intel.json"
        #else
        let name = "appcast.json"
        #endif
        return URL(string: "https://github.com/\(repository)/releases/latest/download/\(name)")!
    }

    /// An address the feed may name: https, on github.com, among this
    /// repository's releases. The ZIP is checked by hash whatever its
    /// address, but the release page is only ever opened, so it must not be
    /// able to be anywhere else.
    static func ours(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com"
            && url.path.hasPrefix("/\(repository)/releases/")
            && !url.path.contains("..")
    }

    /// The feed inside `envelope`, if `key` signed it. No key (a build made
    /// before `./release.sh key` was ever run) opens nothing, so such a
    /// build is never updated by anyone.
    static func opened(_ envelope: Data, key: String = ReleaseKey.publicKey) -> Data? {
        guard let raw = Data(base64Encoded: key), raw.count == 32,
              let signer = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
              let json = try? JSONSerialization.jsonObject(with: envelope) as? [String: Any],
              let signed = (json["signed"] as? String).flatMap({ Data(base64Encoded: $0) }),
              let signature = (json["signature"] as? String).flatMap({ Data(base64Encoded: $0) }),
              signer.isValidSignature(signature, for: signed)
        else { return nil }
        return signed
    }
}
