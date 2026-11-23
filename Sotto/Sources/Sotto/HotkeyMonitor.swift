import Foundation
import CoreGraphics
import AppKit

/// Watches the keyboard system-wide (CGEventTap, listen-only) for the
/// push-to-talk hotkey. Requires the Input Monitoring permission.
final class HotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private(set) var isRunning = false
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hotkeyIsDown = false

    /// Returns false if the event tap could not be created
    /// (Input Monitoring permission not granted yet).
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            if let userInfo {
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                monitor.handle(type: type, event: event)
            }
            return Unmanaged.passUnretained(event)
        }

        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let tap else { return false }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        isRunning = false
        hotkeyIsDown = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // macOS disables taps that stall or when secure input starts; revive.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        let hotkey = Settings.shared.hotkey
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if hotkey.isModifier {
            guard type == .flagsChanged, keyCode == hotkey.keyCode else { return }
            let downNow = event.flags.contains(hotkey.flagMask)
            transition(to: downNow)
        } else {
            guard keyCode == hotkey.keyCode else { return }
            if type == .keyDown {
                transition(to: true)
            } else if type == .keyUp {
                transition(to: false)
            }
        }
    }

    private func transition(to down: Bool) {
        guard down != hotkeyIsDown else { return } // ignore key-repeat
        hotkeyIsDown = down
        let handler = down ? onPress : onRelease
        DispatchQueue.main.async { handler?() }
    }
}
