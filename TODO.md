# TODO

Open work, known issues and ideas for this fork. CHANGES.md records what is already done.

## Verify first (built, never run for real)

None of these have been tried on a live system. They change the real cursors or the
login items, so they need a person at the Mac.

- [ ] **Apply and reset** a cape from the app. Reset is ⇧⌘R, and `mousecloak --reset`
      also works from Terminal.
- [ ] **Login agent across a real login.** Registering, approval and running as a
      background process work with the ad-hoc signed app (checked 2026-10-17). Still to do:
      log out and back in and check that the cape comes back, and that a display change
      (plugging in a monitor) keeps both cape and cursor size.
- [ ] **Agent after an update without launching the app.** The agent is pinned to the code
      hash of `mousecloak`; the app re-registers it at launch when the hash changed. Until
      the app has been opened once after an update, the agent will not start. Consider a
      stable signing identity (a self-signed certificate keeps the requirement stable
      across builds) or a note in the release notes.
- [ ] **Cursor size slider** and **left-handed mode**, including that the agent restores
      both at login.
- [ ] **Capture Current Cursors.** While capturing, the engine hides the cursor and scales
      it to 16× for a moment.
- [ ] **MightyMouse import**, using a real `.MightyMouse` file.
- [ ] **Finder integration.** Double-clicking a `.cape` opens it. Check what happens when
      the original Mousecape is installed too, since both claim
      `com.alexzielenski.mousecape.cape`.
- [ ] **Cape editor.** The layout has been checked on screen. Still to do: dropping images,
      setting the hot spot by click, changing frame counts and saving.
- [ ] **Newer macOS.** Test on macOS 26 and 27. The engine relies on private CGS/CoreCursor
      calls that Apple can change at any time. The known macOS 27 beta issue (cursor scale
      reset on display changes) is handled; see CHANGES.md.

## Known issues

- [ ] **Hidden deprecation warnings.** The engine builds with
      `-Wno-deprecated-declarations`, which hides three warnings:
      `kUTTypePNG` in `MCDefs.m:73` and `MCDefs.m:94` (use `UTTypePNG`), and
      `NSAlphaFirstBitmapFormat` in `create.m:191`. Fix them and remove the flag.
- [ ] **Blocking work on the main thread.**
  - Applying runs there, so a large cape can freeze the UI for a moment.
  - A library reload parses every cape fully (often several MB each). It now happens only
    when the folder changed, but a big library will still stall. Load the metadata
    first and the images on demand.
- [ ] **Empty tiles while previews decode.** Show a placeholder or the cursor name
      instead of an empty square.
- [ ] **Window closing and reopening on double-clicking a `.cape`** (macOS 27.0.1). A
      screen recording showed SwiftUI closing the window and creating a new one for the
      open event. The `Window` scene now ignores external events, and the app delegate
      handles them. Confirm on macOS 27; macOS 15 never showed it.
- [ ] **Wait without a backup falls back to the Busy cursor**, which is the arrow with a
      beach ball, not the beach ball alone. This only happens in login sessions whose
      backups were made by a version that could not back up Wait (more than 24 frames).
      A new login fixes it for good.
- [ ] **Frame chooser follow-ups.** The chooser is in (2026-10-17). Ideas: drag across the
      filmstrip to select ranges; show the gap pattern of the kept frames; offer it from
      the library's problem banner directly.
- [ ] **What `ArrowS` and `IBeamS` are.** On macOS 15.6 the system doesn't register them,
      and an app setting the standard arrow still gets `Arrow` even when `ArrowS` is
      registered (checked by setting `NSCursor.arrow` in a test window). On macOS 27.0.1
      `ArrowS` apparently replaces the arrow. To check on another macOS version, apply
      `Examples/ArrowS-Test.cape`: it replaces only `ArrowS` with a magenta arrow marked
      "S". Then reset, which should bring the normal arrow back.
      **macOS 27.0.1 (2026-10-17):** the magenta arrow shows, so 27 uses `ArrowS`.
      Switching to Svanslös replaces it, but reset kept it. Diagnosis pending:
      `mousecape-diagnose.sh` runs the test with `mousecloak --list` at each step. Capes
      without `ArrowS` should probably register it from their `Arrow` on macOS 27.
