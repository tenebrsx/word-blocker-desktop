import Cocoa
import ApplicationServices

enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }
    static func prompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

/// Posts synthetic keys, tagged so our own tap ignores them.
enum Synth {
    static let tag: Int64 = 0x57424C4B // 'WBLK'

    static func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down) else { continue }
            e.flags = flags
            e.setIntegerValueField(.eventSourceUserData, value: tag)
            e.post(tap: .cghidEventTap)
        }
    }

    static func backspaces(_ n: Int) {
        guard n > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            for _ in 0..<n { key(0x33); usleep(1500) }
        }
    }

    static func closeTab() { key(0x0D, flags: .maskCommand) } // Cmd+W
}

/// Keeps a short buffer of what you just typed and runs it through the shared Word Block engine
/// (same engine + test vectors as the iOS browser).
final class TypingBuffer {
    private(set) var text = ""
    private let maxLen = 120

    /// Returns the number of characters to erase, or nil.
    func type(_ s: String, engine: WordBlockEngine) -> Int? {
        text += s
        if text.count > maxLen { text = String(text.suffix(maxLen)) }
        return check(engine: engine, isFinal: false)
    }

    func check(engine: WordBlockEngine, isFinal: Bool) -> Int? {
        let out = engine.sanitize(text, isFinal: isFinal)
        guard out != text else { return nil }
        let prefix = text.commonPrefix(with: out)
        let delete = text.count - prefix.count
        text = prefix
        return delete > 0 ? delete : nil
    }

    func backspace() { if !text.isEmpty { text.removeLast() } }
    func reset() { text = "" }
}

final class KeyboardGuard {
    static let shared = KeyboardGuard()
    private var port: CFMachPort?
    private let buffer = TypingBuffer()
    var isActive: Bool { port != nil }

    @discardableResult
    func start() -> Bool {
        if port != nil { return true }
        guard Permissions.accessibility else { return false }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: { _, type, event, _ in KeyboardGuard.shared.handle(type, event) },
                                          userInfo: nil) else { return false }
        port = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let p = port { CGEvent.tapEnable(tap: p, enable: true) }
            return pass
        }
        if type == .leftMouseDown { buffer.reset(); return pass }
        guard type == .keyDown, event.getIntegerValueField(.eventSourceUserData) != Synth.tag else { return pass }

        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let engine = Store.shared.engine
        if flags.contains(.maskCommand) || flags.contains(.maskControl) { buffer.reset(); return pass }
        if code == 0x33 { buffer.backspace(); return pass }
        if code == 0x24 || code == 0x4C {
            // Enter: final check. If the line ends with a blocked word, erase it and hold this Enter.
            if let n = buffer.check(engine: engine, isFinal: true) {
                erased(n)
                buffer.reset()
                return nil
            }
            buffer.reset(); return pass
        }
        if (0x7B...0x7E).contains(code) || code == 0x30 || code == 0x35 { buffer.reset(); return pass }

        var len = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &len, unicodeString: &chars)
        guard len > 0 else { return pass }
        let typed = String(utf16CodeUnits: chars, count: len)
        if let n = buffer.type(typed, engine: engine) { erased(n) }
        return pass
    }

    private func erased(_ n: Int) {
        Synth.backspaces(n)
        DispatchQueue.main.async {
            Store.shared.recordBlock()
            if Store.shared.state.soundOn { NSSound(named: "Tink")?.play() }
            if Store.shared.state.toastOn { Toast.show("Word removed — you've got this.") }
        }
    }
}
