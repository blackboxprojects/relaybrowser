// Fork: the public half of the key Relay's releases are signed with
// (Ed25519, base64). `./release.sh key` makes the pair once, keeps the
// private half in the login keychain and writes this file. Empty, no feed is
// believed and nothing is ever installed (see ReleaseFeed).
enum ReleaseKey {
    static let publicKey = "3qti/LA/wisAJCS66nyuObkYKdJWhPO5DGJZxeE44t8="
}
