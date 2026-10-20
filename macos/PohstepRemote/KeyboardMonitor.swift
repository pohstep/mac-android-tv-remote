import AppKit
import Carbon

/// Global hotkey is Control-Option-K. Full keyboard capture needs Accessibility,
/// because that is what lets one Mac app swallow keys destined for another.
final class KeyboardMonitor {
    private weak var model: AppModel?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var swallowed = Set<Int64>()
    private var captureAvailable = false

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        installTapIfTrusted(prompt: false)
        if tap == nil {
            installCarbonHotkey()
        }
    }

    func accessibilityStatus() -> Bool {
        AXIsProcessTrusted()
    }

    func promptForAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        installTapIfTrusted(prompt: false)
    }

    func refreshCapture() {
        installTapIfTrusted(prompt: false)
    }

    private func installTapIfTrusted(prompt: Bool) {
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else { return }
        // Keyboard only (keyDown/keyUp/flagsChanged). Mouse, trackpad and clicks are never tapped,
        // so the panel toggle can always be clicked off.
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            captureAvailable = false
            return
        }
        tap = created
        captureAvailable = true
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: created, enable: true)
        removeCarbonHotkey()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp {
            if swallowed.remove(keyCode) != nil {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
        // Modifier changes (flagsChanged) always pass through to the Mac.
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let chord = chord(from: event, keyCode: keyCode)
        guard let model else { return Unmanaged.passUnretained(event) }

        if model.settingsFieldsAreActive && !model.hotkey.matches(chord) {
            return Unmanaged.passUnretained(event)
        }

        let result = model.session.ingest(chord)
        switch result {
        case .ignored, .passthrough:
            return Unmanaged.passUnretained(event)
        case .toggled, .buffered, .flushAndSend, .send:
            swallowed.insert(keyCode)
            DispatchQueue.main.async {
                model.deliver(result)
            }
            return nil
        }
    }

    private func chord(from event: CGEvent, keyCode: Int64) -> KeyChord {
        var modifiers = KeyModifiers()
        let flags = event.flags
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        return KeyChord(
            key: MacVirtualKey.inputKey(for: Int(keyCode)),
            modifiers: modifiers,
            characters: characters(from: event)
        )
    }

    private func characters(from event: CGEvent) -> String {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &buffer)
        guard length > 0 else { return "" }
        return String(utf16CodeUnits: buffer, count: length)
    }

    private func installCarbonHotkey() {
        guard hotKey == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                monitor.model?.toggleKeyboardMode()
            }
            return noErr
        }, 1, &eventType, refcon, &handler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x5048_524D), id: 1)
        let modifiers = UInt32(controlKey | optionKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_K), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKey)
    }

    private func removeCarbonHotkey() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    var canCaptureKeys: Bool { captureAvailable }
}
