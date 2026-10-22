# Notes on macOS

What this fork learnt about how macOS handles cursors. Mousecape relies on private
CGS/CoreCursor calls, so any of this can change with the next macOS version. Unless a
version is named, it was measured on macOS 15.6 and 27.0.1 on Apple silicon. How to
repeat the checks is in [TESTING.md](TESTING.md).

## Frame limit

The window server refuses cursors with more than 24 frames: registering 25 or more fails
with `kCGErrorFailure`. On macOS 15.6 the limit is the same for every cursor name
(standard, variant, core or made-up), size, pixel density and registration flag tried.
macOS registers its own cursors another way, so its Wait cursor (the beach ball) has 30
frames.

A registered cursor has one frame duration for all its frames. Animations whose frames
last differently long can only keep their timing by repeating frames.

## Registrations last for the session

Only the process that registered a cursor can unregister it. Every later process fails,
silently. So backups made by the first apply of a login session stay until logout, and
cursors are overwritten rather than removed.

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

## Reset Colors

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
