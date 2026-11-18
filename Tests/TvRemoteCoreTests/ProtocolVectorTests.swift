import XCTest
@testable import TvRemoteCore

final class ProtocolVectorTests: XCTestCase {
    func testSha256Abc() {
        let digest = Sha256.hash(Data("abc".utf8))
        XCTAssertEqual(hex(digest), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testPairingHashMatchesAndroidTvRemote2Formatting() {
        let client = hexData("CCCCA98584B001421246D95064ECD1D2D2F99BB2D0823589A688810ECBB90B8A522555BC26251E71267DDB1197E7EFFF30C1250BD0EC68547AE54C0D7EC20D02F38FD6D03C0AAE05AEAEDA4043BF0D82833B57C33647EB66749587EA228FACEE79BDFDADB2E0D76AEB5430A1F62C349166551382F569920C94E392A4369DE969E3FF0976ACC6DDCA767FA0B53BFFFF771AECDA37B8EF53B29C013435BF786E50FD8435CF5037DD8D986C2E87D379DAC50A4CA23FA8E50438A0A92D8DB2358379AADD75F8F69B09E08BB1D55A14D3C19130B4900B2006C142046862B3B143FFF43747061A2D4C7C61EC50FBF5F5F71B770FE6E1971CDE29CAB948C58705474327")
        var serverBytes = [UInt8](client)
        serverBytes[serverBytes.count - 1] ^= 0xff
        let server = Data(serverBytes)
        let exponent = AtvPairingHash.exponentBytes(65537)
        let digest = AtvPairingHash.digest(
            clientModulus: client,
            clientExponent: exponent,
            serverModulus: server,
            serverExponent: exponent,
            nonceHex: "ABCD"
        )
        XCTAssertEqual(hex(digest), "969cb0fce87160faa9626eb95d1d7c9c53802bf993e71a693f5c03bed290defd")
        XCTAssertTrue(AtvPairingHash.accepts(code: "96ABCD", clientModulus: client, clientExponent: exponent, serverModulus: server, serverExponent: exponent))
        XCTAssertFalse(AtvPairingHash.accepts(code: "97ABCD", clientModulus: client, clientExponent: exponent, serverModulus: server, serverExponent: exponent))
        XCTAssertFalse(AtvPairingHash.accepts(code: "96ABCZ", clientModulus: client, clientExponent: exponent, serverModulus: server, serverExponent: exponent))
    }

    func testPairingRequestFrame() {
        XCTAssertEqual(hex(AtvPairingMessage.framedRequest()), "1a080210c80152130a0961747672656d6f746512065a6170626172")
        XCTAssertEqual(hex(AtvRemoteMessage.framedKey(.dpadCenter)), "06520408171003")
    }

    func testAdbAuthSignatureVector() {
        let token = Data("abcdefghij123456789".utf8) + Data([0])
        let signature = AdbAuth.signature(token: token, modulus: hexData("CCCCA98584B001421246D95064ECD1D2D2F99BB2D0823589A688810ECBB90B8A522555BC26251E71267DDB1197E7EFFF30C1250BD0EC68547AE54C0D7EC20D02F38FD6D03C0AAE05AEAEDA4043BF0D82833B57C33647EB66749587EA228FACEE79BDFDADB2E0D76AEB5430A1F62C349166551382F569920C94E392A4369DE969E3FF0976ACC6DDCA767FA0B53BFFFF771AECDA37B8EF53B29C013435BF786E50FD8435CF5037DD8D986C2E87D379DAC50A4CA23FA8E50438A0A92D8DB2358379AADD75F8F69B09E08BB1D55A14D3C19130B4900B2006C142046862B3B143FFF43747061A2D4C7C61EC50FBF5F5F71B770FE6E1971CDE29CAB948C58705474327"), privateExponent: hexData("46E5467DE90C00B37D9E37166489B2AD17C9BEC36CF8D64DBB6F9FB59E82856331C2A8E644122F729E0F8D698EBB84D2436F6942A8E55DCC78EAADA432503CAEDBDFDC4E23AAD2C936CA62D5425E7DEFC33C24CA781CF779753C5A5B8BF14EBD1339D8FA6B64F84D93FF86025B34BC51E529E8623A507C758C8927375F8CD4C2EB32BB94CFFB898931457141D554DA2ED00A163813C4D119AC98C4C0039D1993DEBD54E28E8073CEFA81E9B5E8AD5FC087ABAAB068AECA99FEB2373FAF794F92AEFEF4A6A8B0E96A3AEFE4D0D89EEBEDB5859FADBA8A958EDA614CC966F05238A46627187B6849D2B86AEB94284256C186BBE97746D1758185C69DFACA542501"))
        XCTAssertEqual(hex(signature), "42a254ea3092c33187477a5a0ed6beb8fd64e4cd26387cc94722cad6ac3d14c2f3e640ece470a9b7ed6460ca12172e2f56a7c99d72962ea323cba4e4f903e87abc1a38d5eac51fbf05fb50c049fa2acad29f9101d9756feaea02a3d4f827f5ca30655104d8dfa2a9847c72cccd310058820acf7f7d210a1264d102cf6cedfee2531e214b887d305f0ec6ec7205cc7bf72393ef247f5435b4303e8a6a665efa8d95023b1b755d6d2bd5559c7945609f6d9b702d2525c16593a230efc681317716f0ae9abde3893f8850f5ce568bf39899259ac46ca553718423e4dc61c5748b0f4d08966e2e385ba6a54755963ef9b67cb64b19c3942df44c4a80e795209601f0")
        let packet = AdbWire.signature(signature).encode(checksum: true)
        let decoded = AdbPacket.decode(packet)
        XCTAssertEqual(decoded?.packet.command, AdbCommand.auth)
        XCTAssertEqual(decoded?.packet.arg0, AdbCommand.signature)
        XCTAssertEqual(decoded?.packet.payload, signature)
    }

    func testAdbPublicKeyVector() {
        let key = AdbAuth.androidPublicKey(modulus: hexData("CCCCA98584B001421246D95064ECD1D2D2F99BB2D0823589A688810ECBB90B8A522555BC26251E71267DDB1197E7EFFF30C1250BD0EC68547AE54C0D7EC20D02F38FD6D03C0AAE05AEAEDA4043BF0D82833B57C33647EB66749587EA228FACEE79BDFDADB2E0D76AEB5430A1F62C349166551382F569920C94E392A4369DE969E3FF0976ACC6DDCA767FA0B53BFFFF771AECDA37B8EF53B29C013435BF786E50FD8435CF5037DD8D986C2E87D379DAC50A4CA23FA8E50438A0A92D8DB2358379AADD75F8F69B09E08BB1D55A14D3C19130B4900B2006C142046862B3B143FFF43747061A2D4C7C61EC50FBF5F5F71B770FE6E1971CDE29CAB948C58705474327"), exponent: 65537, comment: "zapbar@mac")
        XCTAssertEqual(hex(key), "5141414141476b447041306e513063466838564975636f7033687958346559506478763339665837554f78686645777447675a484e2f542f5137477a596d674551734547494175517444435277644d5557745778692b414a6d2f62346464327165594d31736f307471614134424f576f50364a4d4373586165644f484c6d79596a643033554d383168503151626e692f4e5451426e4c4a543737673332757761642f2f2f4f3757676633624b3363617364676e2f34326e706e54616b6b754f55444a4a7039594954565761524e437a326f54425536327258344c4b742f62313537717950497571486c58526d36306332773163376734494e76304e41327136754261344b504e44576a2f4d4344634a2b44557a6c656c526f374e414c4a6345772f2b2f6e6c78486266535a784869556d7646556c556f6f4c7563734f6759696d69545743304c4b622b644c533065786b554e6c47456b49427349534671637a4d6a4868524f37783659336d7344554c53774b32544669577335504274413666584c4b49746b6f4b6d4a4856322b462f4735437a5a3047492b4a684a776b4859746a446578424677636c3976594f6556563176424b753774596265366c4464417764696e384b56737638686f4e4262506265637a736b572b456b6a697367644c547a693174623145554f4133462b4b623974783644436d524b55733347647035334345412f626777797647766c35614c6a484c4a382f7a737976566b4a3239596377356c41475352427872525a645772354b7171433652393452744b4a525a6e36675a4c367477636b672b72716a6b774f3779552f5947584e516d7056415a3947513756773133352b317442314b537959334735382b784a69726d305047696b6c7931774c4c303052526545646c654146535a7266534d6a73636f367261422f61394e484679524133364d6364756d48396f4b4a394c5145414151413d207a6170626172406d616300")
    }

    func testSyncPushAndGuardedCommands() throws {
        let body = AdbSync.push(path: "/data/local/tmp/app.apk", bytes: Data([1, 2, 3, 4]))
        XCTAssertTrue(body.starts(with: uint32(AdbSync.send)))
        let named = "/data/local/tmp/app.apk,33188"
        XCTAssertTrue(String(data: body, encoding: .isoLatin1)?.contains(named) == true)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Sources/TvRemoteCore/Resources/never-touch.json"))
        let list = NeverTouchGuard.load(data)
        XCTAssertNil(AdbAppCommand.uninstall("com.android.settings", guardList: list))
        XCTAssertNil(AdbAppCommand.forceStop("com.android.settings", guardList: list))
        XCTAssertEqual(AdbAppCommand.uninstall("com.example.game", guardList: list), "pm uninstall --user 0 com.example.game")
        XCTAssertNil(AdbAppCommand.install(remotePath: "/tmp/not-an-apk.txt"))
        XCTAssertEqual(AdbAppCommand.screencap(), "exec:screencap -p")
        XCTAssertFalse(ApkPick.isApk("/tmp/movie.mp4"))
        XCTAssertTrue(ApkPick.isApk("/tmp/App.APK"))
    }

    func testProProductFileHasNoTrial() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("macos/PohstepRemote/Products.storekit"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let products = json?["products"] as? [[String: Any]]
        XCTAssertEqual(products?.count, 1)
        XCTAssertEqual(products?.first?["productID"] as? String, ProProduct.id)
        XCTAssertEqual(products?.first?["displayPrice"] as? String, ProProduct.displayPrice)
        XCTAssertEqual(products?.first?["familyShareable"] as? Bool, true)
        XCTAssertEqual(products?.first?["type"] as? String, "NonConsumable")
        XCTAssertEqual((json?["subscriptionGroups"] as? [Any])?.count, 0)
        XCTAssertFalse(ProProduct.trial)
        XCTAssertFalse(ProProduct.consumable)
        XCTAssertFalse(ProGate.allows(.screenshot, access: .locked))
        XCTAssertTrue(ProGate.allows(.screenshot, access: ProAccess(purchased: true, preview: false)))
        XCTAssertTrue(ProGate.allows(.apkInstall, access: ProAccess(purchased: false, preview: true)))
    }

    func testCodePairWizardIsThreeSteps() {
        var wizard = SetupWizard()
        XCTAssertEqual(wizard.phase, .find)
        XCTAssertEqual(wizard.progressTotal, 3)
        let tv = DiscoveredTV(name: "Living Room", brand: .generic, host: "192.0.2.9", port: 6466, controlPort: 6466, source: DiscoveryService.androidTvRemoteType)
        XCTAssertTrue(tv.offersCodePair)
        XCTAssertEqual(wizard.handle(.pick(tv)), .none)
        XCTAssertEqual(wizard.phase, .screenCode)
        XCTAssertEqual(wizard.handle(.submitScreenCode("zzzzzz")), .none)
        guard case .pairScreenCode(let host, let code) = wizard.handle(.submitScreenCode("96abcd")) else {
            return XCTFail("expected code")
        }
        XCTAssertEqual(host, "192.0.2.9")
        XCTAssertEqual(code, "96ABCD")
        guard case .save(let saved) = wizard.handle(.screenCodeAccepted) else {
            return XCTFail("expected save")
        }
        XCTAssertEqual(wizard.phase, .done)
        XCTAssertEqual(wizard.message, "Connected.")
        XCTAssertFalse(saved.useDebugging)
        XCTAssertEqual(saved.port, 6466)
    }

    func testPanelRemoteMapsTheFocusedPanel() {
        XCTAssertEqual(KeyMapping.panelRemote(for: KeyChord(key: .arrowUp), textFieldFocused: false), .send(.key(.dpadUp)))
        XCTAssertEqual(KeyMapping.panelRemote(for: KeyChord(key: .space), textFieldFocused: false), .send(.key(.mediaPlayPause)))
        XCTAssertEqual(KeyMapping.panelRemote(for: KeyChord(key: .esc), textFieldFocused: false), .send(.key(.back)))
        XCTAssertEqual(
            KeyMapping.panelRemote(for: KeyChord(key: .arrowUp, modifiers: [.command]), textFieldFocused: false),
            .send(.key(.volumeUp))
        )
        XCTAssertEqual(KeyMapping.panelRemote(for: KeyChord(key: .arrowUp), textFieldFocused: true), .passthrough)
        let open = GlobalHotkeys.factory.action(for: 17, modifiers: [.control, .option])
        XCTAssertEqual(open, .openPanel)
    }
}

private func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

private func hexData(_ text: String) -> Data {
    var out = Data()
    var index = text.startIndex
    while index < text.endIndex {
        let next = text.index(index, offsetBy: 2)
        out.append(UInt8(text[index..<next], radix: 16)!)
        index = next
    }
    return out
}

private func uint32(_ value: UInt32) -> Data {
    var little = value.littleEndian
    return Data(bytes: &little, count: 4)
}
