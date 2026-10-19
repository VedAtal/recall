# Recall

A small, Flycut-style clipboard history for macOS. Recall saves the text you copy. Hold
**⇧⌘**, tap **V** to go back through your history, and let go to paste.

It runs in the menu bar, uses almost no memory, and keeps everything on your Mac.

## Setup

```sh
curl -fsSL https://raw.githubusercontent.com/VedAtal/swift-app-kit/main/scripts/install.sh | bash -s recall
```

That one command does everything:

1. Checks that Swift is installed. If it isn't, it opens Apple's Command Line Tools installer;
   re-run the command once that finishes. Full Xcode isn't needed.
2. Downloads the latest version from GitHub ([VedAtal/recall](https://github.com/VedAtal/recall)),
   along with [swift-app-kit](https://github.com/VedAtal/swift-app-kit), the parts it shares with
   my other menu bar apps.
3. Creates a local code-signing certificate (first run only, see [why](#why-the-signing-certificate)).
4. Builds Recall and installs it to `~/Applications/Recall.app`, then deletes the download.
5. Launches it and sets it to start at login.

To work on Recall, clone the repo (`git clone https://github.com/VedAtal/recall.git`). Its
`setup.sh` takes:

| Command | Installs |
|---|---|
| `./setup.sh` | The latest commit on GitHub (the default) |
| `./setup.sh --local` | This folder as it is, including changes you haven't committed or pushed |
| `./setup.sh --build-only` | Nothing. It just builds `build/Recall.app` from this folder |
| `./setup.sh --uninstall` | Nothing. It removes Recall completely ([details](#uninstall)) |

**One manual step:** the first time Recall runs, macOS asks you to allow it under
**System Settings → Privacy & Security → Accessibility**. Turn it on. Recall needs this to
paste into other apps. Without it, choosing an item only copies it, and you press ⌘V yourself.

### Updating

**To the latest on GitHub:** click **Update Recall** in the menu bar menu, or run `./setup.sh` in a clone.
Both work the same way:

- They check GitHub, download anything newer, rebuild, quit the running copy, and launch the
  new one.
- If you're already on the latest commit, they say so and change nothing.
- Your history, settings, and Accessibility permission stay.

**To try local changes before pushing them:** run `./setup.sh --local`. The next
**Update Recall** or plain `./setup.sh` replaces that build with whatever is on GitHub.

- The menu shows which version is running, for example **Version 59ba24f · built 2 minutes ago**.
  "(modified)" after the version means it was built with `--local` from a folder that had
  uncommitted changes.
- From the menu, a window shows progress, including the build output under **Details**. You can
  close it and the update keeps going; click **Updating Recall…** to bring it back. When the new
  version starts, it shows **Recall was updated** with the commit it's running.
- If an update fails, nothing is replaced. The old version keeps running and the window shows
  the error. The full output is in `~/Library/Logs/Recall/update.log`.
- Updates download into `~/Library/Caches/Recall/source`, never into your project folder, so
  they can't touch your work in progress. They download over HTTPS, so they don't need your
  SSH key. If the repo ever becomes private, that download will need GitHub credentials.

## Using it

| Do this | To |
|---|---|
| **⇧⌘V** (hold ⇧⌘) | Open the history, starting at the most recent item |
| Tap **V** again / **↓** / **↑** | Move through the history while holding ⇧⌘ |
| Let go of **⇧⌘** | Paste the selected item |
| **1–9** | Paste that item right away |
| **↩** or click | Paste the selected item |
| **S** | Favorite the selected item (or unfavorite it if it already is one) |
| **F** or **←** / **→** | Switch between the History and Favorites tabs |
| **⌫** | Delete the selected item from the history (in Favorites: unfavorite it) |
| **esc** or click outside | Close without pasting |

Pasting an older item also moves it back to the top. The bar along the bottom of the popup lists
these keys.

### Favorites

Favorites are items you want to keep around for good. Open the popup, select an item, and press
**S**; it gets a gold ★. Press **F** to see all your favorites. The popup gets a gold border while
the Favorites tab is open. Favorites are always saved, aren't limited by the history size, and
**Clear History** doesn't touch them. Pasting a favorite puts it back at the top of History too.

While Recall is running, its **clipboard icon** sits in the menu bar at the top right. Click it
to see your 9 most recent items (click one, or press its number, to paste it), plus **Clear History**,
**Launch at Login** (a checkmark you can toggle), **Settings…**, **Update Recall**, and **Quit**.

### Settings

- **Shortcut.** Click the button and type a new combination. It must include ⌘, ⌃ or ⌥.
- **Keep the list open after releasing the shortcut.** For when holding the keys is awkward:
  move with the arrows, then press ↩.
- **History size** (default 50) and whether history is kept after quitting.
- **Paste automatically.** Turn this off if you only want items copied, not pasted.
- **Launch at login.**

## Privacy

- History and favorites stay on your Mac, in `history.json` and `favorites.json` under
  `~/Library/Application Support/Recall/`. Only your user account can read them. Favorites are
  saved even when "Keep history after quitting" is off.
- Items marked as secret or temporary are never recorded. Password managers such as 1Password
  set these markers (see [nspasteboard.org](http://nspasteboard.org)) on what they copy.
- Only plain text is saved. Images and files are skipped.

## Uninstall

```sh
~/Applications/Recall.app/Contents/Resources/setup.sh --uninstall
```

This removes the app, its history and settings, the login item, the Accessibility entry, and
the signing certificate.

## Troubleshooting

**Choosing an item copies it but doesn't paste.** Recall doesn't have Accessibility access.
Open System Settings → Privacy & Security → Accessibility and turn on Recall. If it's already
on and still doesn't work, select Recall and remove it with **−**. Then quit Recall from its menu
and open it again (Spotlight → Recall); macOS will ask for access again.
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

Recall is built on [swift-app-kit](https://github.com/VedAtal/swift-app-kit), which provides
the parts my menu bar apps share: the install script, the menu bar menu's standard items,
the Settings window layout, the shortcut recorder, launch at login, and updates. This repo
holds only what's specific to Recall:

```
Sources/Recall/
├── main.swift               Starts the app through swift-app-kit
├── AppDelegate.swift        Connects the parts below, adds Recall's menu items, applies settings live
├── ClipboardWatcher.swift   Checks NSPasteboard.changeCount every 0.25s for new text
├── HistoryStore.swift       Newest-first list with no duplicates, saved as JSON
├── SwitcherPanel.swift      The ⇧⌘V popup: a non-activating NSPanel with a SwiftUI list
├── Paster.swift             Writes the clipboard and sends a synthetic ⌘V (needs Accessibility)
├── SettingsWindow.swift     Recall's sections of the Settings window
└── Preferences.swift        Settings stored in UserDefaults
app.env                      Name, bundle ID, icons: what swift-app-kit's setup builds
setup.sh                     Fetches swift-app-kit and runs its install script
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
swift-app-kit's setup creates a self-signed certificate once, in its own keychain
(`~/Library/Keychains/recall-codesign.keychain-db`), and signs every build with it. Your login
keychain and system trust settings aren't touched.

### Development

```sh
./setup.sh --local        # build and install what is in this folder right now
./setup.sh --build-only   # build and sign build/Recall.app without installing
swift build               # just compile
```

To change the shared parts (menu, Settings layout, install script), edit
[swift-app-kit](https://github.com/VedAtal/swift-app-kit) and build Recall against your local
copy with `swift package edit swift-app-kit --path ../swift-app-kit`. The kit's README explains
the rest of the workflow.

The project builds with only the Command Line Tools. One catch: in the current SDK, SwiftUI's
`@State` is a macro whose plugin only comes with full Xcode, so the code avoids `@State` and
`@StateObject`. View state lives in `ObservableObject` classes instead.
