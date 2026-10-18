import SwiftAppKit
import SwiftUI

// Note: no @State/@StateObject in here. In this SDK @State is a macro whose plugin only ships
// with full Xcode, and Recall is meant to build with just the Command Line Tools.

/// Recall's sections of the Settings window. SettingsForm adds the standard General section.
struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    let onClearHistory: () -> Void

    var body: some View {
        SettingsForm(needsAccessibility: prefs.autoPaste) {
            Section {
                ShortcutField("Open history", shortcut: $prefs.shortcut, hotKey: "openHistory")
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
            }
        }
    }
}
