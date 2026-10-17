# Changes from the original

What this fork changes compared to [alexzielenski/Mousecape](https://github.com/alexzielenski/Mousecape)
at commit `184f87b` ("bump version, copyright", July 2024), the last upstream commit.

## Summary

The cursor engine is the original. Everything around it is new: the app is rebuilt in
SwiftUI, the project builds with Swift Package Manager instead of Xcode, and the
bundled third-party libraries are gone.

| | Original | This fork |
|---|---|---|
| Minimum macOS | 10.13 | 14 Sonoma |
| App | Objective-C, XIB, AppKit | SwiftUI |
| Build | Xcode project | SwiftPM + `Scripts/build-app.sh`, Command Line Tools only |
| Background helper | Login item app (`mousecloakHelper`, `SMLoginItemSetEnabled`) | Launch agent (`mousecloak --listen`, `SMAppService`) |
| Updates | Sparkle | None |
| Bundle identifier | `com.alexzielenski.Mousecape` | `io.github.metal-snake.Mousecape` |
| Architectures | Universal (arm64, x86_64) | Apple silicon only |
| Tests | None | Swift Testing (`swift test`) |

## What stays compatible

- **Cape format.** `.cape` files are read and written in the same format (version 2.0),
  under the same type identifier `com.alexzielenski.mousecape.cape`.
- **Library.** `~/Library/Application Support/Mousecape/capes`, the same folder.
- **Preferences.** The engine and the app keep using the `com.alexzielenski.Mousecape`
  preferences domain (applied cape, cursor scale, left-handed mode), so an existing setup
  carries over.
- **Engine behaviour.** Applying, backing up and restoring cursors, cursor scale,
  left-handed mirroring, MightyMouse conversion and cursor dumps run the original code.
- **Command line options.** `mousecloak` accepts the same options as before.

## Cursor engine (`Sources/MousecloakCore`)

The Objective-C sources of `mousecloak` moved unchanged in substance (history kept with
`git mv`). Only the build setup differs:

- The prefix header (`mousecloak-Prefix.pch`) is replaced by explicit imports in each file.
  `MCDefs.h` now imports Cocoa and the CGS declarations itself.
- An umbrella header and module map make the engine callable from Swift.
- Of the vendored `CGSInternal` headers, only the three in use are kept
  (`CGSCursor.h`, `CGSConnection.h`, `CGSAccessibility.h`).
- **Cursor scale.** The engine used to force 1x at every login when no size was saved in
  Mousecape, overriding the Accessibility pointer size. It now restores a size only when
  one was saved, and otherwise keeps the current one.
- **Display changes.** On a display change, the agent now restores the preferred size
  instead of re-reading the current one: on the macOS 27 beta, display changes reset the
  scale to 1x. The idea comes from the Mousecape-swiftUI fork; the implementation is our
  own, because that fork's licence does not allow its code to be reused.
- Still compiled with manual retain/release (`-fno-objc-arc`), as before.
- Deprecation warnings are silenced for this target (see TODO.md).

## Command line tool (`Sources/mousecloak`)

- Rewritten in Swift. The GBCli library is no longer needed.
- Same options: `--apply`, `--reset`, `--create`, `--convert`, `--dump`, `--export`,
  `--output`, `--scale`, `--listen`, `--help`. `--suppressCopyright` is still accepted
  and ignored.
- Exits with a non-zero status when a command fails. The original always exited 0.
- Errors go to stderr. The coloured copyright banner is gone.
- Lives inside the app bundle at `Contents/MacOS/mousecloak` and is also the background
  agent.

## Background agent

- The `mousecloakHelper` login item app is replaced by a launch agent that runs
  `mousecloak --listen`. Its label is `io.github.metal-snake.Mousecape.agent` and its
  plist is in `Contents/Library/LaunchAgents`.
- Registered through `SMAppService` (macOS 13+) instead of the deprecated
  `SMLoginItemSetEnabled`.
- Turned on and off in **Settings → Apply cape at login** instead of the
  **Install Helper Tool** menu item. When macOS asks for approval, Settings links to
  System Settings → Login Items, where it appears under "Allow in the Background".
- Runs as a background-only process, so it shows no Dock icon.
- Ad-hoc signing pins the agent to the exact build. When the agent binary has changed, the
  app registers it again at launch; otherwise launchd would refuse to start it.

## App (`Sources/Mousecape`)

New SwiftUI app. Compared with the original:

- **Library window.** Sidebar of capes with the applied one marked. The detail view
  animates every cursor at twice its size, with an optional hot spot overlay.
- **Importing.** Use File → Import (⌘O), double-click in Finder, or drag files onto the
  window. `.MightyMouse` files are converted on import, as before.
- **Identifier clashes on import.** The app now asks whether to replace the existing cape.
  The original silently appended a UUID to the identifier.
- **Deleting** uses the system Trash API (`FileManager.trashItem`). The original moved the
  file to `~/.Trash` by hand. There is no undo for deleting yet.
- **Capture Current Cursors** (the original's dump) imports the cursors on screen as a new
  cape.
- **Settings** cover the login agent, the cursor size (slider from 1 to 4) and left-handed
  mode. The slider shows the current system size until a size is saved. Changing
  left-handed mode re-applies the current cape right away.
- **No re-apply at launch.** The original re-applied the current cape every time the app
  launched. The new app leaves that to the agent.
- **Not ported:** the library click and double-click action preferences
  (`MCLibraryClickAction`, `MCDoubleAction`).

## Cape editor

Rebuilt from scratch. It works on a draft and saves explicitly:

- **New, edit, duplicate:** ⌘N, ⌘E, ⌘D.
- **Cape details:** name, author, version, HiDPI and identifier. Changing the identifier
  renames the file, and an applied cape is re-applied after saving.
- **Cursors:** add any system cursor the cape doesn't replace yet, or remove one.
- **Per cursor:** size, hot spot (also set by clicking the preview), frame count (1–24)
  and frame duration.
- **Images:** one well per scale (1x, 2x, 5x, 10x), filled by drag and drop or by
  choosing a file. Images are stored as sRGB PNG. The first image sets the cursor size,
  and later images must match it exactly.
- **Validation:** cursors that would not apply, or would look wrong, are flagged.
- **No undo** within the editor. The original had undo.

## New code

- **`Sources/CapeKit`:** reads and writes `.cape` files, splits sprite sheets into frames,
  and holds the editing model and validation. Pure Swift with no private API.
- **Tests:** `Tests/CapeKitTests` cover the cape format, frames, scales and validation.
  `Tests/MousecapeTests` cover saving, renaming and duplicating in a throwaway library.
- **`MOUSECAPE_LIBRARY`:** this environment variable points the app at another library
  folder, for testing.

## Removed

- The Xcode project, the Objective-C/XIB app and the `mousecloakHelper` target.
- The vendored libraries: Sparkle (submodule) and its `appcast.xml`, Rebel, BTRKit,
  MASPreferences, DTScrollView and GBCli.
- `screenshot.png`, which showed the old interface.

## Moved

- `Mousecape/com.maxrudberg.svanslosbluehazard.cape` → `Examples/`.
- The app icon from the asset catalog to `Resources/AppIcon.iconset`. The artwork is
  unchanged.

## Licence

Unchanged. The original licence forbids commercial use, so this fork stays free and
non-commercial and keeps Alex Zielenski's copyright notice in `LICENSE` and `README.md`.
