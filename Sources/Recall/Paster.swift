import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Puts text on the clipboard and, with Accessibility access, pastes it into the frontmost app
/// by sending a synthetic ⌘V. (The access itself is SwiftAppKit's `Accessibility`.)
enum Paster {
    @MainActor
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @MainActor
    static func pasteIntoFrontmostApp() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Keep modifiers the user is still physically holding (e.g. ⇧ from the shortcut) out of
        // the synthetic ⌘V, so it doesn't turn into "Paste and Match Style".
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        let vKey = CGKeyCode(kVK_ANSI_V)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
