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
| Background helper | Login item app (`mousecloakHelper`, `SMLoginItemSetEnabled`) | Launch agent (`mousecloak --listen` in `~/Library/LaunchAgents`) |
| Updates | Sparkle | None |
| Bundle identifier | `com.alexzielenski.Mousecape` | `io.github.metal-snake.Mousecape` |
| Architectures | Universal (arm64, x86_64) | Apple silicon only |
| Tests | None | Swift Testing (`swift test`) |
| Imports | `.cape`, MightyMouse | Also Windows (`.cur`, `.ani`) and Linux (Xcursor) themes, from folders or archives |

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

**This fork:** the backup is reduced like any long animation, so it succeeds. Reset backs
up before it restores: without backups nothing has been applied in the session yet, so
the cursors on screen are still the system's. (Backing up afterwards, as at first, saved
the stand-in described next instead of the real beach ball.) In a login session whose
backups were made by an older version, reset falls back to the system's busy cursor, an
arrow with a beach ball: close, but not identical.

### Cursors outside the standard set stayed after a reset

Some capes register cursors the original doesn't know, such as
`com.apple.coregraphics.ArrowS` and `IBeamS`.
- **macOS 15:** the system doesn't register them, and they don't change what is shown.
- **macOS 27:** the system registers them itself at login, with the same images as
  `Arrow` and `IBeam`. A registered `ArrowS` shadows `Arrow` completely, even when the
  arrow is read back, and `IBeamS` does the same to `IBeam`. A cape that only replaces
  `Arrow` would therefore not show on macOS 27 at all.

**Original:** they were never backed up or reset. On macOS 27 the arrow of such a cape
stayed on screen after a reset, and after applying another cape.

**This fork:** these variants are backed up when the system has them. On reset they are
handled first, before the standard cursors: they are restored, or given the default
arrow/I-beam from the standard cursor's backup when the system never had them. They can't
take the current Arrow, because on macOS 27 that would read back the variant itself.
On macOS 27 the system's own `ArrowS`/`IBeamS` are backed up at the first apply of a
login session, and a cape without them gives them its `Arrow`/`IBeam`, so such capes
show from the start. Confirmed on macOS 27.0.1: reset brings back the standard arrow and
I-beam. Applying a
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

### Left-handed mode missed cursors

**Original:** the list of pointers that left-handed mode mirrors had a typo: its last
entry, Zoom Out, was an array instead of a name, so Zoom Out was never mirrored.

**This fork:** fixed. Variants such as `ArrowS` count as pointers when their base cursor
does; otherwise left-handed mode would not mirror the arrow on macOS 27, where `ArrowS`
is the arrow people see.

### Left-handed mode only worked with a cape

**Original:** left-handed mode mirrored the cursors of an applied cape. With the macOS
cursors it did nothing.

**This fork:** with no cape applied, left-handed mode mirrors the macOS cursors too:
reset, the Settings switch and the login agent all register mirrored copies of the
system's pointers. Reset in right-handed mode brings back the plain macOS cursors.

### Capes under other file names were lost at login

**Original:** the login agent looks for the applied cape at `<identifier>.cape`. A cape
copied into the library folder under another name could be applied from the app, but not
restored at login.

**This fork:** the library renames such files to `<identifier>.cape` when that name is free.
Files whose identifier is already taken are listed under "Duplicate identifiers" instead of
appearing twice. Saving from the editor writes to `<identifier>.cape` and removes the file
the cape came from if that was a different one.

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
  registered (size, hot spot, frames, pixel sizes) and whether a backup exists, together
  with the macOS version, applied cape, cursor scale, left-handed mode and the window
  server's own cursor names. Meant for bug reports.
- Lives inside the app bundle at `Contents/MacOS/mousecloak` and is also the background
  agent.

## Background agent

- The `mousecloakHelper` login item app is replaced by `mousecloak --listen`, the command
  line tool in agent mode, which re-applies the cape at login, on user switches and on
  display changes.
