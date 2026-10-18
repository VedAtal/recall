import AppKit
import ServiceManagement

// `setup.sh --uninstall` runs the binary with this flag so the login item goes away with the app.
if CommandLine.arguments.contains("--unregister-login-item") {
    try? SMAppService.mainApp.unregister()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
