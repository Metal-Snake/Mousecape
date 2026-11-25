# Notes on macOS

What this fork learnt about how macOS handles cursors. Mousecape relies on private
CGS/CoreCursor calls, so any of this can change with the next macOS version. Unless a
version is named, it was measured on macOS 15.6 and 27.0.1 on Apple silicon. How to
repeat the checks is in [TESTING.md](TESTING.md).

## Frame limit

`CGSRegisterCursorWithImages` refuses cursors with more than 24 frames: registering 25 or
more fails with `kCGErrorFailure`. On macOS 15.6 the limit is the same for every cursor
name (standard, variant, core or made-up), size, pixel density and registration flag
tried. macOS registers its own cursors another way, so its Wait cursor (the beach ball)
has 30 frames.

The limit sits in SkyLight's client-side wrapper, not in the window server (measured on
macOS 15.8.3, 24H241, with `Scripts/frame-limit-probe.m`). `SLSRegisterCursorWithImages`
accepts 1 to 24 frames and at most 64 images, turns the images into pixel buffers and
passes them to the internal, unexported `_CGSRegisterCursorImages`, which sends them to
the window server. Called directly, that function registers 25, 48 and 100 frames, and
`CGSCopyRegisteredCursorImages` returns them all. The server side
(`_CGXRegisterCursorImages`, `CGXCursorCreate`, CoreDisplay's `CursorBitmapCreate`)
checks only that the pixel data fits. The window server also plays them: an arrow with 48
numbered frames, registered this way as `Arrow`, `ArrowS` and `com.apple.cursor.0`,
counted 1 to 48 without gaps at 0.25 s each (`frame-limit-probe --play`).

macOS 27.2.1 (26B131) behaves the same. There the wrapper is
`SLSRegisterCursorWithImages2` (as CX330-YCH's fork of Mousecape-swiftUI found on macOS
26); `CGSRegisterCursorWithImages` still refuses 25 frames or more, the same
`_CGSRegisterCursorImages`, called the same way, registers 100, and an arrow with 48
frames plays them all. The internal call isn't exported, but `dladdr` names it, so a
program can find it among the calls the exported wrapper makes. Its address and the
wrapper's code change with each macOS build.

The engine uses this (`longanim.m`): it finds the call by name, checks it once per
process with a test registration of 25 frames on its own connection, and then registers
animations of up to 256 frames, and at most 2^24 pixels per cursor, through it. When the
call isn't found, the test fails, or a registration fails, it reduces to 24 frames and
uses the public call. `MOUSECAPE_SHORT_ANIMATIONS=1` turns the long path off for testing.

A registered cursor has one frame duration for all its frames. Animations whose frames
last differently long can only keep their timing by repeating frames.

## Registrations last for the session

`CGSRemoveRegisteredCursor` takes a flag. With `false`, only the process that registered
a cursor can remove it; every other process fails silently, though the call reports
success. With `true`, any process can remove it, whether the process that registered it
still runs or not (measured on macOS 15.6, 15.8.3 and 27.2.1, with cursors registered with
the global flag, as the engine does). The global remove was found by the SnowGlow-aww fork
of the original.

Names under `com.apple.coregraphics.` are the exception: they can't be removed at all,
not even by the process that registered them, with either flag (error 1000; measured on
macOS 15.8.3, also for made-up names in that namespace). So a variant like `ArrowS`, once a
cape registered it, stays until logout; a reset can only give it the default images.

This shapes how reset works. The engine registers its backups as
`com.alexzielenski.mousecape.<identifier>`, the same names the original Mousecape uses,
and backs up only when no backup exists yet. A reset removes each backup it restored, with
the global flag, so the next apply backs up what is on screen after the reset. A backup
that could not be restored stays, so a cape's cursor is never backed up as the system's.

The engine can't tell whether the cursors on screen are macOS's own when it backs them
up: if another tool (the original Mousecape, Cursie, …) changed them before, reset brings
back that tool's cursors. Logging out and in again starts over.

## ArrowS and IBeamS

`com.apple.coregraphics.ArrowS` and `IBeamS` are variants of `Arrow` and `IBeam`.

- **macOS 15.6:** the system doesn't register them. When a cape registers `ArrowS`, apps
  still get `Arrow`.
- **macOS 27.0.1:** the system registers both itself at login, with the same images as
  `Arrow` and `IBeam`. A registered `ArrowS` shadows `Arrow` completely, even when the
  arrow is read back, and `IBeamS` does the same to `IBeam`.

## System cursor names

`CGSCursorNameForSystemCursor(i)` returns the window server's names for its own cursors
(`mousecloak --list` prints them). On macOS 15.6 these are the 9 standard cursors. On
macOS 27.0.1 they are the same plus `ArrowS` and `IBeamS`. Other names that Cursie lists
(`CopyDrag`, `ResizeUp`, …) don't exist on either version.

## Cursor names

The names Mousecape shows follow the names macOS gives the cursor resources in HIServices
and SkyLight. The mapping comes from macOS27-Cursors (`docs/MAPPING.md`). Next to the real
cursors, macOS keeps small coregraphics placeholders, which Mousecape marks "(Legacy)".

There are two sets of system cursors. The named ones (`com.apple.coregraphics.Arrow`,
`…IBeam`, `…Wait`, …) are registered by the window server under their names. The core
cursors (`com.apple.cursor.0` to `…43`) are numbered; apps ask for them by number, and
macOS draws them from the PDFs in HIServices' `cursors` folder. A cape replaces core
cursor N by registering an image as `com.apple.cursor.N`; a reset brings all of them back
at once (`CoreCursorUnregisterAll`). Core cursors 0 and 1 are the arrow and the I-beam,
with no PDF of their own. Whether any app asks for them by number is unknown; MaCursor
registers its arrow and I-beam under those numbers too, and Mousecape does the same.

## Cursor size

Measured with `Scripts/cursor-size-probe.swift`: macOS draws a cursor at its registered
size in points times the cursor scale. There is no size limit up to 64 × 64 points, the
largest size tried.

- The cursor scale is the same setting as System Settings → Accessibility → Display →
  Pointer size.
- On display changes, macOS 27 resets the scale to 1x.
- For comparison: Windows draws cursors at 32 × 32 pixels at the default pointer size,
  whatever the file's resolution. Linux (libXcursor) defaults to size 24, and 24 points
  match Apple's own arrow.

## Which image macOS shows

A cursor registers one image per pixel density. macOS 27.0.1 accepts any density, not
only the 1x, 2x, 5x and 10x of the cape editor, and shows the smallest image that is at
least as dense as the screen needs: the display's backing scale times the cursor scale.
Measured with a test arrow that has a different colour at 1x, 2x, 3x, 4x, 5x and 10x, on a
5K Studio Display and a 4K monitor in a scaled mode (both 2x backing):

| Cursor scale | 1 | 1.25 | 1.5 | 1.75 | 2 | 2.5 | 3 | 4 |
|---|---|---|---|---|---|---|---|---|
| Needed density | 2 | 2.5 | 3 | 3.5 | 4 | 5 | 6 | 8 |
| Image shown | 2x | 3x | 3x | 4x | 4x | 5x | 10x | 10x |

Every one looked sharp. Densities that aren't whole numbers work too: MaCursor themes
with 25.6-point cursors in 26-pixel images show completely and click where they point.
The 1x image only matters on displays without Retina.


System Settings → Accessibility → Pointer → Reset Colors (suggested by Cursie) restores only the arrow
and the I-beam (and their `S` variants). It is no way back from a cape.

## Login agent

- **SMAppService:** for an app without an Apple team ID (ad-hoc or self-signed), launchd
  pins an `SMAppService` agent to the exact build. After an update it refuses to start it
  ("needs LWCR update"), and neither registering again nor switching it off and on helps.
  A plain launch agent in `~/Library/LaunchAgents` isn't pinned and keeps working across
  rebuilds.
- **Name in Login Items:** for a plain launch agent, System Settings → Login Items shows
  the program's name ("mousecloak"). `AssociatedBundleIdentifiers` only counts for apps
  with an Apple team ID.
