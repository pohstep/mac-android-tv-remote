import XCTest
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import TvRemoteCore

final class SsdpTests: XCTestCase {
    func testSearchNamesTheSonyTargetAndTheWiderSearch() {
        let sony = SsdpMessage.search(target: SsdpMessage.sonyTarget, mx: 2)
        XCTAssertTrue(sony.contains("M-SEARCH * HTTP/1.1\r\n"))
        XCTAssertTrue(sony.contains("HOST: 239.255.255.250:1900\r\n"))
        XCTAssertTrue(sony.contains("MAN: \"ssdp:discover\"\r\n"))
        XCTAssertTrue(sony.contains("ST: urn:schemas-sony-com:service:ScalarWebAPI:1\r\n"))
        XCTAssertEqual(SsdpMessage.targets, [SsdpMessage.sonyTarget, SsdpMessage.allTarget])
    }

    func testSonyScalarReplyFillsTheIP() {
        let packet = """
        HTTP/1.1 200 OK\r
        CACHE-CONTROL: max-age=1800\r
        LOCATION: http://192.0.2.8:52323/dmr.xml\r
        SERVER: Linux/3.10 UPnP/1.0 Sony-BRAVIA/1.0\r
        ST: urn:schemas-sony-com:service:ScalarWebAPI:1\r
        USN: uuid:sony-1::urn:schemas-sony-com:service:ScalarWebAPI:1\r
        \r

        """
        let tv = SsdpParse.television(packet: packet, sourceHost: "192.0.2.99")
        XCTAssertEqual(tv?.brand, .sony)
        XCTAssertEqual(tv?.host, "192.0.2.8")
        XCTAssertEqual(tv?.controlPort, 80)
        XCTAssertEqual(tv?.port, 5555)
        XCTAssertEqual(tv?.source, "ssdp-scalar")
        XCTAssertEqual(tv?.name, "Sony TV")
        XCTAssertEqual(SsdpParse.host(from: "http://192.0.2.8:52323/dmr.xml"), "192.0.2.8")
    }

    func testLowercaseLocationAndSenderHostStillCount() {
        let packet = """
        HTTP/1.1 200 OK\r
        location: http://192.0.2.8/description.xml\r
        st: urn:schemas-sony-com:service:ScalarWebAPI:1\r
        server: Sony-BRAVIA\r

        """
        let tv = SsdpParse.television(packet: packet, sourceHost: "")
        XCTAssertEqual(tv?.host, "192.0.2.8")
        let missingLocation = """
        HTTP/1.1 200 OK\r
        ST: urn:schemas-sony-com:service:ScalarWebAPI:1\r
        SERVER: BRAVIA\r

        """
        XCTAssertEqual(SsdpParse.television(packet: missingLocation, sourceHost: "192.0.2.7")?.host, "192.0.2.7")
    }

    func testXiaomiBannerIsAPort6095Candidate() {
        let packet = """
        HTTP/1.1 200 OK\r
        LOCATION: http://192.0.2.40:8008/ssdp/device-desc.xml\r
        SERVER: Linux/3.0 UPnP/1.0 MiTV/1.0\r
        ST: urn:dial-multiscreen-org:service:dial:1\r
        USN: uuid:mitv-1::urn:dial-multiscreen-org:service:dial:1\r

        """
        let tv = SsdpParse.television(packet: packet, sourceHost: "192.0.2.40")
        XCTAssertEqual(tv?.brand, .xiaomi)
        XCTAssertEqual(tv?.host, "192.0.2.40")
        XCTAssertEqual(tv?.port, 6095)
        XCTAssertEqual(tv?.controlPort, 6095)
        XCTAssertEqual(tv?.source, "ssdp-xiaomi")
        XCTAssertEqual(tv?.listTitle, "Xiaomi TV")
    }

    func testAndroidDialIsGenericAndARouterIsIgnored() {
        let android = """
        HTTP/1.1 200 OK\r
        LOCATION: http://192.0.2.50:8008/ssdp/device-desc.xml\r
        SERVER: Linux/4.9 UPnP/1.0 Android TV/1.0\r
        ST: urn:dial-multiscreen-org:service:dial:1\r
        USN: uuid:atv-1::urn:dial-multiscreen-org:service:dial:1\r

        """
        let tv = SsdpParse.television(packet: android, sourceHost: "192.0.2.50")
        XCTAssertEqual(tv?.brand, .generic)
        XCTAssertEqual(tv?.host, "192.0.2.50")
        XCTAssertEqual(tv?.name, "Android TV")
        XCTAssertEqual(tv?.source, "ssdp-dial")
        XCTAssertEqual(tv?.port, 5555)

        let router = """
        HTTP/1.1 200 OK\r
        LOCATION: http://192.0.2.1:5000/rootDesc.xml\r
        SERVER: Linux/4.4 UPnP/1.0 Router/1.0\r
        ST: upnp:rootdevice\r
        USN: uuid:router::upnp:rootdevice\r

        """
        XCTAssertNil(SsdpParse.television(packet: router, sourceHost: "192.0.2.1"))
        XCTAssertNil(SsdpParse.television(packet: "NOTIFY * HTTP/1.1\r\n", sourceHost: "192.0.2.1"))
        XCTAssertNil(SsdpParse.host(from: ""))
        XCTAssertNil(SsdpParse.host(from: "http://0.0.0.0/desc.xml"))
    }

    func testBraviaOutranksAGenericDialBannerOnTheSameReply() {
        XCTAssertEqual(
            SsdpClassify.role(server: "Sony-BRAVIA Android TV", searchTarget: "urn:dial-multiscreen-org:service:dial:1", usn: ""),
            .sony
        )
        XCTAssertEqual(
            SsdpClassify.role(server: "Redmi", searchTarget: "ssdp:all", usn: ""),
            .xiaomi
        )
        XCTAssertEqual(
            SsdpClassify.role(server: "Router", searchTarget: "upnp:rootdevice", usn: ""),
            .ignore
        )
    }

    func testSelectRetriesOnEINTRAndStopsOnTimeoutOrOtherErrors() {
        XCTAssertTrue(SocketSelect.fits(0))
        XCTAssertTrue(SocketSelect.fits(Int32(FD_SETSIZE) - 1))
        XCTAssertFalse(SocketSelect.fits(-1))
        XCTAssertFalse(SocketSelect.fits(Int32(FD_SETSIZE)))
        XCTAssertEqual(SocketSelect.interpret(ready: -1, errnoValue: EINTR), .retry)
        XCTAssertEqual(SocketSelect.interpret(ready: 0, errnoValue: EINTR), .stop)
        XCTAssertEqual(SocketSelect.interpret(ready: -1, errnoValue: EBADF), .stop)
        XCTAssertEqual(SocketSelect.interpret(ready: 1, errnoValue: 0), .ready)
    }
}