- [ ] **Backups live for the whole login session.** The window server won't let a later
      process remove them, so the first backup in a session is the one that counts. If
      another tool changed the cursors before Mousecape's first apply, that is what reset
      brings back. Logging out clears it.
- [ ] **No undo** in the editor, or for deleting a cape. The original had both.
- [ ] **`mousecloak --create` asks questions on stdin** (`scanf` in `create.m`), so it
      cannot be scripted. Add options such as `--name` and `--author`.
- [ ] **The agent's output goes nowhere.** The engine prints to stdout with ANSI colours.
      Switch to `os_log`, or set `StandardOutPath` in the agent plist.
- [ ] **No re-apply at launch.** The app no longer re-applies the cape when it starts,
      unlike the original. Decide whether that should come back, for example only when the
      agent is off.
- [ ] **Closing the window quits the app** (single `Window` scene). Decide whether that is
      what we want.
- [ ] **No preferences for library clicks.** The original's click and double-click actions
      were not ported.

## Build and release

Apple silicon only, on purpose: macOS 27 no longer runs on Intel Macs, so there is no
x86_64 build.

- [ ] **CI.** A GitHub Actions workflow running `swift test` and `Scripts/build-app.sh` on
      a macOS runner.
- [ ] **Releases.** Tag, zip and upload a GitHub release. Notarization needs a paid
      Developer ID; until then, document right-click → Open.
- [ ] **Version scheme.** `build-app.sh` says 2.0.0; the last upstream release was
      build 1813. Decide on a scheme and keep the version in one place.
- [ ] **Update checks.** Sparkle is gone, so there are none. If wanted, add an opt-in check
      of the GitHub releases API that only links to the release page.

## Features and ideas

- [ ] **Localization**, German first. String catalogs (`.xcstrings`) need
      `xcstringstool`, which the Command Line Tools don't include. Use plain
      `Localizable.strings` with SwiftPM resources instead, or compile the catalog on CI.
- [ ] **Export a cape to a folder of PNGs.** The engine can already do this
      (`exportCape`, `mousecloak --export`); only the UI is missing. Also allow dragging a
      cape out of the window to share it.
- [ ] **Easier animated cursors.** Build the sprite sheet from several single-frame images
      or a GIF, so nobody has to stack frames by hand.
- [ ] **Generate missing scales**, e.g. 1x from 2x, with a clear warning that resampled
      images look worse.
- [ ] **Windows cursors.** Import `.cur` and `.ani` files.
- [ ] **Menu bar extra** for switching capes quickly.
- [ ] **Accessibility pointer size.** Mousecape's size and the system's pointer size
      (System Settings → Accessibility → Display → Pointer size) are the same setting
      underneath. Show that in Settings, or drop Mousecape's own slider.
- [ ] **Library search and sorting** for big libraries.
- [ ] **Hot spot fine-tuning** with the arrow keys in the editor preview.
- [ ] **Quick Look preview and thumbnail** for `.cape` files in Finder. These are app
      extensions, which SwiftPM cannot build; it would need an Xcode project or a manual
      `.appex` build.
- [ ] **New screenshot** for the README.

## Housekeeping

- [ ] **Example capes.** `Default_macOS 15.cape` and `Default_macOS 26.cape` contain
      Apple's cursor artwork, and `Kiriko.cape` is by ArakiCC under unknown terms. Keep
      them local (not committed) unless their redistribution is cleared.
- [ ] **Push.** The `modernize` branch has not been pushed to `Metal-Snake/Mousecape`.
      It stays local until decided otherwise.
- [ ] **Upstream.** `git fetch upstream` (alexzielenski/Mousecape) now and then. As of
      2026-10-17 it has no commits after `184f87b`.
- [ ] **Licence.** Keep the non-commercial clause and Alex Zielenski's notice in every
      distribution. No paid builds, no donations tied to downloads.
