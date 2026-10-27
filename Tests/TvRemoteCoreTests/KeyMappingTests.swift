import XCTest
@testable import TvRemoteCore

final class KeyMappingTests: XCTestCase {
    func testHotkeyTogglesEvenWhenKeyboardModeIsOff() {
        let chord = KeyChord(key: .ansi("k"), modifiers: [.control, .option])
        XCTAssertEqual(KeyMapping.effect(for: chord, keyboardMode: false), .toggleKeyboardMode)
        XCTAssertEqual(KeyMapping.effect(for: chord, keyboardMode: true), .toggleKeyboardMode)
    }

    func testKeyboardModeOffLetsTheMacKeepEverythingElse() {
        let arrows = KeyChord(key: .arrowUp)
        XCTAssertEqual(KeyMapping.effect(for: arrows, keyboardMode: false), .ignore)
        let letter = KeyChord(key: .ansi("a"), characters: "a")
        XCTAssertEqual(KeyMapping.effect(for: letter, keyboardMode: false), .ignore)
    }

    func testArrowsReturnEscAndDelete() {
        XCTAssertEqual(KeyMapping.effect(for: KeyChord(key: .arrowUp), keyboardMode: true), .send(.key(.dpadUp)))
        XCTAssertEqual(KeyMapping.effect(for: KeyChord(key: .arrowDown), keyboardMode: true), .send(.key(.dpadDown)))
        XCTAssertEqual(KeyMapping.effect(for: KeyChord(key: .arrowLeft), keyboardMode: true), .send(.key(.dpadLeft)))
        XCTAssertEqual(KeyMapping.effect(for: KeyChord(key: .arrowRight), keyboardMode: true), .send(.key(.dpadRight)))
        XCTAssertEqual(KeyMapping.effect(for: KeyChord(key: .returnKey), keyboardMode: true), .send(.key(.dpadCenter)))
        XCTAssertEqual(KeyMapping.effect(for: KeyChord(key: .keypadEnter), keyboardMode: true), .send(.key(.dpadCenter)))
        XCTAssertEqual(KeyMapping.effect(for: KeyChord(key: .esc), keyboardMode: true), .send(.key(.back)))
        XCTAssertEqual(KeyMapping.effect(for: KeyChord(key: .delete), keyboardMode: true), .send(.key(.del)))
        XCTAssertEqual(KeyMapping.effect(for: KeyChord(key: .forwardDelete), keyboardMode: true), .send(.key(.forwardDel)))
    }

    func testHomeKeys() {
        XCTAssertEqual(KeyMapping.effect(for: KeyChord(key: .home), keyboardMode: true), .send(.key(.home)))
        XCTAssertEqual(KeyMapping.effect(for: KeyChord(key: .f1), keyboardMode: true), .send(.key(.home)))
        let plainH = KeyChord(key: .ansi("h"), characters: "h")
        XCTAssertEqual(KeyMapping.effect(for: plainH, keyboardMode: true), .send(.text("h")))
        let shiftedH = KeyChord(key: .ansi("h"), modifiers: [.shift], characters: "H")
        XCTAssertEqual(KeyMapping.effect(for: shiftedH, keyboardMode: true), .send(.text("H")))
        let controlH = KeyChord(key: .ansi("h"), modifiers: [.control])
        XCTAssertEqual(KeyMapping.effect(for: controlH, keyboardMode: true), .send(.key(.home)))
    }

    func testOtherLettersAreText() {
        let upper = KeyChord(key: .ansi("k"), modifiers: [.shift], characters: "K")
        XCTAssertEqual(KeyMapping.effect(for: upper, keyboardMode: true), .send(.text("K")))
        let fallback = KeyChord(key: .ansi("a"), modifiers: [.shift])
        XCTAssertEqual(KeyMapping.effect(for: fallback, keyboardMode: true), .send(.text("A")))
    }

    func testSpaceIsASpaceAndPunctuationIsText() {
        XCTAssertEqual(KeyMapping.effect(for: KeyChord(key: .space), keyboardMode: true), .send(.text(" ")))
        let comma = KeyChord(key: .other, characters: ",")
        XCTAssertEqual(KeyMapping.effect(for: comma, keyboardMode: true), .send(.text(",")))
    }

