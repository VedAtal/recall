import AppKit

/// "Update Recall": runs the copy of setup.sh bundled in the app, in its default mode, which
/// downloads the latest Recall from GitHub and installs it. On success, the new build quits this
/// copy and launches itself.
@MainActor
final class Updater {
    private(set) var isUpdating = false
    private var process: Process?

    /// Where updates come from: the HTTPS URL of the repo this copy was built from.
    static var repositoryURL: String? { infoString("RecallRepositoryURL") }

    /// The commit this copy was built from, with a "-dirty" suffix if it had uncommitted changes.
    static var commit: String? { infoString("RecallCommit") }

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

    /// e.g. "Version 59ba24f · built 5 minutes ago".
    static var versionDescription: String? {
        let built = buildDate.map { "built \($0.formatted(.relative(presentation: .named)))" }
        guard let commit else { return built.map { $0.prefix(1).uppercased() + $0.dropFirst() } }
        let version = "Version " + commit.prefix(7) + (commit.hasSuffix("-dirty") ? " (modified)" : "")
        return [version, built].compactMap { $0 }.joined(separator: " · ")
    }

    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Recall/update.log")

    func update() {
        guard !isUpdating else { return }
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
        // The bundled script isn't in a git checkout, so tell it which repo to install from.
        process.environment = ProcessInfo.processInfo.environment.merging(["RECALL_REPO": repositoryURL]) { $1 }
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
            self.process = process
            isUpdating = true
        } catch {
            showAlert("Couldn't start the update", info: error.localizedDescription)
        }
    }

    private func finished(status: Int32) {
        isUpdating = false
        process = nil

        // A successful install quits this copy before the script exits. So if we're still here,
        // either the script found nothing newer (exit 0) or it failed. Either way, this version is
        // still the one running.
        switch status {
        case 0:
            showAlert("Recall is up to date",
                      info: "You're running \(Self.commit.map { String($0.prefix(7)) } ?? "the latest version"), the newest commit on \(Self.repositoryName ?? "GitHub").")
        default:
            let output = (try? String(contentsOf: Self.logURL, encoding: .utf8)) ?? ""
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Update failed. Recall is still on the previous version."
            alert.informativeText = output.split(separator: "\n", omittingEmptySubsequences: false)
                .suffix(15).joined(separator: "\n")
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Open Full Log")
            NSApp.activate()
            if alert.runModal() == .alertSecondButtonReturn {
                NSWorkspace.shared.open(Self.logURL)
            }
        }
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
