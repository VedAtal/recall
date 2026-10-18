import AppKit

/// "Update Recall": runs the copy of setup.sh bundled in the app, in its default mode, which
/// downloads the latest Recall from GitHub and installs it. Progress shows in the update window.
/// On success, setup.sh quits this copy and launches the new build with --updated, and the new
/// build shows the result.
@MainActor
final class Updater {
    var isUpdating: Bool { process != nil }

    private var process: Process?
    private var logTimer: Timer?
    private let window = UpdateWindowController()

    /// Where updates come from: the HTTPS URL of the repo this copy was built from.
    static var repositoryURL: String? { infoString("RecallRepositoryURL") }

    /// The commit this copy was built from, with a "-dirty" suffix if it had uncommitted changes.
    static var commit: String? { infoString("RecallCommit") }

    static var commitSubject: String? { infoString("RecallCommitSubject") }

    static var buildDate: Date? {
        infoString("RecallBuildDate").flatMap { try? Date($0, strategy: .iso8601) }
    }

    /// "github.com/owner/repo", for display.
    static var repositoryName: String? {
        repositoryURL.map {
            $0.replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: ".git", with: "", options: [.anchored, .backwards])
        }
    }

    /// e.g. "59ba24f", or "59ba24f (modified)" for a --local build with uncommitted changes.
    static var shortCommit: String? {
        commit.map { String($0.prefix(7)) + ($0.hasSuffix("-dirty") ? " (modified)" : "") }
    }

    /// e.g. "Version 59ba24f · built 5 minutes ago".
    static var versionDescription: String? {
        let built = buildDate.map { "built \($0.formatted(.relative(presentation: .named)))" }
        guard let shortCommit else { return built.map { $0.prefix(1).uppercased() + $0.dropFirst() } }
        return ["Version \(shortCommit)", built].compactMap { $0 }.joined(separator: " · ")
    }

    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Recall/update.log")

    /// Starts an update, or brings the progress window back if one is already running.
    func update() {
        guard !isUpdating else {
            window.show()
            return
        }
        guard let repositoryURL = Self.repositoryURL,
              let script = Bundle.main.url(forResource: "setup", withExtension: "sh") else {
            showAlert("This copy of Recall doesn't know where to get updates",
                      info: "It was built from a folder with no GitHub remote. Run setup.sh from a clone of the repository once, and Update Recall will work from then on.")
            return
        }

        let log: FileHandle
        do {
            try FileManager.default.createDirectory(at: Self.logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: Self.logURL.path, contents: nil)
            log = try FileHandle(forWritingTo: Self.logURL)
        } catch {
            showAlert("Couldn't start the update", info: error.localizedDescription)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        // The bundled script isn't in a git checkout, so tell it which repo to install from, and
        // that it should relaunch Recall with --updated when it's done.
        process.environment = ProcessInfo.processInfo.environment.merging([
            "RECALL_REPO": repositoryURL,
            "RECALL_FROM_APP": "1",
        ]) { $1 }
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = FileHandle.nullDevice
        // Output goes to a file, not a pipe. setup.sh quits this app partway through, and writing
        // to a pipe nobody is reading anymore would kill the script.
        process.standardOutput = log
        process.standardError = log
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor in self?.finished(status: status) }
        }

        do {
            try process.run()
        } catch {
            showAlert("Couldn't start the update", info: error.localizedDescription)
            return
        }
        self.process = process
        window.progress.start()
        window.show()

        // The script's output is the progress report: follow the log as it grows.
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.readLog() }
        }
        RunLoop.main.add(timer, forMode: .common)
        logTimer = timer
    }

    /// Called at launch when setup.sh started this copy with --updated.
    func showUpdateResult() {
        window.progress.finish(.updated)
        window.show()
    }

    private func readLog() {
        window.progress.update(fromLog: (try? String(contentsOf: Self.logURL, encoding: .utf8)) ?? "")
    }

    private func finished(status: Int32) {
        process = nil
        logTimer?.invalidate()
        logTimer = nil
        readLog()
        // A successful install quits this copy before the script exits. So if we're still here,
        // either the script found nothing newer (exit 0) or it failed. Either way, this version is
        // still the one running.
        window.progress.finish(status == 0 ? .upToDate : .failed)
        window.show()
    }

    private func showAlert(_ message: String, info: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        NSApp.activate()
        alert.runModal()
    }

    private static func infoString(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
