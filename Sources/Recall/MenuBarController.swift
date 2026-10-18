import AppKit

/// The menu bar icon and its menu: recent clips plus app commands.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    var onPick: ((Clip) -> Void)?
    var onClear: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let store: HistoryStore
    private let prefs: Preferences
    private let updater: Updater

    private static let maxMenuClips = 25

    init(store: HistoryStore, prefs: Preferences, updater: Updater) {
        self.store = store
        self.prefs = prefs
        self.updater = updater
        super.init()

        let image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Recall")
        image?.isTemplate = true
        statusItem.button?.image = image

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // Rebuilt every time it opens, so it always reflects the current history.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let clips = store.clips.prefix(Self.maxMenuClips)
        if clips.isEmpty {
            menu.addItem(disabledItem("Nothing copied yet"))
        }
        for (index, clip) in clips.enumerated() {
            let item = NSMenuItem(title: clip.menuTitle, action: #selector(pick(_:)), keyEquivalent: index < 9 ? "\(index + 1)" : "")
            item.keyEquivalentModifierMask = []
            item.target = self
            item.representedObject = clip.id
            item.toolTip = String(clip.text.prefix(1000))
            menu.addItem(item)
        }
        if store.clips.count > clips.count {
            menu.addItem(disabledItem("\(store.clips.count - clips.count) more in \(prefs.shortcut.displayString)"))
        }

        menu.addItem(.separator())
        menu.addItem(disabledItem(prefs.shortcutError ?? "Open history: \(prefs.shortcut.displayString)"))
        if prefs.autoPaste && !Paster.hasAccessibility {
            menu.addItem(actionItem("Grant Accessibility Access…", #selector(grantAccessibility)))
        }
        let clear = actionItem("Clear History", #selector(clear))
        clear.isEnabled = !store.clips.isEmpty
        menu.addItem(clear)

        menu.addItem(.separator())
        let launchAtLogin = actionItem("Launch at Login", #selector(toggleLaunchAtLogin))
        launchAtLogin.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(launchAtLogin)
        menu.addItem(actionItem("Settings…", #selector(openSettings), key: ","))

        menu.addItem(.separator())
        if updater.isUpdating {
            menu.addItem(disabledItem("Updating Recall…"))
        } else {
            let update = actionItem("Update Recall", #selector(update))
            update.toolTip = Updater.sourceDirectory.map { "Rebuild from \($0.path) and restart" }
            menu.addItem(update)
        }
        if let built = Updater.buildDate {
            menu.addItem(disabledItem("Built \(built.formatted(.relative(presentation: .named)))"))
        }
        menu.addItem(actionItem("Quit Recall", #selector(quit), key: "q"))
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let clip = store.clips.first(where: { $0.id == id }) else { return }
        onPick?(clip)
    }

    @objc private func grantAccessibility() {
        Paster.requestAccessibility()
        Paster.openAccessibilitySettings()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            NSApp.activate()
            NSAlert(error: error).runModal()
        }
    }

    @objc private func update() { updater.update() }
    @objc private func clear() { onClear?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func actionItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
