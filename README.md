# Corners

A tiny macOS menu bar app that moves the frontmost window with global keyboard shortcuts.
Press `⌃⌘←`, and the window fills the left half of its screen. Press `⌃⌘=`, and it grows
by 10% of the screen without leaving the edge it's against. Shortcuts live in a TOML
file that Corners watches and hot-reloads, so you can edit them in the built-in Configure
window or in your editor of choice.

- Native SwiftUI, macOS 26 (Tahoe) and later
- Menu bar only, no Dock icon
- Needs Accessibility permission to move other apps' windows; not sandboxed (see below)
- One dependency: [TOMLKit](https://github.com/LebJe/TOMLKit)

`main` is always the latest release.

## Quick start

Requirements: Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/octoth0rpe/corners.git
cd corners
make cert       # once: create a local signing certificate (see below)
make install    # build Release, replace ~/Applications/Corners.app, relaunch
```

On first launch macOS asks for Accessibility permission. Turn Corners on in
**System Settings → Privacy & Security → Accessibility**. The Configure window shows a
banner until it's granted.

| Target          | What it does                                                               |
|-----------------|----------------------------------------------------------------------------|
| `make`          | Same as `make build`                                                       |
| `make build`    | Debug build into `build/`                                                  |
| `make install`  | Release build; quit Corners, replace `~/Applications/Corners.app`, relaunch |
| `make run`      | Debug build; quit Corners, launch it from `build/`                         |
| `make release`  | Release build into `build/`                                                |
| `make test`     | Run the unit tests (Grow/Shrink math, key names)                           |
| `make cert`     | Create the "Corners Local Signing" certificate in the login keychain       |
| `make project`  | Regenerate `Corners.xcodeproj` from `project.yml`                          |
| `make clean`    | Remove `build/` and the generated project                                  |

The Makefile points `DEVELOPER_DIR` at `/Applications/Xcode.app`, so it works even if
`xcode-select` still points at the Command Line Tools.

### Why `make cert`

macOS remembers the Accessibility grant by the app's code signature. Builds are ad-hoc
signed so they work without a developer account, but an ad-hoc signature is the hash of
the binary, so every build looks like a new app and the grant stops working. `make cert`
creates a self-signed certificate once, and `make install` re-signs the installed copy
with it. The designated requirement then becomes "bundle ID `com.octoth0rpe.corners`, signed
by this certificate", which stays the same from build to build.

The certificate shows as "not trusted" in `security find-identity`. That's fine:
codesign and TCC only need it to stay the same. To remove it, delete
"Corners Local Signing" from the login keychain in Keychain Access.

`make run` builds aren't re-signed, so they'd need their own grant. Use `make install`
for anything that moves windows.

## Configuration

```
~/Library/Application Support/Corners/config.toml
```

**Configure Shortcuts… → Show Config File** reveals it in Finder. It's created on first
launch with the default shortcuts, and **Restore Defaults…** puts them back.

```toml
# Left Half
[[shortcut]]
keys  = "ctrl+cmd+left"
frame = { x = 0, y = 0, width = 50, height = 100 }

# Center Half
[[shortcut]]
keys  = "ctrl+opt+shift+cmd+2"
frame = { x = 25, y = 0, width = 50, height = 100 }

# Grow 10%
[[shortcut]]
keys   = "ctrl+cmd+="
resize = "grow"
```

- **`keys`**: modifiers and one key joined with `+`.
  - Modifiers: `cmd`, `shift`, `opt`, `ctrl`. The aliases `command`, `option`, `alt`,
    `control` and the symbols `⌘⇧⌥⌃` also work.
  - Key: a single character (`a`, `1`, `'`, `/`) or a name: `space`, `return`, `tab`,
    `escape`, `delete`, `forwarddelete`, `up`, `down`, `left`, `right`, `home`, `end`,
    `pageup`, `pagedown`, `f1`–`f20`.
  - Characters are matched against your current keyboard layout, and characters typed
    with Shift become Shift plus the base key (`cmd+|` means `cmd+shift+\` on a US layout).
- **`frame`**: where the window goes, in percent of the usable area of the screen it's on.
  That's the screen minus the menu bar and Dock. `x` and `y` are measured from the
  top-left corner. `x + width` and `y + height` can be at most 100. Fractions work:
  `width = 33.333` is a third.
- **`resize`**: instead of a `frame`, `"grow"` or `"shrink"`. Each press changes the window
  by 10% of the screen on each axis. See [Grow and Shrink](#grow-and-shrink).

### Defaults

| Shortcut  | Position                                |
|-----------|-----------------------------------------|
| `⌃⌘←`     | Left half                               |
| `⌃⌘→`     | Right half                              |
| `⌃⌘↑`     | Top half                                |
| `⌃⌘↓`     | Bottom half                             |
| `⌃⌥⇧⌘1`   | Left quarter, full height               |
| `⌃⌥⇧⌘2`   | Center half (25%–75%), full height      |
| `⌃⌥⇧⌘3`   | Right quarter, full height              |
| `⌘↩`      | Maximize                                |
| `⌃⌘=`     | Grow 10%                                |
| `⌃⌘-`     | Shrink 10%                              |

`⌘↩` is "send" or "run" in many apps. Corners registers it globally, so those apps
won't see it. Change it if that gets in the way.

### Grow and Shrink

Each press grows or shrinks the window by 10% of the screen's width and height. Edges
flush with the screen stay where they are (within 20 points, so a terminal that stopped
a line short still counts):

- A left half grows to the right: 50% → 60% → 70% of the width. A right half grows to
  the left. A corner window grows out of its corner.
- A window touching no edge grows or shrinks evenly around its center.
- Growing stops at the screen edges. Windows don't shrink below 10% of the screen.
- An axis the window fills completely doesn't shrink, so a left half only gets
  narrower. The exception is a maximized window, which shrinks evenly to 90% × 90%.
  Grow undoes each step exactly.

The last rule was a judgment call among four options. They're listed at the top of
`Corners/Resize.swift`, along with how to switch. `make test` covers the chosen
behavior, so after switching, the failing tests show exactly what changed.

### The Configure window

Each row has modifier toggles, a key button, and an action. Click the key button and press
a key to record it. Hold modifiers while you press it to set the toggles too (`⌃⌘←`
records `←` with ⌃ and ⌘); a bare key leaves the toggles alone. Esc cancels. Corners'
own shortcuts are paused while recording, so you can record combos it already uses.
Keypad keys and Escape can't be recorded.

The action pop-up lists presets (halves, quarters, thirds, corners, maximize) and
Grow/Shrink. Choose **Custom…** or click the
screen thumbnail to draw any rectangle (snapped to 5%) or type exact percentages.

A ⚠️ on a row means its shortcut may not work. Hover for the reason:
- **Same keys as a row above.** macOS registers a combo once per app, so the first
  row wins and this one is off.
- **macOS also uses these keys** (System Settings → Keyboard → Keyboard Shortcuts:
  Mission Control, Spaces, screenshots…). macOS's shortcut usually wins. The row stays
  registered, so it starts working if you turn the macOS one off. This check can't see
  every system shortcut (Spotlight's `⌘Space` isn't listed) or other apps' shortcuts:
  macOS doesn't report those, and registering a taken combo doesn't fail.
- **macOS refused these keys.** Rare, for the same reason.

Edits from either side show up on the other. Edits in the Configure window rewrite the
file, which replaces comments and formatting you added by hand. If the file has a
problem, Corners keeps the last working shortcuts and shows the error in the Configure
window.

## Architecture

```
Corners/
├── CornersApp.swift     App entry: MenuBarExtra + About and Configure windows
├── ConfigStore.swift    Source of truth: load, save, reload, keep hotkeys in sync
├── ConfigFile.swift     TOML parse (TOMLKit) and render (hand-written for readability)
├── Shortcut.swift       Shortcut, Action and Modifier models, "cmd+shift+k" parsing, defaults
├── Placement.swift      Placement (percent rectangle) and the presets
├── Resize.swift         Grow/Shrink: anchoring math, no Accessibility code
├── WindowMover.swift    Moves the frontmost window via the Accessibility API
├── HotKeyManager.swift  Global hotkeys via Carbon RegisterEventHotKey
├── KeyCodes.swift       Key name → virtual key code, layout-aware via UCKeyTranslate
├── FileWatcher.swift    kqueue (DispatchSource) watcher for config.toml
├── ConfigureView.swift  Shortcut editor, position picker, permission banner
├── AboutView.swift
└── Assets.xcassets      App icon PNGs and the menu bar template SVG
CornersTests/            Unit tests for Resize and KeyCodes (make test). They compile
                         those files directly, so running them doesn't launch Corners.
```

`KeyCodes`, `FileWatcher`, `HotKeyManager` and the config round trip come from
Summon and work the same way.

### Design decisions

- **Carbon hotkeys, plus Accessibility for moving.** Hotkeys still use
  `RegisterEventHotKey`, which needs no permission. Moving another app's window needs
  the Accessibility API (`AXUIElement`), and that needs the user's permission.
- **No App Sandbox.** A sandboxed app can be granted Accessibility permission, and
  `AXIsProcessTrusted()` returns true, but every call to another app still fails with
  `kAXErrorCannotComplete` (-25204). So Corners isn't sandboxed, which rules out the Mac
  App Store as it stands. Distribution would be a notarized direct download. (Some App
  Store window managers exist; how they get around this hasn't been looked into.)
- **Percentages of the visible frame.** Every position is a rectangle in percent of
  `NSScreen.visibleFrame`, so the same shortcut works on any screen size and never
  slides under the Dock. Presets are just named rectangles. The file stores numbers,
  and the UI shows the preset name when the numbers match one.
- **Edges are rounded, not sizes.** Each edge is rounded to whole points on its own,
  so a left half and a right half always meet with no gap or overlap.
- **The window stays on its screen.** The target screen is the one showing most of the
  window.
- **Resizes realign.** If an app won't take the exact size (a minimum size, or a
  terminal's character cells), the window is moved again so its anchored edge is still
  flush.
- **Size, move, size.** Apps can refuse a size that doesn't fit at the window's current
  position, so the size is set again once the window has moved. While moving,
  `AXEnhancedUserInterface` is switched off, because Chrome and Electron apps animate
  (and drop) frame changes while it's on.

## Debugging

Failures (no focused window, a full-screen window, an unreadable frame) are logged at
notice level. Every move is logged at debug level with the before, target and after
frames and each Accessibility call's result:

```sh
log stream --level debug --predicate 'subsystem == "com.octoth0rpe.corners"'
```

## Ideas / not yet done

- Move the window to the next screen
- A `.icon` from Icon Composer for dark, tinted and Liquid Glass variants

## License

MIT. See [LICENSE](LICENSE).
