import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Borderless panel that can take keyboard focus without activating Recall, so the app you're
/// pasting into stays frontmost the whole time.
private final class SwitcherWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SwitcherModel: ObservableObject {
    @Published var clips: [Clip] = []
    @Published var selection = 0
    @Published var releaseHint = ""
    /// Bumped on every show so the list starts out scrolled to the top.
    @Published var generation = 0

    var selectedClip: Clip? { clips.indices.contains(selection) ? clips[selection] : nil }
}

/// The history popup. Hold the shortcut's modifiers, tap the key again (or use the arrows) to go
/// further back, and let go to paste. This is the same interaction as Flycut.
@MainActor
final class SwitcherController {
    var onChoose: ((Clip) -> Void)?
    var onDelete: ((Clip) -> Void)?

    var isVisible: Bool { panel.isVisible }

    private let panel: SwitcherWindow
    private let model = SwitcherModel()
    private var heldModifiers: NSEvent.ModifierFlags = []
    private var shortcutKeyCode = 0
    private var sticky = false
    private var eventMonitor: Any?
    private var releaseTimer: Timer?
    private var resignObserver: NSObjectProtocol?

    init() {
        panel = SwitcherWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 440),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true

        let host = NSHostingView(rootView: SwitcherView(model: model) { [weak self] index in
            self?.choose(at: index)
        })
        host.frame = background.bounds
        host.autoresizingMask = [.width, .height]
        background.addSubview(host)
        panel.contentView = background
    }

    func show(clips: [Clip], shortcut: Shortcut, sticky: Bool) {
        model.clips = clips
        model.selection = 0
        model.generation += 1
        model.releaseHint = sticky ? "↩ paste" : "release \(shortcut.modifierSymbols) to paste"
        heldModifiers = shortcut.cocoaModifiers
        shortcutKeyCode = Int(shortcut.keyCode)
        self.sticky = sticky

        positionOnActiveScreen()
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.invalidateShadow()
        startTracking()

        // The keys may already be up by the time we get here; treat that as a quick tap.
        checkRelease(NSEvent.modifierFlags)
    }

    func selectNext() {
        move(by: 1)
    }

    func hide() {
        stopTracking()
        if panel.isVisible { panel.orderOut(nil) }
    }

    // MARK: - Keyboard

    private func startTracking() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return handled ? nil : event
        }

        // Backup for flagsChanged: catches a key release we never got an event for.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkRelease(NSEvent.modifierFlags) }
        }
        RunLoop.main.add(timer, forMode: .common)
        releaseTimer = timer

        // Clicking elsewhere dismisses the panel.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func stopTracking() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        releaseTimer?.invalidate()
        releaseTimer = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }

    private func checkRelease(_ flags: NSEvent.ModifierFlags) {
        guard panel.isVisible, !sticky, flags.intersection(heldModifiers).isEmpty else { return }
        confirm()
    }

    /// Returns true if the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        if event.type == .flagsChanged {
            checkRelease(event.modifierFlags)
            return false
        }

        switch Int(event.keyCode) {
        case kVK_DownArrow: move(by: 1)
        case kVK_UpArrow: move(by: -1)
        case kVK_PageDown: move(by: 9, wrap: false)
        case kVK_PageUp: move(by: -9, wrap: false)
        case kVK_Home: move(to: 0)
        case kVK_End: move(to: model.clips.count - 1)
        case kVK_Return, kVK_ANSI_KeypadEnter: confirm()
        case kVK_Escape: hide()
        case kVK_Delete, kVK_ForwardDelete: deleteSelected()
        case shortcutKeyCode:
            // With all of its modifiers held, the shortcut goes to the hotkey handler instead.
            // This catches it after some were let go. Adding ⇧ (if it isn't part of the
            // shortcut) goes back.
            let back = event.modifierFlags.contains(.shift) && !heldModifiers.contains(.shift)
            move(by: back ? -1 : 1)
        default:
            if let digit = event.characters(byApplyingModifiers: []).flatMap({ Int($0) }), (1...9).contains(digit) {
                choose(at: digit - 1)
            }
        }
        // Swallow everything else too, so stray keys don't beep or reach the app underneath.
        return true
    }

    // MARK: - Selection

    private func move(by delta: Int, wrap: Bool = true) {
        let count = model.clips.count
        guard count > 0 else { return }
        let target = model.selection + delta
        model.selection = wrap ? (target % count + count) % count : min(max(target, 0), count - 1)
    }

    private func move(to index: Int) {
        guard !model.clips.isEmpty else { return }
        model.selection = min(max(index, 0), model.clips.count - 1)
    }

    private func choose(at index: Int) {
        guard model.clips.indices.contains(index) else { return }
        model.selection = index
        confirm()
    }

    private func confirm() {
        let clip = model.selectedClip
        hide()
        if let clip { onChoose?(clip) }
    }

    private func deleteSelected() {
        guard let clip = model.selectedClip else { return }
        onDelete?(clip)
        model.clips.remove(at: model.selection)
        model.selection = min(model.selection, max(model.clips.count - 1, 0))
    }

    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        // A little above center, like Spotlight.
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2 + visible.height * 0.1
        ))
    }
}

// MARK: - Views

private struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    let onPick: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if model.clips.isEmpty {
                ContentUnavailableView(
                    "Nothing copied yet",
                    systemImage: "list.clipboard",
                    description: Text("Copy some text and it will show up here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
                Divider()
                preview
            }
            Divider()
            footer
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.clips.enumerated()), id: \.element.id) { index, clip in
                        ClipRow(clip: clip, index: index, isSelected: index == model.selection)
                            .contentShape(Rectangle())
                            .onTapGesture { onPick(index) }
                    }
                }
                .padding(8)
            }
            .id(model.generation)
            .onChange(of: model.selection) { _, selection in
                guard model.clips.indices.contains(selection) else { return }
                proxy.scrollTo(model.clips[selection].id)
            }
        }
    }

    private var preview: some View {
        Text(model.selectedClip.map { String($0.text.prefix(3000)) } ?? "")
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(height: 130)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text(model.releaseHint)
            Text("↑↓ move")
            Text("1–9 pick")
            Text("⌫ delete")
            Text("esc cancel")
            Spacer()
            if !model.clips.isEmpty {
                Text("\(model.selection + 1) of \(model.clips.count)").monospacedDigit()
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 30)
    }
}

private struct ClipRow: View {
    let clip: Clip
    let index: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(index < 9 ? "\(index + 1)" : "")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                .frame(width: 14)
            Text(clip.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
            Spacer(minLength: 8)
            Text(clip.subtitle)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 7).fill(isSelected ? Color.accentColor : Color.clear))
    }
}