    func testCommandShortcutsPassThrough() {
        let copy = KeyChord(key: .ansi("c"), modifiers: [.command], characters: "c")
        XCTAssertEqual(KeyMapping.effect(for: copy, keyboardMode: true), .passthrough)
        let paste = KeyChord(key: .ansi("v"), modifiers: [.command], characters: "v")
        XCTAssertEqual(KeyMapping.effect(for: paste, keyboardMode: true), .passthrough)
        XCTAssertEqual(KeyMapping.effect(for: paste, keyboardMode: false), .ignore)
        let letter = KeyChord(key: .ansi("a"), characters: "a")
        XCTAssertEqual(
            KeyMapping.effect(for: letter, keyboardMode: true, textFieldFocused: true),
            .passthrough
        )
        XCTAssertEqual(
            KeyMapping.effect(for: KeyChord(key: .arrowUp), keyboardMode: true, textFieldFocused: true),
            .passthrough
        )
        XCTAssertEqual(
            KeyMapping.effect(for: paste, keyboardMode: true, textFieldFocused: true),
            .passthrough
        )
        let quit = KeyChord(key: .ansi("q"), modifiers: [.command])
        XCTAssertEqual(KeyMapping.effect(for: quit, keyboardMode: true), .passthrough)
    }

    func testOtherControlChordsPassThrough() {
        let controlC = KeyChord(key: .ansi("c"), modifiers: [.control])
        XCTAssertEqual(KeyMapping.effect(for: controlC, keyboardMode: true), .passthrough)
    }

    func testMediaKeys() {
        XCTAssertEqual(KeyMapping.effect(for: KeyChord(key: .mediaPlayPause), keyboardMode: true), .send(.key(.mediaPlayPause)))
        XCTAssertEqual(KeyMapping.effect(for: KeyChord(key: .volumeUp), keyboardMode: true), .send(.key(.volumeUp)))
        XCTAssertEqual(KeyMapping.effect(for: KeyChord(key: .volumeDown), keyboardMode: true), .send(.key(.volumeDown)))
        XCTAssertEqual(KeyMapping.effect(for: KeyChord(key: .mute), keyboardMode: true), .send(.key(.volumeMute)))
    }

    func testHotkeyDisplayAndMacKeyCodes() {
        XCTAssertEqual(Hotkey.default.display, "⌃⌥K")
        XCTAssertEqual(MacVirtualKey.inputKey(for: 126), .arrowUp)
        XCTAssertEqual(MacVirtualKey.inputKey(for: 36), .returnKey)
        XCTAssertEqual(MacVirtualKey.inputKey(for: 53), .esc)
        XCTAssertEqual(MacVirtualKey.inputKey(for: 51), .delete)
        XCTAssertEqual(MacVirtualKey.inputKey(for: 115), .home)
        XCTAssertEqual(MacVirtualKey.inputKey(for: 122), .f1)
        XCTAssertEqual(MacVirtualKey.inputKey(for: 4), .ansi("h"))
        XCTAssertEqual(MacVirtualKey.inputKey(for: 40), .ansi("k"))
        XCTAssertEqual(MacVirtualKey.inputKey(for: 49), .space)
        XCTAssertEqual(MacVirtualKey.inputKey(for: 72), .volumeUp)
    }

    func testTypingBufferFlushesBeforeOK() {
        let session = RemoteSession(settings: .factoryDefaults(), runner: FakeRunner())
        session.setKeyboardMode(true)
        XCTAssertEqual(session.ingest(KeyChord(key: .ansi("s"), characters: "s")), .buffered)
        XCTAssertEqual(session.ingest(KeyChord(key: .ansi("o"), characters: "o")), .buffered)
        XCTAssertEqual(
            session.ingest(KeyChord(key: .returnKey)),
            .flushAndSend(text: "so", action: .key(.dpadCenter))
        )
        XCTAssertEqual(session.flushTyping(), "")
    }
}
