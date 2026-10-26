import XCTest
@testable import TvRemoteCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// `bind` and `close` are macros on Darwin and plain functions on Glibc.
/// Calling them by these names keeps one test body for both.
private func systemBind(_ fd: Int32, _ address: UnsafePointer<sockaddr>, _ length: socklen_t) -> Int32 {
    bind(fd, address, length)
}

private func systemClose(_ fd: Int32) -> Int32 {
    close(fd)
}

#if os(Linux)
private let datagramSocketType = Int32(SOCK_DGRAM.rawValue)
#else
private let datagramSocketType = SOCK_DGRAM
#endif

final class WakeAndSettingsTests: XCTestCase {
    func testMagicPacketLayout() throws {
        let mac = try XCTUnwrap(MACAddress.bytes("aa:bb:cc:dd:ee:ff"))
        XCTAssertEqual(MACAddress.bytes("AA-BB-CC-DD-EE-FF"), mac)
        XCTAssertEqual(MACAddress.bytes("aabbccddeeff"), mac)
        XCTAssertNil(MACAddress.bytes("aa:bb"))
        let packet = MagicPacket.bytes(for: mac)
        XCTAssertEqual(packet.count, 102)
        XCTAssertEqual(Array(packet.prefix(6)), [UInt8](repeating: 0xFF, count: 6))
        XCTAssertEqual(Array(packet[6..<12]), mac)
        XCTAssertEqual(Array(packet[(6 + 15 * 6)..<(6 + 16 * 6)]), mac)
        XCTAssertEqual(MACAddress.display("aabb.ccdd.eeff"), "AA:BB:CC:DD:EE:FF")
    }

    func testSenderRejectsABadMacAndBroadcast() {
        let sender = WakeOnLanSender()
        XCTAssertThrowsError(try sender.send(mac: "nope", broadcastHost: "255.255.255.255", port: 9)) { error in
            guard case RemoteError.invalidMac = error else {
                return XCTFail("unexpected \(error)")
            }
        }
        XCTAssertThrowsError(try sender.send(mac: "aa:bb:cc:dd:ee:ff", broadcastHost: "not-an-ip", port: 9)) { error in
            guard case RemoteError.invalidBroadcast = error else {
                return XCTFail("unexpected \(error)")
            }
        }
    }

    func testMagicPacketArrivesOnLoopback() throws {
        let port = try UDPCatcher.bind(host: "127.0.0.1")
        let sender = WakeOnLanSender()
        try sender.send(mac: "10:20:30:40:50:60", broadcastHost: "127.0.0.1", port: port.port)
        let received = try port.receive()
        let expected = MagicPacket.bytes(for: try XCTUnwrap(MACAddress.bytes("10:20:30:40:50:60")))
        XCTAssertEqual(received, expected)
        port.shutdownSocket()
    }

    func testSettingsRoundTripAndCorruptFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("settings.json")
        let store = SettingsStore(url: url)
        XCTAssertEqual(store.load().settings, .factoryDefaults())
        XCTAssertNil(store.load().warning)

        var settings = Settings.factoryDefaults()
        settings.host = "bravia.tailnet.ts.net"
        settings.port = 5555
        settings.wolEnabled = true
        settings.macAddress = "AA:BB:CC:DD:EE:FF"
        settings.apps.append(TvApp(id: "extra", name: "Kodi", packageName: "org.xbmc.kodi"))
        try store.save(settings)
        let loaded = store.load()
        XCTAssertEqual(loaded.settings.host, "bravia.tailnet.ts.net")
        XCTAssertEqual(loaded.settings.apps.last?.packageName, "org.xbmc.kodi")
        XCTAssertNil(loaded.warning)

        try "not json".data(using: .utf8)?.write(to: url)
        let broken = store.load()
        XCTAssertEqual(broken.settings, .factoryDefaults())
        XCTAssertNotNil(broken.warning)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("bad").path))
    }

    func testShellRunnerEchoAndTimeout() throws {
        let runner = ShellRunner()
        let echoed = try runner.run("/bin/echo", arguments: ["pohstep"], timeout: 5)
        XCTAssertEqual(echoed.status, 0)
        XCTAssertEqual(echoed.stdout, "pohstep\n")
        XCTAssertThrowsError(try runner.run("/bin/sleep", arguments: ["5"], timeout: 0.3)) { error in
            guard case RemoteError.timedOut = error else {
                return XCTFail("unexpected \(error)")
            }
        }
        XCTAssertThrowsError(try runner.run("/no/such/adb", arguments: [], timeout: 1))
    }
}

final class UDPCatcher {
    let fd: Int32
    let port: UInt16

    private init(fd: Int32, port: UInt16) {
        self.fd = fd
        self.port = port
    }

    static func bind(host: String) throws -> UDPCatcher {
        let fd = socket(AF_INET, datagramSocketType, 0)
        if fd < 0 { throw TestSocketError() }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        #if os(macOS)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        _ = host.withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                systemBind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bound != 0 {
            _ = systemClose(fd)
            throw TestSocketError()
        }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var resolved = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &resolved) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(fd, socketAddress, &length)
            }
        }
        if named != 0 {
            _ = systemClose(fd)
            throw TestSocketError()
        }
        return UDPCatcher(fd: fd, port: UInt16(bigEndian: resolved.sin_port))
    }

    func receive() throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: 200)
        let count = recv(fd, &buffer, buffer.count, 0)
        if count < 0 { throw TestSocketError() }
        return Array(buffer.prefix(count))
    }

    func shutdownSocket() {
        _ = systemClose(fd)
    }
}

private struct TestSocketError: Error {}
