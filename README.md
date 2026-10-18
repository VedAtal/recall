# Recall

A small, Flycut-style clipboard history for macOS. Recall saves the text you copy. Hold
**⇧⌘**, tap **V** to go back through your history, and let go to paste.

It runs in the menu bar, uses almost no memory, and keeps everything on your Mac.

## Setup

```sh
~/projects/recall/setup.sh
```

That one command does everything:

1. Checks that Swift is installed. If it isn't, it opens Apple's Command Line Tools installer;
   re-run the command once that finishes. Full Xcode isn't needed.
2. Creates a local code-signing certificate (first run only, see [why](#why-the-signing-certificate)).
3. Builds Recall and installs it to `~/Applications/Recall.app`.
4. Launches it and sets it to start at login.

**One manual step:** the first time Recall runs, macOS asks you to allow it under
**System Settings → Privacy & Security → Accessibility**. Turn it on. Recall needs this to
paste into other apps. Without it, choosing an item only copies it, and you press ⌘V yourself.

### Updating after you change the code

Either click **Update Recall** in the menu bar menu, or run `./setup.sh` again. Both do the
same thing: rebuild, quit the running copy, install the new one, and relaunch. Your history,
settings, and Accessibility permission stay.

- The menu shows **Built …** (for example "Built 2 minutes ago"), so you can tell the new
  version is the one running.
- If the build fails, nothing is replaced. The old version keeps running and shows the error.
  The full output is in `~/Library/Logs/Recall/update.log`.
- If you move the project folder, run `setup.sh` from the new location once, so the menu
  item knows where the project is.

## Using it

| Do this | To |
|---|---|
| **⇧⌘V** (hold ⇧⌘) | Open the history, starting at the most recent item |
| Tap **V** again / **↓** / **↑** | Move through the history while holding ⇧⌘ |
| Let go of **⇧⌘** | Paste the selected item |
| **1–9** | Paste that item right away |
| **↩** or click | Paste the selected item |
| **⌫** | Delete the selected item from the history |
| **esc** or click outside | Close without pasting |

Pasting an older item also moves it back to the top.

While Recall is running, its **clipboard icon** sits in the menu bar at the top right. Click it
to see your 25 most recent items (click one to paste it), plus **Clear History**,
**Launch at Login** (a checkmark you can toggle), **Settings…**, **Update Recall**, and **Quit**.

### Settings

- **Shortcut.** Click the button and type a new combination. It must include ⌘, ⌃ or ⌥.
- **Keep the list open after releasing the shortcut.** For when holding the keys is awkward:
  move with the arrows, then press ↩.
- **History size** (default 50) and whether history is kept after quitting.
- **Paste automatically.** Turn this off if you only want items copied, not pasted.
- **Launch at login.**

## Privacy

- History stays on your Mac, in `~/Library/Application Support/Recall/history.json`. Only
  your user account can read it.
- Items marked as secret or temporary are never recorded. Password managers such as 1Password
  set these markers (see [nspasteboard.org](http://nspasteboard.org)) on what they copy.
- Only plain text is saved. Images and files are skipped.

## Uninstall

```sh
~/projects/recall/setup.sh --uninstall
```

This removes the app, its history and settings, the login item, the Accessibility entry, and
the signing certificate.

## Troubleshooting

**Choosing an item copies it but doesn't paste.** Recall doesn't have Accessibility access.
Open System Settings → Privacy & Security → Accessibility and turn on Recall. If it's already
on and still doesn't work, select Recall, remove it with **−**, then run `./setup.sh` again.
The menu bar menu shows **Grant Accessibility Access…** while access is missing.

**⇧⌘V doesn't open anything.** Another app probably has the same shortcut. Flycut uses ⇧⌘V
too, so quit it, or pick a different shortcut in Settings. If Recall couldn't register the
shortcut, the menu bar menu says so. Note that ⇧⌘V is also "Paste and Match Style" in many apps;
Recall takes it over, just like Flycut does.

**I don't see the menu bar icon.** Check that Recall is running (`pgrep -x Recall`). If it is,
the icon is probably hidden: either behind the camera notch when the menu bar is full, or
because Recall isn't allowed in System Settings → Menu Bar. Quit a few other menu bar apps or
allow Recall there. You can always get to Settings by opening Recall again from Spotlight.

**Paste lands in the wrong place.** Recall pastes into whatever app is in front when you let go.
Keep the target text field focused before you press the shortcut.

## How it works

```
Sources/Recall/
├── main.swift               App entry point (menu-bar-only app, no Dock icon)
├── AppDelegate.swift        Connects the parts below and applies settings changes live
├── ClipboardWatcher.swift   Checks NSPasteboard.changeCount every 0.25s for new text
├── HistoryStore.swift       Newest-first list with no duplicates, saved as JSON
├── HotKey.swift             Global shortcut via Carbon RegisterEventHotKey (no permissions)
├── SwitcherPanel.swift      The ⇧⌘V popup: a non-activating NSPanel with a SwiftUI list
├── Paster.swift             Writes the clipboard and sends a synthetic ⌘V (needs Accessibility)
├── MenuBarController.swift  Menu bar icon and menu
├── SettingsWindow.swift     Settings window and shortcut recorder
├── Updater.swift            "Update Recall": runs setup.sh from the source folder
├── LoginItem.swift          Launch at login (SMAppService)
├── Preferences.swift        Settings stored in UserDefaults
└── Shortcut.swift           Key code and modifier handling for shortcuts
Resources/Info.plist         Bundle metadata (LSUIElement = menu bar only)
scripts/make-icon.swift      Draws the app icon at build time
setup.sh                     Build, sign, install, and uninstall
```

A few details that aren't obvious:

- **macOS has no "clipboard changed" event**, so Recall polls `changeCount`, like every
  clipboard manager does. Checking it is very cheap.
- **The popup never steals focus.** It's an `NSPanel` with `.nonactivatingPanel`, so it gets
  your keystrokes while the app you're pasting into stays frontmost. That way the synthetic
  ⌘V goes to the right place.
- **Letting go of the keys** is detected through `flagsChanged` events, with a backup timer that
  checks `NSEvent.modifierFlags` 30 times a second.

### Why the signing certificate

macOS ties the Accessibility permission to an app's code signature. A normal local build gets
an *ad-hoc* signature, which changes every time you rebuild. macOS then quietly stops honoring
the permission, even though the toggle in System Settings still looks on. To avoid that,
`setup.sh` creates a self-signed certificate once, in its own keychain
(`~/Library/Keychains/recall-codesign.keychain-db`), and signs every build with it. Your login
keychain and system trust settings aren't touched.

### Development

```sh
./setup.sh --build-only   # build and sign build/Recall.app without installing
swift build               # just compile
```

The project builds with only the Command Line Tools. One catch: in the current SDK, SwiftUI's
`@State` is a macro whose plugin only comes with full Xcode, so the code avoids `@State` and
`@StateObject`. View state lives in `ObservableObject` classes instead (see `SettingsWindow.swift`).
