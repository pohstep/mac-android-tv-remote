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

    func testSonyModelFillsTheNameWhenTheSetOnlySaysTV() {
        let body = #"{"result":[{"product":"TV","model":"KD-55X80L","macAddr":"AA:BB:CC:DD:EE:FF"}],"id":1}"#
        let found = DiscoveryParse.sony(host: "192.0.2.8", status: 200, body: body)
        XCTAssertEqual(found?.name, "KD-55X80L")
        XCTAssertEqual(found?.model, "KD-55X80L")
        XCTAssertEqual(found?.macAddress, "AA:BB:CC:DD:EE:FF")
        let identity = DiscoveryParse.sonyIdentity(host: "192.0.2.8", status: 200, body: body)
        XCTAssertEqual(identity?.model, "KD-55X80L")
        XCTAssertNil(DiscoveryParse.sonyIdentity(host: "192.0.2.8", status: 403, body: #"{"error":[403,"Forbidden"]}"#))
    }

    func testLegacyAdbAndCastAreListedAndSpeakersAreNot() {
        let tvs = DiscoveryParse.bonjour([
            ServiceEndpoint(name: "Living Room", host: "192.0.2.8", port: 5555, serviceType: "_adb._tcp."),
            ServiceEndpoint(name: "Bravia", host: "192.0.2.9", port: 8009, serviceType: "_googlecast._tcp", model: "BRAVIA 4K"),
            ServiceEndpoint(name: "Kitchen speaker", host: "192.0.2.11", port: 8009, serviceType: "_googlecast._tcp", model: "Google Home"),
            ServiceEndpoint(name: "Shield", host: "192.0.2.12", port: 6466, serviceType: "_androidtvremote2._tcp", model: "SHIELD Android TV")
        ])
        let byHost = Dictionary(uniqueKeysWithValues: tvs.map { ($0.host, $0) })
        XCTAssertEqual(byHost["192.0.2.8"]?.legacyAdbPort, 5555)
        XCTAssertEqual(byHost["192.0.2.8"]?.brand, .generic)
        XCTAssertEqual(byHost["192.0.2.9"]?.brand, .sony)
        XCTAssertEqual(byHost["192.0.2.9"]?.controlPort, 80)
        XCTAssertEqual(byHost["192.0.2.9"]?.model, "BRAVIA 4K")
        XCTAssertEqual(byHost["192.0.2.9"]?.listTitle, "Bravia · BRAVIA 4K · 192.0.2.9")
        XCTAssertNil(byHost["192.0.2.11"])
        XCTAssertEqual(byHost["192.0.2.12"]?.brand, .generic)
        XCTAssertEqual(byHost["192.0.2.12"]?.name, "Shield")
        XCTAssertFalse(CastFilter.include(name: "Nest Hub", model: "Nest Hub"))
        XCTAssertTrue(CastFilter.include(name: "Living Room", model: "Chromecast Google TV"))
    }

    func testSsdpSonyKeepsDebuggingHintsFromTheSameHost() {
        let ssdp = DiscoveredTV(name: "Sony TV", brand: .sony, host: "192.0.2.8", port: 5555, controlPort: 80, source: "ssdp-scalar")
        let pairing = ServiceEndpoint(name: "Living Room", host: "192.0.2.8", port: 37111, serviceType: DiscoveryService.pairingType)
        let outcome = DiscoveryEngine(
            serviceEndpoints: [pairing],
            localAddresses: [],
            prober: StaticSubnetProbe(found: []),
            ssdpFound: [ssdp],
            portProbe: StaticPortProbe(open: ["192.0.2.8:5555"])
        ).find()
        XCTAssertEqual(outcome.found.count, 1)
        XCTAssertEqual(outcome.found[0].brand, .sony)
        XCTAssertEqual(outcome.found[0].controlPort, 80)
        XCTAssertEqual(outcome.found[0].name, "Living Room")
        XCTAssertEqual(outcome.found[0].pairingPort, 37111)
        XCTAssertEqual(outcome.found[0].legacyAdbPort, 5555)
        XCTAssertTrue(outcome.manualEntryAvailable)
    }

    func testDescribedNameReplacesAPlaceholder() {
        let row = DiscoveredTV(name: "Sony TV", brand: .sony, host: "192.0.2.8", port: 5555, controlPort: 80, source: "ssdp-scalar")
        let naming = StaticTvNaming(identity: TvIdentity(name: "Living Room", model: "KD-55X80L", macAddress: "AA:BB:CC:DD:EE:FF"))
        let named = DiscoveryNaming.apply([row], namer: naming)
        XCTAssertEqual(named[0].name, "Living Room")
        XCTAssertEqual(named[0].model, "KD-55X80L")
        XCTAssertEqual(named[0].macAddress, "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(named[0].listTitle, "Living Room · KD-55X80L · 192.0.2.8")
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

private struct StaticTvNaming: TvNaming {
    var identity: TvIdentity
    func describe(host: String, brand: TvBrand) -> TvIdentity? { identity }
}
