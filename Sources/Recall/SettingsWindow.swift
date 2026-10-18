import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

// Note: no @State/@StateObject in here. In this SDK @State is a macro whose plugin only ships
// with full Xcode, and Recall is meant to build with just the Command Line Tools. View-local
// state lives in SettingsState instead.

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private let prefs: Preferences
    private let state: SettingsState
    private let onClearHistory: () -> Void

    init(prefs: Preferences, onClearHistory: @escaping () -> Void) {
        self.prefs = prefs
        self.state = SettingsState(prefs: prefs)
        self.onClearHistory = onClearHistory
    }

    func show() {
        state.refresh()
        if window == nil {
            let view = SettingsView(prefs: prefs, state: state, onClearHistory: onClearHistory)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Recall Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
            // Hand focus back to whatever app was in front before Settings opened.
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { _ in
                MainActor.assumeIsolated { NSApp.hide(nil) }
            }
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class SettingsState: ObservableObject {
    @Published private(set) var launchAtLogin = false
    @Published private(set) var loginItemError: String?
    @Published private(set) var hasAccessibility = false

    private let prefs: Preferences
    private var keyMonitor: Any?
    private var closeObserver: NSObjectProtocol?

    init(prefs: Preferences) {
        self.prefs = prefs
        refresh()
    }

    /// Re-reads things that can change outside Recall (System Settings).
    func refresh() {
        launchAtLogin = LoginItem.isEnabled
        hasAccessibility = Paster.hasAccessibility
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        launchAtLogin = LoginItem.isEnabled
    }

    // MARK: Shortcut recording

    func startRecording() {
        // AppDelegate unregisters the current hotkey while this is true, so typing it again works.
        prefs.isRecordingShortcut = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.record(event) }
            return nil
        }
        // Don't stay in recording mode (with no hotkey) if the window is closed mid-recording.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopRecording() }
        }
    }

    func stopRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        prefs.isRecordingShortcut = false
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }
        guard let shortcut = Shortcut(event: event) else {
            NSSound.beep() // needs ⌘, ⌃ or ⌥
            return
        }
        prefs.shortcut = shortcut
        stopRecording()
    }
}

private struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var state: SettingsState
    let onClearHistory: () -> Void

    // Access can be granted in System Settings while this window is open, so keep checking.
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                LabeledContent("Open history") {
                    Button(prefs.isRecordingShortcut ? "Type a shortcut…" : prefs.shortcut.displayString) {
                        if prefs.isRecordingShortcut { state.stopRecording() } else { state.startRecording() }
                    }
                    .frame(minWidth: 130)
                }
                if let error = prefs.shortcutError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
                Toggle("Keep the list open after releasing the shortcut", isOn: $prefs.stickyPanel)
            } header: {
                Text("Shortcut")
            } footer: {
                Text(prefs.stickyPanel
                     ? "Use the arrow keys, then press ↩ or click an item to paste."
                     : "Hold the modifier keys, tap the key again to go further back, and let go to paste.")
                    .foregroundStyle(.secondary)
            }

            Section("History") {
                Stepper("Remember the last \(prefs.historyLimit) items", value: $prefs.historyLimit, in: 5...1000, step: 5)
                Toggle("Keep history after quitting", isOn: $prefs.persistHistory)
                Button("Clear History", role: .destructive, action: onClearHistory)
            }

            Section("Pasting") {
                Toggle("Paste into the active app after choosing an item", isOn: $prefs.autoPaste)
                if prefs.autoPaste {
                    LabeledContent("Accessibility access") {
                        if state.hasAccessibility {
                            Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button("Grant Access…") {
                                Paster.requestAccessibility()
                                Paster.openAccessibilitySettings()
                            }
                        }
                    }
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
                if let error = state.loginItemError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 540)
        .onReceive(refreshTimer) { _ in state.refresh() }
    }
}
