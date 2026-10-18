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

## Bugs in the original

Problems in the original's engine and app, what the user saw, and what this fork does about
them. Found by reading the original code and by testing on macOS 15.6 and 27.0.1.

### Animations with more than 24 frames

The window server refuses cursors with more than 24 frames: registering 25 or more fails
with `kCGErrorFailure`. The limit is the same for every cursor name (standard, variant,
core or made-up), size, pixel density and registration flag tested on macOS 15.6. macOS registers its own cursors another way, so its Wait cursor
(the beach ball) has 30 frames, and so do capes made from it.

**Original:** a cursor over 24 frames was rejected with a line in the log, and the
whole apply stopped at that point ("Bailing out"). Cursors handled before it stayed
replaced, the rest did not, and the order was random. The app showed no message and
didn't mark the cape as applied; the login helper failed the same way at every login.
The editor only limited typing in the frames field (1–24): a cape with 30 frames
opened and saved unchanged, and dropping several images set the frame count unchecked.

**This fork:**
- The engine keeps every n-th frame and shows each one n times as long, so the cape
  applies and the animation keeps its speed (30 frames at 1/60 s become 15 at 1/30 s).
  The cape file is not changed.
- The editor's frame stepper stops at 24. A cursor over the limit shows its frame count
  with a **Reduce to N** button, which rewrites its images the same way, for good, and
  **Choose…**, which lets you pick the frames yourself (see the cape editor below).
- The library marks such capes with an orange badge, and the cape view explains what
  happens when they are applied.

### One bad cursor aborted the whole cape

**Original:** whatever made a cursor fail (frame count, an unreadable image), the apply
stopped there, leaving a mix of the old and the new cape on screen.

**This fork:** a failing cursor is skipped and the rest is applied. Registration errors
are logged with their error code. The app says that some
cursors were rejected. If none applies, the cursors are reset to the macOS defaults.

### Reset could not bring back the Wait cursor

**Original:** before the first apply, the engine backs up the system cursors by
registering copies of them. The system's Wait cursor has 30 frames, so its copy failed,
and the failure was ignored. Reset then had nothing to restore it from: the Wait cursor
of the last cape stayed until logout.

**This fork:** the backup is reduced like any long animation, so it succeeds. In a login
session whose backups were made by an older version, reset falls back to the system's
busy cursor (an arrow with a beach ball, so close but not identical; see TODO.md).

### Cursors outside the standard set stayed after a reset

Some capes register cursors the original doesn't know, such as
`com.apple.coregraphics.ArrowS` and `IBeamS`. On macOS 15 they don't change what is shown.
On macOS 27 a registered `ArrowS` shadows `Arrow` completely, even when the arrow is read
back, and `IBeamS` does the same to `IBeam`.

**Original:** they were never backed up or reset. On macOS 27 the arrow of such a cape
stayed on screen after a reset, and after applying another cape.

**This fork:** these variants are backed up when the system has them. On reset they are
handled first, before the standard cursors: they are restored, or given the default
arrow/I-beam from the standard cursor's backup when the system never had them. They can't
take the current Arrow, because on macOS 27 that would read back the variant itself. Applying a
cape without them gives leftover variants the cape's own arrow/I-beam. Any other cursor
outside the standard set is remembered when applied (`MCAppliedExtraCursors`) and
handled the same way.

### Cleanup that never worked

**Original:** after restoring, the engine tried to unregister its backups and other
cursors. The window server only lets the process that registered a cursor remove it,
and that is always an earlier process, so every one of these calls failed silently.
Backups therefore live for the whole login session, and the first backup in a session
is the one that counts.

**This fork:** nothing relies on unregistering; cursors are overwritten instead. The
session-long backups are documented in TODO.md.

### Reset claimed success when nothing changed

**Original:** reset never checked its own work. Failed restores were ignored, the cape
was marked as no longer applied, and the app looked as if the cursors were back to
normal.

**This fork:** every restored cursor is compared with its backup (point size, frame
count, pixel sizes). Reset reports the cursors it could not put back; the app shows an
error, and `mousecloak --reset` exits non-zero.

### Captured cursors could not be applied

**Original:** **Capture Current Cursors** copies the system's Wait cursor with its 30
frames into the new cape, so the original couldn't apply its own capture.

**This fork:** such captures apply, with the Wait animation reduced.

### Cursor size forced to 1x at login

**Original:** with no size saved in Mousecape, the helper set the cursor scale to 1x at
every login, overriding the pointer size from System Settings → Accessibility.

**This fork:** a size is restored only when one was saved in Mousecape. Otherwise the
current size stays. On display changes the agent restores the preferred size instead of
re-reading the current one, because macOS 27 resets the scale to 1x there. The idea comes
from the Mousecape-swiftUI fork; the implementation is our own, because that fork's licence
doesn't allow its code to be reused.

## Cursor engine (`Sources/MousecloakCore`)

The Objective-C sources of `mousecloak` moved unchanged in substance (history kept with
`git mv`). Only the build setup differs:

- The prefix header (`mousecloak-Prefix.pch`) is replaced by explicit imports in each file.
  `MCDefs.h` now imports Cocoa and the CGS declarations itself.
- An umbrella header and module map make the engine callable from Swift.
- Of the vendored `CGSInternal` headers, only the three in use are kept
  (`CGSCursor.h`, `CGSConnection.h`, `CGSAccessibility.h`).
- Behaviour fixes are described under [Bugs in the original](#bugs-in-the-original).
- Still compiled with manual retain/release (`-fno-objc-arc`), as before.
- Deprecation warnings are silenced for this target (see TODO.md).

## Command line tool (`Sources/mousecloak`)

- Rewritten in Swift. The GBCli library is no longer needed.
- Same options: `--apply`, `--reset`, `--create`, `--convert`, `--dump`, `--export`,
  `--output`, `--scale`, `--listen`, `--help`. `--suppressCopyright` is still accepted
  and ignored.
- Exits with a non-zero status when a command fails. The original always exited 0.
- Errors go to stderr. The coloured copyright banner is gone.
- New `--list`: shows, for every standard and extra cursor, what the window server has
  registered (size, frames, pixel sizes) and whether a backup exists, together with the
  macOS version, applied cape and cursor scale. Meant for bug reports.
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
- Ad-hoc signing pins the agent to the exact build, app bundle included. When the build
  has changed, the app registers the agent again at launch; otherwise launchd would refuse
  to start it.

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
- **Problem marks.** Capes with cursors that won't apply cleanly get a badge in the
  sidebar: red when a cursor won't apply or will look wrong, orange when macOS only
  adjusts it (e.g. a reduced animation). The cape view lists what happens per cursor.
- **Smoother previews.** Cursor images are decoded off the main thread and cached. Each
  cape gets fresh tiles, so switching capes never shows the previous cape's images.
  Coming back to the app reads the library again only if the folder changed.
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
  and frame duration. A cursor over 24 frames can be reduced with one click (see
  [Bugs in the original](#animations-with-more-than-24-frames)).
- **Choose Frames** (**Choose…** next to the frame count, for any animated cursor): a
  filmstrip of all frames to keep or drop. Presets are every n-th frame, n spread evenly,
  the first n, or a custom pick. The original and the result play side by side. The frame
  duration follows the selection so one loop keeps its length, and can be adjusted. A
  note appears when the kept frames are unevenly spaced, because with one duration for
  all frames steady motion may then stutter.
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
