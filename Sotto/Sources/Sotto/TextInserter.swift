import AppKit
import CoreGraphics

/// Inserts text into whatever app has focus by putting it on the clipboard,
/// simulating Cmd+V, then restoring the previous clipboard contents.
/// Requires the Accessibility permission (for posting the keystroke).
enum TextInserter {

    static func insert(_ text: String) {
        // If the user is still physically holding the hotkey modifier, wait
        // for it to be released so the paste isn't turned into Cmd+Opt+V etc.
        waitForModifierRelease(deadline: Date().addingTimeInterval(1.5)) {
            performInsert(text)
        }
    }

    private static func waitForModifierRelease(deadline: Date, then: @escaping () -> Void) {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let blockers: CGEventFlags = [.maskAlternate, .maskControl, .maskShift, .maskCommand]
        if flags.intersection(blockers).isEmpty || Date() > deadline {
            then()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                waitForModifierRelease(deadline: deadline, then: then)
            }
        }
    }

    private static func performInsert(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Snapshot current clipboard (all data types) so we can restore it
        let snapshot: [[NSPasteboard.PasteboardType: Data]] = (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    entry[type] = data
                }
            }
            return entry
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        postCmdV()

        // Give the frontmost app time to read the pasteboard, then restore
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            restore(snapshot)
        }
    }

    private static func restore(_ snapshot: [[NSPasteboard.PasteboardType: Data]]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        let items = snapshot.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }

    private static func postCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9 // kVK_ANSI_V
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
