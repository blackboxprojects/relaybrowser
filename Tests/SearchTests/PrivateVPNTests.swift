import XCTest
@testable import Relay

/// Fork: a VPN for private tabs only (PrivateVPN.swift). The WireGuard file
/// is checked and rewritten for the helper; nothing in it but the tunnel
/// gets through.
final class PrivateVPNTests: XCTestCase {
    private let proton = """
    [Interface]
    # Key for relay-private
    # NetShield = 1
    PrivateKey = aGVsbG8gd29ybGQgdGhpcyBpcyBub3QgYSBrZXkgYXQgYWxsIQ==
    Address = 10.2.0.2/32
    DNS = 10.2.0.1

    [Peer]
    # CH#1
    PublicKey = cGVlciBrZXkgdGhhdCBpcyBhbHNvIG5vdCBhIHJlYWwga2V5IQ==
    AllowedIPs = 0.0.0.0/0, ::/0
    Endpoint = 185.159.157.1:51820
    """

    func testAProvidersFileIsFineAndNamesItsServer() {
        XCTAssertNil(WireGuardFile.problem(proton))
        XCTAssertEqual(WireGuardFile.endpoint(proton), "185.159.157.1:51820")
    }

    func testWhatIsNoWireGuardFileIsRefusedWithWhy() {
        XCTAssertNotNil(WireGuardFile.problem(""))
        XCTAssertNotNil(WireGuardFile.problem("{\"containers\": []}"))
        XCTAssertNotNil(WireGuardFile.problem("[Interface]\nAddress = 10.2.0.2/32\n[Peer]\nPublicKey = a\nEndpoint = b:1"))
        XCTAssertNotNil(WireGuardFile.problem("[Interface]\nPrivateKey = a\nAddress = 10.2.0.2/32"))
        XCTAssertNotNil(WireGuardFile.problem("[Interface]\nPrivateKey = a\nAddress = 1\n[Peer]\nPublicKey = a"))
    }

    func testTheHelpersFileIsTheTunnelAndOneProxyOnThisMacAlone() {
        let made = WireGuardFile.helperConfig(proton, port: 50123, user: "relay", password: "secret")
        XCTAssertTrue(made.contains("PrivateKey = aGVsbG8gd29ybGQgdGhpcyBpcyBub3QgYSBrZXkgYXQgYWxsIQ=="))
        XCTAssertTrue(made.contains("Endpoint = 185.159.157.1:51820"))
        XCTAssertTrue(made.contains("AllowedIPs = 0.0.0.0/0, ::/0"))
        XCTAssertTrue(made.contains("DNS = 10.2.0.1"))
        XCTAssertTrue(made.contains("[Socks5]\nBindAddress = 127.0.0.1:50123\nUsername = relay\nPassword = secret"))
        XCTAssertFalse(made.contains("#"), "comments stay behind")
        XCTAssertEqual(made.components(separatedBy: "[Socks5]").count, 2)
    }

    func testNothingButTheTunnelGetsThroughToTheHelper() {
        let loaded = """
        WGConfig = /etc/passwd
        [Interface]
        PrivateKey = a
        Address = 10.2.0.2/32
        PostUp = rm -rf ~
        PreDown = curl example.com
        Table = off
        [Peer]
        PublicKey = b
        Endpoint = vpn.example:51820
        [Socks5]
        BindAddress = 0.0.0.0:1080
        [http]
        BindAddress = 0.0.0.0:8080
        [TCPServerTunnel]
        ListenPort = 22
        Target = localhost:22
        [STDIOTunnel]
        Target = localhost:22
        """
        XCTAssertNil(WireGuardFile.problem(loaded))
        let made = WireGuardFile.helperConfig(loaded, port: 50123, user: "relay", password: "secret")
        for gone in ["WGConfig", "PostUp", "PreDown", "Table", "0.0.0.0", "[http]", "TCPServerTunnel", "STDIOTunnel", "rm -rf", "passwd"] {
            XCTAssertFalse(made.contains(gone), gone)
        }
        XCTAssertEqual(made.components(separatedBy: "BindAddress").count, 2, "one listener, Relay's own")
        XCTAssertTrue(made.contains("BindAddress = 127.0.0.1:50123"))
    }

    func testKeysAreReadWhateverTheirCase() {
        let odd = "[interface]\nprivatekey=a\nADDRESS = 10.0.0.2/32\n[PEER]\npublickey = b\nendpoint = host:1"
        XCTAssertNil(WireGuardFile.problem(odd))
        XCTAssertEqual(WireGuardFile.endpoint(odd), "host:1")
    }

    func testWithTheSwitchOnAndNoTunnelAPrivateTabIsClosedNotDirect() {
        XCTAssertFalse(PrivateVPNProxy.closed.allowFailover)
        XCTAssertFalse(PrivateVPNProxy.local(port: 50123, user: "relay", password: "x").allowFailover)
    }

    @MainActor func testAPortAskedOfTheSystemIsFreeAndNothingAnswersOnIt() async throws {
        let port = try XCTUnwrap(PrivateVPN.freePort())
        XCTAssertGreaterThan(port, 1023)
        let taken = await PrivateVPN.answers(port: port)
        XCTAssertFalse(taken)
    }

    @MainActor func testAPrivatelyWrittenFileIsReadableByItsOwnerAlone() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vpn-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("wireguard.conf")
        try PrivateVPN.writePrivately("secret", to: file)
        let mode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(mode.intValue & 0o777, 0o600)
        let above = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(above.intValue & 0o777, 0o700)
    }

    @MainActor func testThePinnedHelperIsOneReleaseOverHTTPSFromItsAuthor() {
        let pin = PrivateVPN.pin
        XCTAssertEqual(pin.url.scheme, "https")
        XCTAssertEqual(pin.url.host, "github.com")
        XCTAssertTrue(pin.url.path.hasPrefix("/pufferffish/wireproxy/releases/download/v\(pin.version)/"))
        XCTAssertEqual(pin.sha256.count, 64)
    }
}
