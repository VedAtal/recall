import SwiftAppKit
import SwiftUI

/// What the menu bar icon opens: the latest clips, each pasted by a click or its number key.
/// SwiftAppKit adds the footer.
struct PanelView: View {
    let clips: [Clip]
    /// How many more are only in the history popup.
    let more: Int
    let shortcut: String
    let shortcutTaken: Bool
    let paste: @MainActor (Clip) -> Void
    let clearHistory: @MainActor () -> Void

    var body: some View {
        PanelSection("History") {
            if clips.isEmpty {
                Text("Nothing copied yet").foregroundStyle(.secondary)
            }
            VStack(spacing: 4) {
                ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                    row(clip, number: index + 1)
                }
            }
            if more > 0 {
                Text("\(more) more in \(shortcut)").font(.caption).foregroundStyle(.secondary)
            }
        }
        HStack {
            Text(shortcutTaken ? "\(shortcut) is taken. Pick another in Settings." : "Open history: \(shortcut)")
                .font(.callout)
                .foregroundStyle(shortcutTaken ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            Spacer()
            Button("Clear History", role: .destructive, action: clearHistory).disabled(clips.isEmpty)
        }
    }

    private func row(_ clip: Clip, number: Int) -> some View {
        Button { paste(clip) } label: {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(clip.title).lineLimit(1)
                    Text(clip.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.panelTile)
        .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: [])
        .help(String(clip.text.prefix(1000)))
    }
}
