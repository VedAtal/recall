import AppKit
import Combine
import SwiftAppKit
import SwiftUI

/// Recall's parts on top of SwiftAppKit's standard menu bar app (menu, Settings, updates,
/// launch at login).
@MainActor
final class AppDelegate: MenuBarAppDelegate {
    private let prefs = Preferences.shared
    private let watcher = ClipboardWatcher()
    private let switcher = SwitcherController()
    private var store: HistoryStore!
    private let favorites = FavoritesStore()
    private var subscriptions = Set<AnyCancellable>()

    /// One per number key. The full history is in the ⇧⌘V popup.
    private static let maxMenuClips = 9
    private static let hotKeyName = "openHistory"

    override var needsAccessibility: Bool { prefs.autoPaste }

    override func start() {
        store = HistoryStore(limit: prefs.historyLimit, persist: prefs.persistHistory)

        watcher.onCopy = { [weak self] text, sourceApp in
            self?.store.add(text, sourceApp: sourceApp)
        }
        watcher.start()

        switcher.onChoose = { [weak self] clip in self?.paste(clip) }
        switcher.onDelete = { [weak self] clip in self?.store.remove(clip.id) }
        switcher.onToggleFavorite = { [weak self] clip in self?.favorites.toggle(clip) }
        switcher.history = { [weak self] in self?.store.clips ?? [] }
        switcher.favorites = { [weak self] in self?.favorites.clips ?? [] }

        registerShortcut(prefs.shortcut)
        observePreferences()
    }

    override func addMenuItems(to menu: NSMenu) {
        let clips = store.clips.prefix(Self.maxMenuClips)
        if clips.isEmpty {
            menu.addDisabledItem("Nothing copied yet")
        }
        for (index, clip) in clips.enumerated() {
            let item = menu.addItem(clip.menuTitle, key: "\(index + 1)", modifiers: []) { [weak self] in
                self?.paste(clip)
            }
            item.toolTip = String(clip.text.prefix(1000))
        }
        if store.clips.count > clips.count {
            menu.addDisabledItem("\(store.clips.count - clips.count) more in \(prefs.shortcut.displayString)")
        }

        menu.addItem(.separator())
        menu.addDisabledItem(HotKeyCenter.shared.failed.contains(Self.hotKeyName)
            ? "\(prefs.shortcut.displayString) is already in use. Pick another shortcut in Settings."
            : "Open history: \(prefs.shortcut.displayString)")
        menu.addItem("Clear History") { [weak self] in self?.store.clear() }.isEnabled = !store.clips.isEmpty
    }

    override func makeSettingsView() -> AnyView {
        AnyView(SettingsView(prefs: prefs) { [weak self] in self?.store.clear() })
    }

    private func hotKeyPressed() {
        if switcher.isVisible {
            switcher.selectNext()
        } else {
            switcher.show(shortcut: prefs.shortcut, sticky: prefs.stickyPanel)
        }
    }

    private func paste(_ clip: Clip) {
        Paster.copy(clip.text)
        watcher.skipCurrentContents()
        // Moves it to the top of History, and puts a favorite back there if it had dropped out.
        store.add(clip.text, sourceApp: clip.sourceApp)

        guard prefs.autoPaste else { return }
        guard Accessibility.isGranted else {
            // It's on the clipboard either way; only nag once per launch.
            Accessibility.requestOnce()
            return
        }
        Task { @MainActor in
            // Give focus a moment to settle back on the target app after the panel or menu closes.
            try? await Task.sleep(for: .milliseconds(100))
            Paster.pasteIntoFrontmostApp()
        }
    }

    private func registerShortcut(_ shortcut: Shortcut) {
        HotKeyCenter.shared.register(Self.hotKeyName, shortcut) { [weak self] in self?.hotKeyPressed() }
    }

    private func observePreferences() {
        // @Published fires before the property changes, so use the value passed in.
        prefs.$shortcut.dropFirst()
            .sink { [weak self] shortcut in self?.registerShortcut(shortcut) }
            .store(in: &subscriptions)

        prefs.$historyLimit.dropFirst()
            .sink { [weak self] limit in self?.store.limit = limit }
            .store(in: &subscriptions)

        prefs.$persistHistory.dropFirst()
            .sink { [weak self] persist in self?.store.persist = persist }
            .store(in: &subscriptions)
    }
}
