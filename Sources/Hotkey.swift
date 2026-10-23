import AppKit
import ApplicationServices

struct Shortcut: Codable, Equatable {
    var keyCode: UInt16 = 2
    var flags: UInt64 = CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue
    var label: String = "Control + Shift + D"
    var isFn: Bool { keyCode == 63 }
}

final class HotkeyOutput {
    private var pressed: Shortcut?
    private var activeMode: String?
    var dryRun = false
    var observer: ((String) -> Void)?
    static var trusted: Bool { AXIsProcessTrusted() }
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    private func post(_ shortcut: Shortcut, down: Bool) {
        observer?(down ? "down" : "up")
        guard !dryRun else { return }
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: shortcut.keyCode, keyDown: down) else { return }
        if shortcut.isFn {
            event.type = .flagsChanged
            event.flags = down ? [.maskSecondaryFn] : []
        } else {
            event.flags = down ? CGEventFlags(rawValue: shortcut.flags) : []
        }
        event.setIntegerValueField(.eventSourceUserData, value: 0x5331425249444745)
        event.post(tap: .cghidEventTap)
    }
    func begin(_ shortcut: Shortcut, mode: String) throws {
        guard pressed == nil else { return }
        guard dryRun || Self.trusted else { throw BridgeError.message("请先授权辅助功能，再启用快捷键联动。") }
        pressed = shortcut; activeMode = mode
        post(shortcut, down: true)
        if mode == "toggle" { post(shortcut, down: false) }
    }
    func end() {
        guard let shortcut = pressed else { return }
        let mode = activeMode
        pressed = nil; activeMode = nil
        if mode == "toggle" { post(shortcut, down: true) }
        post(shortcut, down: false)
    }
    deinit { end() }
}

final class ShortcutRecorder {
    private var monitor: Any?
    var onCapture: ((Shortcut) -> Void)?
    var onCancel: (() -> Void)?
    func start() {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.stop(); self.onCancel?(); return nil }
            if event.type == .flagsChanged && event.keyCode != 63 { return event }
            if event.keyCode == 63 && !event.modifierFlags.contains(.function) { return event }
            let clean = event.modifierFlags.intersection([.command, .control, .option, .shift, .function])
            var parts: [String] = []
            if clean.contains(.control) { parts.append("Control") }
            if clean.contains(.option) { parts.append("Option") }
            if clean.contains(.shift) { parts.append("Shift") }
            if clean.contains(.command) { parts.append("Command") }
            let key = event.keyCode == 63 ? "Fn" : (event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)")
            parts.append(key)
            let result = Shortcut(keyCode: event.keyCode, flags: UInt64(clean.rawValue), label: parts.joined(separator: " + "))
            self.stop(); self.onCapture?(result)
            return nil
        }
    }
    func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    deinit { stop() }
}
