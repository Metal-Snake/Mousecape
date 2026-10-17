# TODO

Open work, known issues and ideas for this fork. CHANGES.md records what is already done.

## Verify first (built, never run for real)

None of these have been tried on a live system. They change the real cursors or the
login items, so they need a person at the Mac.

- [ ] **Apply and reset** a cape from the app. Reset is ⇧⌘R, and `mousecloak --reset`
      also works from Terminal.
- [ ] **Login agent.** Turn it on in Settings, approve it in System Settings → Login Items,
      log out and back in, and check that the cape comes back. Also check that a display
      change keeps it. Open question: does `SMAppService.agent` accept an **ad-hoc signed**
      app, or does it need a real signing identity?
- [ ] **Cursor size slider** and **left-handed mode**, including that the agent restores
      both at login.
- [ ] **Capture Current Cursors.** While capturing, the engine hides the cursor and scales
      it to 16× for a moment.
- [ ] **MightyMouse import**, using a real `.MightyMouse` file.
- [ ] **Finder integration.** Double-clicking a `.cape` opens it. Check what happens when
      the original Mousecape is installed too, since both claim
      `com.alexzielenski.mousecape.cape`.
- [ ] **Cape editor.** Its layout has never been seen on screen. Check the image wells,
      drag and drop, hot spot clicks, frame counts and saving.
- [ ] **Newer macOS.** Test on macOS 15 and 26. The engine relies on private CGS/CoreCursor
      calls that Apple can change at any time; another fork needed a fix for the
      macOS 27 beta.

## Known issues

- [ ] **Hidden deprecation warnings.** The engine builds with
      `-Wno-deprecated-declarations`, which hides three warnings:
      `kUTTypePNG` in `MCDefs.m:73` and `MCDefs.m:94` (use `UTTypePNG`), and
      `NSAlphaFirstBitmapFormat` in `create.m:191`. Fix them and remove the flag.
- [ ] **Blocking work on the main thread.**
  - Applying runs there, so a large cape can freeze the UI for a moment.
  - Library reload decodes every cape fully (often several MB each) whenever the app
    becomes active. Load the metadata first and the images on demand.
  - Cursor previews decode PNGs on the main thread.
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

- [ ] **Universal binary.** `build-app.sh` builds arm64 only. Build each architecture with
      `--triple` and merge the binaries with `lipo`. The Command Line Tools cannot run
      `swift build --arch arm64 --arch x86_64`, because that needs Xcode's build system.
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
- [ ] **Accessibility pointer size.** Keep the cursor size in step with
      System Settings → Accessibility → Display → Pointer size.
- [ ] **Library search and sorting** for big libraries.
- [ ] **Hot spot fine-tuning** with the arrow keys in the editor preview.
- [ ] **Quick Look preview and thumbnail** for `.cape` files in Finder. These are app
      extensions, which SwiftPM cannot build; it would need an Xcode project or a manual
      `.appex` build.
- [ ] **New screenshot** for the README.

## Housekeeping

- [ ] **Push.** The `modernize` branch has not been pushed to `Metal-Snake/Mousecape`.
      It stays local until decided otherwise.
- [ ] **`.vscode/`** is untracked. Either add it to `.gitignore` or commit the parts worth
      sharing.
- [ ] **Upstream.** `git fetch upstream` (alexzielenski/Mousecape) now and then. As of
      2026-10-17 it has no commits after `184f87b`.
- [ ] **Licence.** Keep the non-commercial clause and Alex Zielenski's notice in every
      distribution. No paid builds, no donations tied to downloads.
