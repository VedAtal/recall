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

/// A JSON file of clips in ~/Library/Application Support/Recall. Writes happen in the background.
struct ClipFile: Sendable {
    let url: URL
    private let queue: DispatchQueue

    init(_ name: String) {
        url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recall", isDirectory: true)
            .appendingPathComponent(name)
        queue = DispatchQueue(label: "recall.\(name)", qos: .utility)
    }

    func load() -> [Clip]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode([Clip].self, from: data)
    }

    func save(_ clips: [Clip]) {
        let url = url
        queue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(clips) else { return }
            let fileManager = FileManager.default
            // Clips can contain anything you've copied, so keep them readable only by you.
            try? fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            guard (try? data.write(to: url, options: .atomic)) != nil else { return }
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    func delete() {
        let url = url
        queue.async { try? FileManager.default.removeItem(at: url) }
    }
}

/// The clipboard history, newest first.
@MainActor
final class HistoryStore {
    private(set) var clips: [Clip] = []

    var limit: Int {
        didSet { trim(); save() }
    }
    var persist: Bool {
        didSet { persist ? save() : file.delete() }
    }

    private let file = ClipFile("history.json")

    init(limit: Int, persist: Bool) {
        self.limit = max(1, limit)
        self.persist = persist
        if persist {
            clips = file.load() ?? []
            trim()
        } else {
            file.delete()
        }
    }

    /// Records a copy, or moves it to the top (as copied now) if the same text is already here.
    func add(_ text: String, sourceApp: String?) {
        clips.removeAll { $0.text == text }
        clips.insert(Clip(text: text, copiedAt: .now, sourceApp: sourceApp), at: 0)
        trim()
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

    private func save() {
        if persist { file.save(clips) }
    }
}

/// Favorited clips, most recently favorited first. Unlike history, they're always saved, never
/// trimmed, and Clear History leaves them alone.
@MainActor
final class FavoritesStore {
    private(set) var clips: [Clip] = []

    private let file = ClipFile("favorites.json")

    init() {
        clips = file.load() ?? []
    }

    /// Favorites the clip, or unfavorites it if the same text is already a favorite.
    func toggle(_ clip: Clip) {
        if let index = clips.firstIndex(where: { $0.text == clip.text }) {
            clips.remove(at: index)
        } else {
            clips.insert(Clip(text: clip.text, copiedAt: .now, sourceApp: clip.sourceApp), at: 0)
        }
        file.save(clips)
    }
}
