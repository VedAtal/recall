import AppKit

/// Rebuilds and reinstalls Recall from its source folder by running setup.sh, exactly as running
/// it in Terminal would. On success, setup.sh quits this copy and launches the new one.
@MainActor
final class Updater {
    private(set) var isUpdating = false
    private var process: Process?

    /// The project folder. setup.sh writes it into Info.plist at build time.
    static var sourceDirectory: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "RecallSourceDirectory") as? String)
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// When this copy was built (also written by setup.sh).
    static var buildDate: Date? {
        (Bundle.main.object(forInfoDictionaryKey: "RecallBuildDate") as? String)
            .flatMap { try? Date($0, strategy: .iso8601) }
    }

    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Recall/update.log")

    func update() {
        guard !isUpdating else { return }
        guard let directory = Self.sourceDirectory else {
            showAlert("This copy of Recall doesn't know where its source is",
                      info: "Run setup.sh from the project folder once, and Update Recall will work from then on.")
            return
        }
        let script = directory.appendingPathComponent("setup.sh")
        guard FileManager.default.fileExists(atPath: script.path) else {
            showAlert("Can't find setup.sh",
                      info: "Recall was built from \(directory.path), but setup.sh isn't there anymore. If you moved the project, run setup.sh from its new location once.")
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
        process.currentDirectoryURL = directory
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
        // A successful run quits this copy before setup.sh exits, so reaching here means it stopped
        // early, usually a compile error. The old version is still the one running.
        guard status != 0 else { return }

        let output = (try? String(contentsOf: Self.logURL, encoding: .utf8)) ?? ""
        let tail = output.split(separator: "\n", omittingEmptySubsequences: false).suffix(15).joined(separator: "\n")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Update failed. Recall is still on the previous version."
        alert.informativeText = tail
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Full Log")
        NSApp.activate()
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(Self.logURL)
        }
    }

    private func showAlert(_ message: String, info: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        NSApp.activate()
        alert.runModal()
    }
}
