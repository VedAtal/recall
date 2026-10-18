import Foundation

struct Clip: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var text: String
    var copiedAt: Date
    /// Name of the app that was frontmost when this was copied.
    var sourceApp: String?
}

extension Clip {
    /// Single-line version for lists: outer whitespace trimmed, line breaks shown as ↩.
    var title: String {
        String(text.prefix(400))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ↩ ")
            .replacingOccurrences(of: "\t", with: " ")
    }

    var menuTitle: String {
        let title = self.title
        return title.count > 60 ? title.prefix(60) + "…" : title
    }

    var subtitle: String {
        [sourceApp, age].compactMap { $0 }.joined(separator: " · ")
    }

    private var age: String {
        let seconds = Int(Date.now.timeIntervalSince(copiedAt))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86400)d"
        }
    }
}

/// The clipboard history, newest first. Saved as JSON in ~/Library/Application Support/Recall.
@MainActor
final class HistoryStore {
    private(set) var clips: [Clip] = []

    var limit: Int {
        didSet { trim(); save() }
    }
    var persist: Bool {
        didSet { persist ? save() : deleteFile() }
    }

    private let fileURL: URL
    private let ioQueue = DispatchQueue(label: "recall.history", qos: .utility)

    init(limit: Int, persist: Bool) {
        self.limit = max(1, limit)
        self.persist = persist
        fileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recall", isDirectory: true)
            .appendingPathComponent("history.json")
        if persist { load() } else { deleteFile() }
    }

    /// Records a new copy. Copying something already in the history moves it to the top.
    func add(_ text: String, sourceApp: String?) {
        clips.removeAll { $0.text == text }
        clips.insert(Clip(text: text, copiedAt: .now, sourceApp: sourceApp), at: 0)
        trim()
        save()
    }

    /// Moves an existing clip to the top, e.g. after it's been pasted.
    func promote(_ id: Clip.ID) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        var clip = clips.remove(at: index)
        clip.copiedAt = .now
        clips.insert(clip, at: 0)
        save()
    }

    func remove(_ id: Clip.ID) {
        clips.removeAll { $0.id == id }
        save()
    }

    func clear() {
        clips.removeAll()
        save()
    }

    private func trim() {
        if clips.count > limit { clips.removeLast(clips.count - limit) }
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? decoder.decode([Clip].self, from: data) else { return }
        clips = saved
        trim()
    }

    private func save() {
        guard persist else { return }
        let snapshot = clips
        let url = fileURL
        ioQueue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            let fileManager = FileManager.default
            // History can contain anything you've copied, so keep it readable only by you.
            try? fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            guard (try? data.write(to: url, options: .atomic)) != nil else { return }
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    private func deleteFile() {
        let url = fileURL
        ioQueue.async { try? FileManager.default.removeItem(at: url) }
    }
}
