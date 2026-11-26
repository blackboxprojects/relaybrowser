// Fork: the key Relay's releases are signed with, and the feed it signs.
// Run by release.sh (swift Installer/release-key.swift …), never built into
// the app. ReleaseFeed.swift says what the app does with the result.
//
//   new <ReleaseKey.swift>     makes the pair: the private half into the
//                              login keychain, the public half into the file
//   public                     prints the public half
//   feed <out> key=value …     writes the signed feed; expect=<public key>
//                              refuses a key the app being packed doesn't carry
//   check <feed> <public key>  prints what a feed says, if that key signed it
//
// The private half is 32 bytes, base64, kept as a generic password. It is
// read from RELAY_RELEASE_KEY instead when that is set, for a build made
// somewhere without the keychain (GitHub Actions, with the key as a secret).

import CryptoKit
import Foundation
import Security

let service = "com.chiduong.relay.release-key"
let account = "blackboxprojects/relaybrowser"

func fail(_ line: String) -> Never {
    FileHandle.standardError.write(Data((line + "\n").utf8))
    exit(1)
}

func stored() -> Curve25519.Signing.PrivateKey? {
    if let given = ProcessInfo.processInfo.environment["RELAY_RELEASE_KEY"], !given.isEmpty {
        guard let raw = Data(base64Encoded: given), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
        else { fail("RELAY_RELEASE_KEY is not a key") }
        return key
    }
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
    ]
    var found: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess,
          let data = found as? Data, let raw = Data(base64Encoded: data)
    else { return nil }
    return try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
}

func key() -> Curve25519.Signing.PrivateKey {
    guard let key = stored() else { fail("no release key in the keychain — ./release.sh key makes one") }
    return key
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "new":
    guard arguments.count == 2 else { fail("new <ReleaseKey.swift>") }
    // Never a second one over the first: every Relay already out believes
    // only the first, and would never be updated again.
    guard stored() == nil else { fail("there is a release key already — keeping it") }
    let made = Curve25519.Signing.PrivateKey()
    let item: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecAttrLabel as String: "Relay release key",
        kSecValueData as String: Data(made.rawRepresentation.base64EncodedString().utf8),
    ]
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else { fail("the keychain didn't take the key (\(status))") }
    let shown = made.publicKey.rawRepresentation.base64EncodedString()
    let file = """
    // Fork: the public half of the key Relay's releases are signed with
    // (Ed25519, base64). `./release.sh key` makes the pair once, keeps the
    // private half in the login keychain and writes this file. Empty, no feed is
    // believed and nothing is ever installed (see ReleaseFeed).
    enum ReleaseKey {
        static let publicKey = "\(shown)"
    }

    """
    do { try file.write(toFile: arguments[1], atomically: true, encoding: .utf8) } catch { fail("couldn't write \(arguments[1])") }
    print(shown)

case "public":
    print(key().publicKey.rawRepresentation.base64EncodedString())

case "feed":
    guard arguments.count > 2 else { fail("feed <out> key=value …") }
    var fields: [String: Any] = [:]
    var expected: String?
    for pair in arguments.dropFirst(2) {
        guard let cut = pair.firstIndex(of: "=") else { fail("not key=value: \(pair)") }
        let name = String(pair[..<cut]), value = String(pair[pair.index(after: cut)...])
        switch name {
        case "expect": expected = value
        case "build":
            guard let number = Int(value) else { fail("build is a number") }
            fields[name] = number
        default: if !value.isEmpty { fields[name] = value }
        }
    }
    for needed in ["version", "build", "url", "dmg", "sha256"] where fields[needed] == nil { fail("the feed needs \(needed)") }
    let signer = key()
    let shown = signer.publicKey.rawRepresentation.base64EncodedString()
    if let expected, expected != shown {
        fail("the key in the keychain is not the one this build carries (ReleaseKey.swift) — no Relay would believe this feed")
    }
    guard let signed = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
          let signature = try? signer.signature(for: signed),
          let envelope = try? JSONSerialization.data(withJSONObject: [
              "signed": signed.base64EncodedString(), "signature": signature.base64EncodedString(),
          ], options: [.sortedKeys, .prettyPrinted])
    else { fail("couldn't sign the feed") }
    do { try envelope.write(to: URL(fileURLWithPath: arguments[1])) } catch { fail("couldn't write \(arguments[1])") }

case "check":
    guard arguments.count == 3 else { fail("check <feed> <public key>") }
    guard let envelope = FileManager.default.contents(atPath: arguments[1]),
          let raw = Data(base64Encoded: arguments[2]),
          let signer = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
          let json = try? JSONSerialization.jsonObject(with: envelope) as? [String: Any],
          let signed = (json["signed"] as? String).flatMap({ Data(base64Encoded: $0) }),
          let signature = (json["signature"] as? String).flatMap({ Data(base64Encoded: $0) }),
          signer.isValidSignature(signature, for: signed)
    else { fail("that key did not sign this feed") }
    print(String(decoding: signed, as: UTF8.self))

default:
    fail("new <ReleaseKey.swift> | public | feed <out> key=value … | check <feed> <public key>")
}
