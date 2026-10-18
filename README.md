Mousecape
===

A free cursor manager for macOS, built on the private, nonintrusive CoreGraphics APIs
that macOS itself uses to register the system cursors.

This is a modernized fork of [Alex Zielenski's Mousecape](https://github.com/alexzielenski/Mousecape):
the original cursor engine is kept as it is, the app around it is rewritten in SwiftUI.

- macOS 14 Sonoma or later
- Builds with the Xcode Command Line Tools alone (no Xcode project)
- No third-party dependencies, no network access

> **Work in progress.** Library, previews, applying, importing, the cape editor and the
> login agent are in place; expect rough edges.

## How it works

Mousecape registers your cursors with the window server, the same way macOS registers its
own. macOS forgets them when you log out, so a small background agent
(`mousecloak --listen`) applies your cape again at login, on user switches and when
displays change. Turn it on in **Settings → Apply cape at login**.

## Capes

A set of cursors is called a cape. Each cape holds many cursors, each at several scales:
the Arrow may come at 1x, 2x, 5x and 10x, the Wait cursor at 1x and 2x.

An example cape is included: [Examples/com.maxrudberg.svanslosbluehazard.cape](Examples/com.maxrudberg.svanslosbluehazard.cape),
a remake of [Max Rudberg's](http://maxrudberg.com/) Svanslös cursors, generously crafted by
Max. Double-click a cape, drop it on the window or use **File → Import…** to add it to
your library. MightyMouse themes are converted on import, and so are Windows cursor
themes: drop a theme folder, its `.zip`, or `.cur`/`.ani` files on the window.

Your library lives in `~/Library/Application Support/Mousecape/capes`, the same folder
the original app used.

### Making your own

**File → New Cape** (⌘N) opens the editor; **Cape → Edit…** (⌘E) edits an existing one.
Add cursors with **+**, then drop a PNG into each scale well (1x, 2x, 5x, 10x). The first
image sets the cursor's size; click the large preview to set the hot spot, where the
click lands. The editor flags images whose size does not fit.

### Animated cursors

An animated cursor is one image with all frames stacked vertically, first frame at the
top. Mousecape walks down the image one frame at a time, each frame the cursor's size.

## Command line

The app bundle contains `mousecloak`, the command line front end of the engine:

```
Mousecape.app/Contents/MacOS/mousecloak --help
mousecloak --apply my.cape       # apply a cape
mousecloak --reset               # back to the macOS cursors
mousecloak --create folder/      # build a cape from <cursor identifier>/<n>.png
mousecloak --scale 2             # set the cursor scale
```

## Building

```
swift test                       # cape parsing tests
Scripts/build-app.sh             # → dist/Mousecape.app (ad-hoc signed)
Scripts/build-app.sh --zip       # → also dist/Mousecape.app.zip
```

`build-app.sh` signs with a "Mousecape Code Signing" certificate from your keychain when
there is one (`Scripts/make-signing-certificate.sh` creates it), so every build keeps the
same identity; otherwise it signs ad-hoc. Either way the app isn't notarized: on first
launch, right-click it and choose **Open**.

### Layout

| Path | What |
|---|---|
| `Sources/MousecloakCore` | The original cursor engine (Objective-C, manual retain/release) |
| `Sources/mousecloak` | Command line tool and background agent |
| `Sources/CapeKit` | Reading and writing `.cape` files, cursor frames (pure Swift, tested) |
| `Sources/Mousecape` | The SwiftUI app |
| `Resources` | Info.plist, app icon, plists of earlier login agents (for unregistering) |

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
