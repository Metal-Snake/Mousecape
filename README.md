Mousecape
===

A free cursor manager for macOS, built on the private, nonintrusive CoreGraphics APIs
that macOS itself uses to register the system cursors.

This is a modernized fork of [Alex Zielenski's Mousecape](https://github.com/alexzielenski/Mousecape):
the original cursor engine is kept and fixed where it broke on current macOS, the app
around it is rewritten in SwiftUI.

- macOS 14 Sonoma or later, Apple silicon only; tested on macOS 15.6 and 27.0.1
- Builds with the Xcode Command Line Tools alone (no Xcode project)
- No third-party dependencies, no network access

> **Work in progress.** Everything below works and is tested, but expect rough edges.
> [CHANGES.md](CHANGES.md) lists what changed from the original and what has been
> tested; [TODO.md](TODO.md) what is still open.

## How it works

Mousecape registers your cursors with the window server, the same way macOS registers its
own. macOS forgets them when you log out, so a small background agent
(`mousecloak --listen`) applies your cape again at login, on user switches and when
displays change. Turn it on in **Settings → Apply cape at login**.

**Settings** also hold the **Cursor size** (the same setting as the pointer size in
System Settings → Accessibility) and **Left-handed** mode, which mirrors the pointers.

## Capes

A set of cursors is called a cape. Each cape holds many cursors, each at several scales:
the Arrow may come at 1x, 2x, 5x and 10x, the Wait cursor at 1x and 2x.

An example cape is included: [Examples/com.maxrudberg.svanslosbluehazard.cape](Examples/com.maxrudberg.svanslosbluehazard.cape),
a remake of [Max Rudberg's](http://maxrudberg.com/) Svanslös cursors, generously crafted by
Max. Your library lives in `~/Library/Application Support/Mousecape/capes`, the same
folder the original app used.

### Importing

Double-click a file, drop it on the window or use **File → Import…** (⌘O). Mousecape
reads:

- **Capes** (`.cape`), from this fork or the original app
- **Windows cursor themes**: a theme folder, its `install.inf`, or `.cur`/`.ani` files
- **Linux cursor themes** (Xcursor, as used by GNOME, KDE and others): a theme folder or
  Xcursor files
- **MightyMouse** files (`.MightyMouse`)

Themes can also come as archives (`.zip`, `.7z`, `.rar`, `.tar.gz`, `.tar.xz`, …); they
are unpacked with the system's own tools. Converted cursors are sized to match macOS and
lose their empty margins. Importing a cape that is already in your library asks whether
to replace it or keep both.

[EXAMPLES.md](EXAMPLES.md) lists places to find capes and cursor themes.

### Applying and checking

Select a cape and click **Apply** (⌘↩); **Cape → Reset to Default Cursors** (⇧⌘R) brings
the macOS cursors back. A cape with problems gets a badge in the sidebar, and its page
says what happens to which cursor: macOS shows at most 24 frames of an animation, so
longer ones are reduced when applied; a cursor whose images don't fit is flagged. Click a
line to open that cursor in the editor.

## Making and editing capes

**File → New Cape** (⌘N) opens the editor; **Cape → Edit…** (⌘E) edits an existing one.
Add cursors with **+**, then drop a PNG into each scale well (1x, 2x, 5x, 10x). The first
image sets the cursor's size; click the large preview to set the hot spot, where the click
lands. The editor shows the same warnings as the library, per cursor and under Cape
Details.

### Animated cursors

An animated cursor is one image with all frames stacked vertically, first frame at the
top. Mousecape walks down the image one frame at a time, each frame the cursor's size.

macOS shows at most 24 frames. **Choose…** next to the frame count picks which frames to
keep (every n-th, spread evenly, the first ones, or your own pick), with the original and
the result playing side by side. Animations imported from Windows or Linux whose frames
last differently long keep each frame's duration; they are picked **By Time** when
applied, so the timing stays.

### Left-handed mode

By default, left-handed mode mirrors the pointers (arrow, hands, busy and the like) and
leaves the rest. Each cursor can say otherwise under **Left-handed mode** in the editor:
**Mirror**, **Don't Mirror**, or **Own Images**, its own left-handed artwork with its own
hot spot for where a mirrored image looks wrong. The **Left-handed** switch under the
preview shows the result. These settings are saved in the cape, so they travel with it.

### History

Every cape keeps the state it came into the library with and the last 20 states a save
replaced. **Cape → History…** (⌘Y) lists them, compares any two (which cursors changed,
and how, side by side) and restores any of them; restoring keeps the current state too.
Edited capes are marked with a pencil, and **Revert to Original…** brings back the
imported version. The history lives in `~/Library/Application Support/Mousecape/Versions`.

## Command line

The app bundle contains `mousecloak`, the command line front end of the engine:

```
Mousecape.app/Contents/MacOS/mousecloak --help
mousecloak --apply my.cape            # apply a cape
mousecloak --reset                    # back to the macOS cursors
mousecloak --scale 2                  # set the cursor scale
mousecloak --create folder/ -o my.cape   # build a cape from <cursor identifier>/<n>.png
mousecloak --export my.cape -o folder/   # write a cape's images as PNG files
mousecloak --dump current.cape        # save the cursors on screen as a cape
mousecloak --convert old.MightyMouse -o new.cape
mousecloak --list                     # what is registered, and the backups (for bug reports)
```

## Building

```
swift test                       # cape format, importers, editing, history, engine agreement
Scripts/build-app.sh             # → dist/Mousecape.app
Scripts/build-app.sh --zip       # → also dist/Mousecape.app.zip
```

`build-app.sh` signs with a "Mousecape Code Signing" certificate from your keychain when
there is one (`Scripts/make-signing-certificate.sh` creates it), so every build keeps the
same identity; otherwise it signs ad-hoc. Either way the app isn't notarized: on first
launch, right-click it and choose **Open**.

`Scripts/cursor-size-probe.swift` measures the size macOS really draws cursors at (for
testing on new macOS versions).

### Layout

| Path | What |
|---|---|
| `Sources/MousecloakCore` | The original cursor engine (Objective-C, manual retain/release) |
| `Sources/mousecloak` | Command line tool and background agent |
| `Sources/CapeKit` | The cape format, cursor images, editing, the Windows and Xcursor importers (pure Swift) |
| `Sources/Mousecape` | The SwiftUI app: library, history, editor, theme import |
| `Tests` | Swift Testing suites, and `TestSupport` with the file builders they share |
| `Resources` | Info.plist, app icon |
| `Scripts` | Building, signing, the cursor size probe |

### Safety

Capes and themes come from anywhere, so Mousecape treats them as untrusted: identifiers
that would leave the library folder are refused, image sizes and animation lengths are
bounded before decoding, and links in archives may not point outside the theme. See
**Hardening** in [CHANGES.md](CHANGES.md).

## LICENSE

Alex Zielenski: "I worked very hard researching the private methods used in Mousecape and
creating this app. Please respect me and my work by not using any of the information
provided here for commercial purposes."

Copyright (c) 2013-2014, Alex Zielenski
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
* Any redistribution, use, or modification is done solely for personal benefit and not for any commercial purpose or for monetary gain

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
