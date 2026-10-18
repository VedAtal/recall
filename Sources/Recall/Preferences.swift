import Combine
import Foundation

/// User settings, backed by UserDefaults. AppDelegate observes these and applies changes live.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @Published var historyLimit: Int {
        didSet { defaults.set(historyLimit, forKey: Key.historyLimit) }
    }
    @Published var autoPaste: Bool {
        didSet { defaults.set(autoPaste, forKey: Key.autoPaste) }
    }
    @Published var stickyPanel: Bool {
        didSet { defaults.set(stickyPanel, forKey: Key.stickyPanel) }
    }
    @Published var persistHistory: Bool {
        didSet { defaults.set(persistHistory, forKey: Key.persistHistory) }
    }
    @Published var shortcut: Shortcut {
        didSet {
            defaults.set(Int(shortcut.keyCode), forKey: Key.shortcutKeyCode)
            defaults.set(Int(shortcut.carbonModifiers), forKey: Key.shortcutModifiers)
            defaults.set(shortcut.keyLabel, forKey: Key.shortcutLabel)
        }
    }

    // Runtime-only state shared with the settings window; not persisted.
    @Published var isRecordingShortcut = false
    @Published var shortcutError: String?

    private let defaults = UserDefaults.standard

    private enum Key {
        static let historyLimit = "historyLimit"
        static let autoPaste = "autoPaste"
        static let stickyPanel = "stickyPanel"
        static let persistHistory = "persistHistory"
        static let shortcutKeyCode = "shortcutKeyCode"
        static let shortcutModifiers = "shortcutModifiers"
        static let shortcutLabel = "shortcutLabel"
    }

    private init() {
        defaults.register(defaults: [
            Key.historyLimit: 50,
            Key.autoPaste: true,
            Key.stickyPanel: false,
            Key.persistHistory: true,
        ])
        historyLimit = defaults.integer(forKey: Key.historyLimit)
        autoPaste = defaults.bool(forKey: Key.autoPaste)
        stickyPanel = defaults.bool(forKey: Key.stickyPanel)
        persistHistory = defaults.bool(forKey: Key.persistHistory)
        if let label = defaults.string(forKey: Key.shortcutLabel) {
            shortcut = Shortcut(
                keyCode: UInt32(defaults.integer(forKey: Key.shortcutKeyCode)),
                carbonModifiers: UInt32(defaults.integer(forKey: Key.shortcutModifiers)),
                keyLabel: label
            )
        } else {
            shortcut = .defaultValue
        }
    }
}
