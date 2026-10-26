import XCTest
@testable import TvRemoteCore

final class DiscoveryTests: XCTestCase {
    func testSubnetSkipsSelfNetworkAndBroadcast() {
        let hosts = SubnetHosts.hosts(in: "192.0.2.20")
        XCTAssertEqual(hosts.count, 253)
        XCTAssertFalse(hosts.contains("192.0.2.20"))
        XCTAssertFalse(hosts.contains("192.0.2.0"))
        XCTAssertFalse(hosts.contains("192.0.2.255"))
        XCTAssertTrue(hosts.contains("192.0.2.1"))
        XCTAssertEqual(SubnetHosts.hosts(in: "not-an-ip"), [])
    }

    func testBonjourMergesPairingAndConnectOnTheSameHost() {
        let tvs = DiscoveryParse.bonjour([
            ServiceEndpoint(name: "Living Room", host: "192.0.2.8", port: 37123, serviceType: "_adb-tls-pairing._tcp."),
            ServiceEndpoint(name: "Living Room", host: "192.0.2.8", port: 41234, serviceType: "_adb-tls-connect._tcp"),
            ServiceEndpoint(name: "", host: "", port: 1, serviceType: "_adb-tls-connect._tcp")
        ])
        XCTAssertEqual(tvs.count, 1)
        XCTAssertEqual(tvs[0].brand, .generic)
        XCTAssertEqual(tvs[0].host, "192.0.2.8")
        XCTAssertEqual(tvs[0].port, 41234)
        XCTAssertEqual(tvs[0].pairingPort, 37123)
        XCTAssertEqual(tvs[0].name, "Living Room")
        XCTAssertEqual(tvs[0].source, DiscoveryService.connectType)
    }

    func testSonyBodyAcceptsPowerAndForbiddenJSON() {
        let power = #"{"result":[{"status":"active"}],"id":1}"#
        let found = DiscoveryParse.sony(host: "192.0.2.8", status: 200, body: power)
        XCTAssertEqual(found?.brand, .sony)
        XCTAssertEqual(found?.port, 5555)
        XCTAssertEqual(found?.controlPort, 80)
        XCTAssertEqual(found?.name, "192.0.2.8")

        let info = #"{"result":[{"name":"Living Room","macAddr":"AA:BB:CC:DD:EE:FF"}],"id":1}"#
        let named = DiscoveryParse.sony(host: "192.0.2.8", status: 200, body: info)
        XCTAssertEqual(named?.name, "Living Room")
        XCTAssertEqual(named?.macAddress, "AA:BB:CC:DD:EE:FF")

        let forbidden = #"{"error":[403,"Forbidden"],"id":1}"#
        XCTAssertEqual(DiscoveryParse.sony(host: "192.0.2.9", status: 403, body: forbidden)?.brand, .sony)
        XCTAssertNil(DiscoveryParse.sony(host: "192.0.2.9", status: 200, body: "<html></html>"))
        XCTAssertNil(DiscoveryParse.sony(host: "192.0.2.9", status: 500, body: power))
        XCTAssertNil(DiscoveryParse.sony(host: "192.0.2.9", status: 200, body: ""))
    }

    func testXiaomiAliveBody() {
        let body = #"{"status":0,"data":{"devicename":"Den"}}"#
        let found = DiscoveryParse.xiaomi(host: "192.0.2.40", status: 200, body: body)
        XCTAssertEqual(found?.brand, .xiaomi)
        XCTAssertEqual(found?.name, "Den")
        XCTAssertEqual(found?.port, 6095)
        XCTAssertEqual(found?.controlPort, 6095)
        XCTAssertNil(DiscoveryParse.xiaomi(host: "192.0.2.40", status: 200, body: #"{"status":1}"#))
        XCTAssertNil(DiscoveryParse.xiaomi(host: "192.0.2.40", status: 404, body: body))
    }

    func testEngineKeepsManualEntryAndInjectedFakes() {
        let services = [
            ServiceEndpoint(name: "Pair", host: "192.0.2.8", port: 37000, serviceType: DiscoveryService.pairingType)
        ]
        let scan = DiscoveredTV(
            name: "Set",
            brand: .sony,
            host: "192.0.2.9",
            port: 5555,
            controlPort: 80,
            macAddress: "AA:BB:CC:DD:EE:FF",
            source: "sony-scan"
        )
        var seenHosts: [String] = []
        let probe = RecordingProbe(found: [scan]) { seenHosts = $0 }
        let outcome = DiscoveryEngine(
            serviceEndpoints: services,
            localAddresses: ["192.0.2.20"],
            prober: probe
        ).find()
        XCTAssertTrue(outcome.manualEntryAvailable)
        XCTAssertEqual(outcome.found.map(\.host).sorted(), ["192.0.2.8", "192.0.2.9"])
        XCTAssertEqual(seenHosts.count, 253)
        XCTAssertFalse(seenHosts.contains("192.0.2.20"))

        let empty = DiscoveryCoordinator(
            listing: StaticServiceListing(endpoints: []),
            prober: StaticSubnetProbe(found: []),
            localAddresses: []
        ).find()
        XCTAssertTrue(empty.found.isEmpty)
        XCTAssertTrue(empty.manualEntryAvailable)
    }
}

private struct RecordingProbe: SubnetProbing {
    var found: [DiscoveredTV]
    var record: ([String]) -> Void
    func probe(hosts: [String]) -> [DiscoveredTV] {
        record(hosts)
        return found
    }
}
