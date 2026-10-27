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
        XCTAssertEqual(byHost["192.0.2.9"]?.listTitle, "Sony TV")
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

    func testSonyAndXiaomiDedupedInOnePassAndNamed() {
        let sony = DiscoveredTV(name: "Sony TV", brand: .sony, host: "192.0.2.8", port: 80, controlPort: 80, source: "ssdp-scalar")
        let sameHost = DiscoveredTV(name: "Living Room", brand: .xiaomi, host: "192.0.2.8", port: 6095, controlPort: 6095, source: "ssdp-xiaomi")
        let other = DiscoveredTV(name: "Den", brand: .xiaomi, host: "192.0.2.40", port: 6095, controlPort: 6095, source: "ssdp-xiaomi", model: "MiTV")
        let rows = DiscoveryParse.deduped([sony, sameHost, other])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].host, "192.0.2.8")
        XCTAssertEqual(rows[0].brand, .sony)
        XCTAssertEqual(rows[0].name, "Living Room")
        XCTAssertEqual(rows[0].controlPort, 80)
        XCTAssertEqual(rows[1].host, "192.0.2.40")
        XCTAssertEqual(rows[1].brand, .xiaomi)
        XCTAssertEqual(rows[1].name, "Den")
        let placeholder = DiscoveredTV(name: "Xiaomi TV", brand: .xiaomi, host: "192.0.2.41", port: 6095, controlPort: 6095, source: "ssdp-xiaomi")
        let named = DiscoveryNaming.apply(
            [placeholder],
            namer: StaticTvNaming(identity: TvIdentity(name: "Bedroom", model: "Mi Box", macAddress: "AA:BB:CC:DD:EE:01"))
        )
        XCTAssertEqual(named[0].name, "Bedroom")
        XCTAssertEqual(named[0].model, "Mi Box")
        XCTAssertEqual(named[0].macAddress, "AA:BB:CC:DD:EE:01")
    }

    func testDescribedNameReplacesAPlaceholder() {
        let row = DiscoveredTV(name: "Sony TV", brand: .sony, host: "192.0.2.8", port: 5555, controlPort: 80, source: "ssdp-scalar")
        let naming = StaticTvNaming(identity: TvIdentity(name: "Living Room", model: "KD-55X80L", macAddress: "AA:BB:CC:DD:EE:FF"))
        let named = DiscoveryNaming.apply([row], namer: naming)
        XCTAssertEqual(named[0].name, "Living Room")
        XCTAssertEqual(named[0].model, "KD-55X80L")
        XCTAssertEqual(named[0].macAddress, "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(named[0].listTitle, "Sony TV")
    }

    func testSameMACBecomesOneCardWithTheIPv4AndTheDebuggingPort() {
        let sony = DiscoveredTV(
            name: "Sony TV",
            brand: .sony,
            host: "192.168.50.57",
            port: 5555,
            controlPort: 80,
            macAddress: "88:c9:e8:5f:28:76",
            source: "sony-scan"
        )
        let adb = DiscoveredTV(
            name: "adb-9415bf001511520",
            brand: .generic,
            host: "fe80::dbfa:3006:82fb:fbdc%en0",
            port: 41234,
            controlPort: 41234,
            pairingPort: 37123,
            macAddress: "88:C9:E8:5F:28:76",
            source: DiscoveryService.connectType
        )
        let cards = DiscoveryCards.present([adb, sony])
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].host, "192.168.50.57")
        XCTAssertEqual(cards[0].controlPort, 80)
        XCTAssertEqual(cards[0].port, 41234)
        XCTAssertEqual(cards[0].pairingPort, 37123)
        XCTAssertEqual(cards[0].macAddress, "88:c9:e8:5f:28:76")
        XCTAssertEqual(cards[0].listTitle, "Sony TV")
        assertCardIsPlain(cards[0].listTitle)
    }

    func testSameIPv4BecomesOneCard() {
        let sony = DiscoveredTV(name: "Sony TV", brand: .sony, host: "192.0.2.8", port: 5555, controlPort: 80, source: "sony-scan")
        let adb = DiscoveredTV(
            name: "adb-abc",
            brand: .generic,
            host: "192.0.2.8",
            port: 41234,
            controlPort: 41234,
            source: DiscoveryService.legacyAdbType,
            legacyAdbPort: 5555
        )
        let cards = DiscoveryCards.present([sony, adb])
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].host, "192.0.2.8")
        XCTAssertEqual(cards[0].controlPort, 80)
        XCTAssertEqual(cards[0].legacyAdbPort, 5555)
        XCTAssertEqual(cards[0].listTitle, "Sony TV")
        assertCardIsPlain(cards[0].listTitle)
    }

    func testResolvedIPv4OnAnAdbAdvertisementMatchesTheScan() {
        let adb = DiscoveryParse.bonjour([
            ServiceEndpoint(
                name: "adb-9415bf001511520",
                host: "fe80::dbfa:3006:82fb:fbdc%en0",
                port: 41234,
                serviceType: DiscoveryService.connectType,
                addresses: ["192.168.50.57", "fe80::dbfa:3006:82fb:fbdc%en0"]
            )
        ])
        let sony = DiscoveredTV(name: "Sony TV", brand: .sony, host: "192.168.50.57", port: 5555, controlPort: 80, source: "sony-scan")
        let cards = DiscoveryCards.present(adb + [sony])
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].host, "192.168.50.57")
        XCTAssertEqual(cards[0].port, 41234)
        XCTAssertEqual(cards[0].listTitle, "Sony TV")
    }

    func testLinkLocalAdbBesideANamedSonyIsOneCard() {
        let sony = DiscoveredTV(name: "Sony TV", brand: .sony, host: "192.168.50.57", port: 5555, controlPort: 80, source: "sony-scan")
        let adb = DiscoveredTV(
            name: "adb-9415bf001511520",
            brand: .generic,
            host: "fe80::dbfa:3006:82fb:fbdc%en0",
            port: 41234,
            controlPort: 41234,
            source: DiscoveryService.connectType
        )
        let cards = DiscoveryCards.present([sony, adb])
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].host, "192.168.50.57")
        XCTAssertEqual(cards[0].listTitle, "Sony TV")
        XCTAssertEqual(cards[0].brand, .sony)
        assertCardIsPlain(cards[0].listTitle)
    }

    func testNeighbourCacheMergesLinkLocalAdbOntoTheSonyIPv4() {
        let sony = DiscoveredTV(name: "Sony TV", brand: .sony, host: "192.168.50.57", port: 5555, controlPort: 80, source: "sony-scan")
        let adb = DiscoveredTV(
            name: "adb-9415bf001511520",
            brand: .generic,
            host: "fe80::dbfa:3006:82fb:fbdc%en0",
            port: 41234,
            controlPort: 41234,
            source: DiscoveryService.connectType
        )
        let cards = DiscoveryCards.present([sony, adb], neighbours: FixtureNeighbours())
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].host, "192.168.50.57")
        XCTAssertEqual(cards[0].macAddress, "88:c9:e8:5f:28:76")
        XCTAssertEqual(cards[0].port, 41234)
        XCTAssertEqual(cards[0].controlPort, 80)
        assertCardIsPlain(cards[0].listTitle)
    }

    func testTwoTelevisionsStayTwoCardsWithPlainNames() {
        let living = DiscoveredTV(
            name: "Living Room",
            brand: .sony,
            host: "192.0.2.8",
            port: 5555,
            controlPort: 80,
            macAddress: "aa:bb:cc:dd:ee:01",
            source: "sony-scan"
        )
        let den = DiscoveredTV(
            name: "Den",
            brand: .xiaomi,
            host: "192.0.2.40",
            port: 6095,
            controlPort: 6095,
            macAddress: "aa:bb:cc:dd:ee:02",
            source: "xiaomi-scan"
        )
        let cards = DiscoveryCards.present([den, living])
        XCTAssertEqual(cards.map(\.listTitle), ["Sony TV", "Xiaomi TV"])
        XCTAssertEqual(cards.map(\.host), ["192.0.2.8", "192.0.2.40"])
        cards.forEach { assertCardIsPlain($0.listTitle) }

        let second = DiscoveredTV(
            name: "Sony TV",
            brand: .sony,
            host: "192.0.2.41",
            port: 5555,
            controlPort: 80,
            macAddress: "aa:bb:cc:dd:ee:03",
            source: "sony-scan"
        )
        let numbered = DiscoveryCards.present([living, second])
        XCTAssertEqual(numbered.map(\.listTitle), ["Sony TV", "Sony TV 2"])
        numbered.forEach { assertCardIsPlain($0.listTitle) }
    }

    func testPhoneIsHiddenAndBareDebuggingIsLast() {
        let phone = DiscoveredTV(
            name: "Pixel phone",
            brand: .generic,
            host: "192.0.2.20",
            port: 5555,
            controlPort: 5555,
            source: DiscoveryService.legacyAdbType
        )
        let sony = DiscoveredTV(name: "Sony TV", brand: .sony, host: "192.0.2.50", port: 5555, controlPort: 80, source: "sony-scan")
        let cast = DiscoveredTV(
            name: "Shield",
            brand: .generic,
            host: "192.0.2.9",
            port: 6466,
            controlPort: 6466,
            source: DiscoveryService.androidTvRemoteType
        )
        let adb = DiscoveredTV(
            name: "adb-deadbeef",
            brand: .generic,
            host: "192.0.2.3",
            port: 5555,
            controlPort: 5555,
            source: DiscoveryService.connectType
        )
        let cards = DiscoveryCards.present([adb, phone, cast, sony])
        XCTAssertEqual(cards.map(\.listTitle), ["Sony TV", "Android TV"])
        XCTAssertEqual(cards.map(\.host), ["192.0.2.50", "192.0.2.9"])
        cards.forEach { assertCardIsPlain($0.listTitle) }

        let only = DiscoveryCards.present([adb])
        XCTAssertEqual(only.map(\.listTitle), ["Android device"])
        XCTAssertFalse(only[0].listTitle.contains("deadbeef"))
        assertCardIsPlain(only[0].listTitle)
    }

    func testNeighbourTextMapsTheLinkLocalAddressToTheIPv4() {
        let ndp = """
        Neighbor                        Linklayer Address  Netif
        fe80::dbfa:3006:82fb:fbdc%en0   88:c9:e8:5f:28:76  en0
        """
        let arp = "? (192.168.50.57) at 88:c9:e8:5f:28:76 on en0 ifscope [ethernet]\n"
        XCTAssertEqual(NeighbourParse.mac(forIPv6: "fe80::dbfa:3006:82fb:fbdc%en0", ndp: ndp), "88:c9:e8:5f:28:76")
        XCTAssertEqual(NeighbourParse.ipv4s(forMAC: "88:C9:E8:5F:28:76", arp: arp), ["192.168.50.57"])
    }
}

private func assertCardIsPlain(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertNil(title.range(of: #"\d+\.\d+\.\d+\.\d+"#, options: .regularExpression), title, file: file, line: line)
    XCTAssertFalse(title.lowercased().contains("adb-"), title, file: file, line: line)
    XCTAssertFalse(title.contains(":"), title, file: file, line: line)
    XCTAssertFalse(title.contains("%"), title, file: file, line: line)
}

private struct FixtureNeighbours: NeighbourLooking {
    func mac(forIPv6 host: String) -> String? {
        host.lowercased().hasPrefix("fe80:") ? "88:c9:e8:5f:28:76" : nil
    }

    func ipv4s(forMAC mac: String) -> [String] {
        mac.lowercased() == "88:c9:e8:5f:28:76" ? ["192.168.50.57"] : []
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
