import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let prefs = Preferences.shared
    private let watcher = ClipboardWatcher()
    private let hotKey = HotKey()
    private let switcher = SwitcherController()
    private let updater = Updater()
    private var store: HistoryStore!
    private var menuBar: MenuBarController!
    private var settingsWindow: SettingsWindowController!
    private var subscriptions = Set<AnyCancellable>()
    private var promptedForAccessibility = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = HistoryStore(limit: prefs.historyLimit, persist: prefs.persistHistory)

        watcher.onCopy = { [weak self] text, sourceApp in
            self?.store.add(text, sourceApp: sourceApp)
        }
        watcher.start()

        switcher.onChoose = { [weak self] clip in self?.paste(clip) }
        switcher.onDelete = { [weak self] clip in self?.store.remove(clip.id) }

        hotKey.onPress = { [weak self] in self?.hotKeyPressed() }
        registerShortcut(prefs.shortcut)

        settingsWindow = SettingsWindowController(prefs: prefs) { [weak self] in self?.store.clear() }

        menuBar = MenuBarController(store: store, prefs: prefs, updater: updater)
        menuBar.onPick = { [weak self] clip in self?.paste(clip) }
        menuBar.onClear = { [weak self] in self?.store.clear() }
        menuBar.onOpenSettings = { [weak self] in self?.settingsWindow.show() }

        observePreferences()
        enableLaunchAtLoginOnFirstRun()

        if prefs.autoPaste && !Paster.hasAccessibility {
            promptedForAccessibility = true
            Paster.requestAccessibility()
        }
    }

    // Opening the app again (Finder, Spotlight) while it's running shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return false
    }

    private func hotKeyPressed() {
        if switcher.isVisible {
            switcher.selectNext()
        } else {
            switcher.show(clips: store.clips, shortcut: prefs.shortcut, sticky: prefs.stickyPanel)
        }
    }

    private func paste(_ clip: Clip) {
        Paster.copy(clip.text)
        watcher.skipCurrentContents()
        store.promote(clip.id)

        guard prefs.autoPaste else { return }
        guard Paster.hasAccessibility else {
            // It's on the clipboard either way; only nag once per launch.
            if !promptedForAccessibility {
                promptedForAccessibility = true
                Paster.requestAccessibility()
            }
            return
        }
        Task { @MainActor in
            // Give focus a moment to settle back on the target app after the panel or menu closes.
            try? await Task.sleep(for: .milliseconds(100))
            Paster.pasteIntoFrontmostApp()
        }
    }

    private func registerShortcut(_ shortcut: Shortcut) {
        prefs.shortcutError = hotKey.register(shortcut)
            ? nil
            : "\(shortcut.displayString) is already in use. Pick another shortcut in Settings."
    }

    private func observePreferences() {
        // @Published fires before the property changes, so use the value passed in.
        prefs.$shortcut.dropFirst()
            .sink { [weak self] shortcut in self?.registerShortcut(shortcut) }
            .store(in: &subscriptions)

        prefs.$isRecordingShortcut.dropFirst()
            .sink { [weak self] recording in
                guard let self else { return }
                // Stop listening while a new shortcut is being typed, so the old one doesn't fire.
                if recording { hotKey.unregister() } else { registerShortcut(prefs.shortcut) }
            }
            .store(in: &subscriptions)

        prefs.$historyLimit.dropFirst()
            .sink { [weak self] limit in self?.store.limit = limit }
            .store(in: &subscriptions)

        prefs.$persistHistory.dropFirst()
            .sink { [weak self] persist in self?.store.persist = persist }
            .store(in: &subscriptions)
    }

    private func enableLaunchAtLoginOnFirstRun() {
        let key = "configuredLoginItem"
        // Only the installed copy, so running a dev build doesn't add a login item.
        guard !UserDefaults.standard.bool(forKey: key),
              Bundle.main.bundlePath.contains("/Applications/") else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? LoginItem.setEnabled(true)
    }
}