- It is a plain launch agent: the app writes
  `~/Library/LaunchAgents/io.github.metal-snake.Mousecape.listener.plist` (pointing at
  `mousecloak` in the app bundle) and loads it with `launchctl`. An earlier version of this
  fork registered it through `SMAppService`; for an app without an Apple team ID (ad-hoc or
  self-signed), launchd pinned that registration to the exact build and refused the agent
  after every update ("needs LWCR update"), and re-registering didn't help. A plain agent
  isn't pinned, so updates just work. Old `SMAppService` registrations are moved over at
  launch.
- Turned on and off in **Settings → Apply cape at login** instead of the **Install Helper
  Tool** menu item. If it is switched off under System Settings → Login Items, Settings
  links there. macOS lists it as "mousecloak".
- At launch the app makes sure the plist points at the app's current location. The label
  follows the bundle identifier, so a copy under another identifier (a test build) gets
  an agent of its own instead of taking this one over.
- Runs as a background-only process, so it shows no Dock icon.
- Logs to `~/Library/Logs/Mousecape/agent.log`.

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
- **Cursor names** follow the names macOS gives the cursor resources (HIServices,
  SkyLight). Several of the original's names were misleading: "Camera" is the
  screenshot window cursor, "Link" is Make Alias, "Busy" is Busy but Clickable,
  "IBeam H." is the vertical I-beam, and the window resize cursors are Resize North,
  Resize Southeast and so on. The small coregraphics placeholders macOS keeps next to the real
  cursors are marked "(Legacy)". Identifiers and the cape format are unchanged.
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
- **Resizable sheets.** The editor and the Choose Frames sheet can be resized from
  their edges and corners (SwiftUI sheets can't by themselves), and reopen at the last
  size used.
- **No undo** within the editor. The original had undo.

## Windows cursors

New: Windows cursor themes import as capes.

- **What can be imported:** a theme folder, its `install.inf`, an archive of the theme
  (see [Archives](#archives)), or loose `.cur`/`.ani` files. Use File → Import, drag and
  drop, or Finder's "Open With" for `.cur`/`.ani`.
- **Size folders:** some packs keep each size in a folder of its own (`x1` … `x5`, `32`,
  `48`, `@2x`, …). The largest is taken, and the cape is named after the folder above.
- **Roles:** taken from the registry lines in `install.inf` (or its scheme line); without
  a usable `.inf`, guessed from the file names. Each Windows role fills every matching
  macOS cursor; Vertical Resize, for example, fills all six vertical resize cursors.
  Handwriting, Alternate Select, Location Select and Person Select have no macOS
  counterpart; the import says which roles it left out. A single loose file whose role
  has no counterpart becomes the arrow.
- **Files:** `.cur`/`.ico` images as PNG or as 1, 4, 8, 16, 24 or 32-bit bitmaps with
  transparency mask. Pixels the mask marks as "invert" are drawn black, since macOS
  cursors can't invert. `.ani` animations with their own frame order and per-step
  durations; uneven durations are repeated in units of their common divisor, within the
  frame limit.
- **Size:** Windows shows cursors at 32 × 32 pixels at the default pointer size, whatever
  the file's resolution, so cursors become 32 × 32 points. Images are resampled to 1x and
  2x, and to 5x when the source is large enough. Hot spots are scaled to match.
- **Margins:** themes put every cursor on one canvas (Windows: 32 × 32), often with a lot
  of empty space around it. Imports cut the transparent margin off: to the area any frame
  at any scale draws into, faint shadows included, plus one point, with the hot spot
  always inside. The size then says what's there and the editor shows the artwork filling
  its preview. Applies to Xcursor imports too. Nothing changes on screen: measured with
  `Scripts/cursor-size-probe.swift`, macOS 15.6 draws cursors at their registered size
  and macOS 27.0.1 all of them 1.17 times larger (its default cursor scale), with no
  size limit up to 64 × 64 points.
- **Importing a theme again** asks whether to replace the cape from the earlier import
  (same identifier) or keep both; keeping both adds a number to the name, as every
  theme import did before.
- **Editor:** dropping a `.cur` or `.ani` on a cursor's image well replaces the whole
  cursor (images, size, hot spot, frames).
- Written from the published file formats; no code from other projects.

## Linux cursors (Xcursor)

New: Xcursor themes, the cursor format of X11 and Wayland desktops (GNOME, KDE, Xfce, the
BSDs), import as capes.

- **What can be imported:** a theme folder (`index.theme` plus `cursors/`), its `cursors`
  folder, an archive of the theme (Linux themes usually come as `.tar.xz` or `.tar.gz`),
  or loose Xcursor files. Xcursor files have no extension; they are recognised by their
  contents.
- **Names:** themes name their cursors after CSS (`pointer`, `ew-resize`) or old X11 names
  (`hand2`, `sb_h_double_arrow`), many of them links to the same file. Each macOS cursor
  takes the first name the theme has from a list per cursor. Linux has counterparts for
  more macOS cursors than Windows: closed and open hand, contextual menu, zoom in and out,
  vertical I-beam, cell, each resize direction.
- **Size:** as on Linux (libXcursor), the images whose nominal size is closest to 24, the
  default pointer size there, are shown one pixel per point, unscaled. For most themes
  that's the 24-pixel images, and measured against Apple's own arrow, 24 points match
  macOS. Older themes made only at size 48 (e.g. Obsidian, a normal-sized arrow on a
  48-pixel canvas) become 48 points, as large as on Linux; scaling them down to 24 made
  them half as large. Higher scales use the file's images of a multiple of that size when
  it has them (Xcursor files usually carry 16 to 96 pixels), else larger ones scaled down;
  a theme with only one size gets 1x only.
- **Animation:** frames with their own delays (in milliseconds), handled like `.ani`
  steps. Typical themes have 40 to 60 frames, which the engine reduces to at most 24.
- **Safety:** links that point outside the theme folder are ignored.
- Written from the format description in `man Xcursor`; no code from other projects.

## Archives

Themes are imported straight from archives, unpacked with the system's own tools into a
temporary folder that is removed afterwards: `ditto` for `.zip`, `tar` (libarchive) for
`.7z`, `.rar` and `.tar` with gzip, bzip2 or xz (`.tgz`, `.txz`, …). No third-party code,
no unpacking code of our own. `tar` refuses absolute paths and `..` and won't write through
links. Not supported: `.tar.zst`, since the system's libarchive has no built-in zstd. Inside
the archive, the theme is searched up to five folders deep; the shallowest wins.

## New code

- **`Sources/CapeKit`:** reads and writes `.cape` files, splits sprite sheets into frames,
  holds the editing model and validation, and reads Windows cursors. Pure Swift with no
  private API.
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

## Tested

On macOS 15.6 (Apple silicon) and 27.0.1:
- Applying and resetting capes, from the app and with `mousecloak`, including capes with
  more than 24 frames and with `ArrowS`/`IBeamS`.
- Opening `.cape` files from Finder (the window stays open on macOS 27).

On macOS 15.6:
- The login agent re-applies the cape and cursor size when it starts (as at login) and
  after a display change (simulated by switching the resolution).
- Capture Current Cursors: the capture has no problems and applies.
- The editor: setting the hot spot by click, Choose Frames, saving; resizable sheets.
- Windows cursors: a theme `.zip`, a theme folder and a single `.cur` import; the
  converted animated theme applies.

Not yet: a real logout/login with a cape applied, dropping images into the editor,
MightyMouse import, macOS 26.

## Other projects looked at

- **Mousecape-swiftUI** (sdmj76): source of the macOS 27 cursor-scale idea; its licence
  forbids reusing its code, so nothing was taken.
- **Cursie** (kwd421): its licence matches Mousecape's (non-commercial, keep the notice).
  No code was taken; ideas recorded in TODO.md (cursor name discovery, time-based frame
  reduction, localised file names, agent through `open -b`). Tested its advice to reset
  through System Settings → Accessibility → Pointer → Reset Colors: on macOS 15.6 and
  27.0.1 alike it restores only the arrow and the I-beam (and their `S` variants), so
  Mousecape's own reset stays the way back.
- **macOS27-Cursors** (Juwan-Hwang): a cape of Apple's own macOS 27 cursors, so not
  taken. Its name mapping (docs/MAPPING.md) is where the cursor names above come from.

## Licence

Unchanged. The original licence forbids commercial use, so this fork stays free and
non-commercial and keeps Alex Zielenski's copyright notice in `LICENSE` and `README.md`.
