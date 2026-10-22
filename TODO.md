# TODO

Open work, known issues and ideas for this fork. [CHANGES.md](CHANGES.md) records what is
already done, [TESTING.md](TESTING.md) what has been tested and what still needs a test on
a real Mac.

## Known issues

- [ ] **Hidden deprecation warnings.** The engine builds with
      `-Wno-deprecated-declarations`, which hides three warnings:
      `kUTTypePNG` in `MCDefs.m:83` and `MCDefs.m:104` (use `UTTypePNG`), and
      `NSAlphaFirstBitmapFormat` in `create.m:191`. Fix them and remove the flag.
- [ ] **Blocking work on the main thread.**
  - Applying runs there, so a large cape can freeze the UI for a moment.
  - A library reload parses every cape fully (often several MB each). It happens only
    when the folder changed, but a big library still stalls. Load the metadata first and
    the images on demand.
- [ ] **Sidebar jumps after an import:** the list scrolls so that the top row is cut off.
- [ ] **Empty tiles while previews decode.** Show a placeholder or the cursor name
      instead of an empty square.
- [ ] **Backups live for the whole login session.** The window server won't let a later
      process remove them ([NOTES.md](NOTES.md#registrations-last-for-the-session)), so the
      first backup in a session is the one that counts. If
      another tool changed the cursors before Mousecape's first apply, that is what reset
      brings back. Logging out clears it.
- [ ] **No undo** in the editor, or for deleting a cape. The original had both.
- [ ] **`mousecloak --create` asks questions on stdin** (`scanf` in `create.m`), so it
      cannot be scripted. Add options such as `--name` and `--author`.
- [ ] **Login Items shows the agent as "mousecloak"**, not Mousecape
      ([NOTES.md](NOTES.md#login-agent)). Cosmetic; a Developer ID would fix it.
- [ ] **Original Mousecape installed alongside.** Both apps claim the
      `com.alexzielenski.mousecape.cape` type. The original's last release (1813) is
      Intel-only, so this only matters on Macs with Rosetta, where it's untested which app
      opens `.cape` files.

## Decisions

- [ ] **Re-apply at launch?** The original re-applied the cape whenever the app started;
      this fork leaves that to the agent. Maybe bring it back when the agent is off.
- [ ] **Closing the window quits the app** (single `Window` scene). Keep it or not?
- [ ] **Library click preferences.** The original's click and double-click actions were
      not ported. Port them or drop them for good.

## Build and release

Apple silicon only, on purpose: macOS 27 no longer runs on Intel Macs, so there is no
x86_64 build.

- [ ] **CI.** A GitHub Actions workflow running `swift test` and `Scripts/build-app.sh` on
      a macOS runner.
- [ ] **Releases.** Tag, zip and upload a GitHub release. Notarization needs a paid
      Developer ID; until then, document right-click → Open.
- [ ] **Version scheme.** `build-app.sh` says 2.0.0; the last upstream release was
      build 1813. Decide on a scheme and keep the version in one place.
- [ ] **Updates.** None at the moment. The original's Sparkle setup was dropped: it was an
      old submodule that needs Xcode to build, and its feed pointed to the original's
      appcast, so it would have offered the original's Intel-only builds. Options, from
      least to most work:
      1. An opt-in check of the GitHub releases API that only links to the release page.
      2. A Homebrew tap with a cask (`brew upgrade`).
      3. Sparkle 2 as a Swift package, embedded by `build-app.sh`, with our own EdDSA key
         and an appcast published with each release. Check first how Sparkle treats an
         ad-hoc signed app, whose code signature changes with every build. Cursie's
         `scripts/build-notarized-release.sh` shows how to embed and sign Sparkle's
         framework, XPC services and updater in a SwiftPM build (with a Developer ID).

## Features and ideas

- [ ] **Localization**, German first. String catalogs (`.xcstrings`) need
      `xcstringstool`, which the Command Line Tools don't include. Use plain
      `Localizable.strings` with SwiftPM resources instead, or compile the catalog on CI.
- [ ] **Export a cape to a folder of PNGs.** The engine can already do this
      (`exportCape`, `mousecloak --export`); only the UI is missing. Also allow dragging a
      cape out of the window to share it.
- [ ] **Easier animated cursors.** Build the sprite sheet from several single-frame images
      or a GIF, so nobody has to stack frames by hand.
- [ ] **Localised file names in Windows packs.** Without an `install.inf`, roles are
      guessed from English file names only. Packs from Korea, Japan or China often use
      names like `일반선택.ani` (Normal Select). Add keywords in more languages.
- [ ] **Theme import follow-ups.**
      - Archives with several themes (e.g. `banana-all.tar.xz`, Bibata's light and dark):
        only the first is imported. Import all, or let the user choose.
      - Windows packs with colour variants in one folder (`normal-select_black.cur`,
        `…_white.cur`): the first by name wins. Detect the variants and ask.
      - Xcursor themes that `Inherits=` another theme for missing cursors: the inherited
        theme isn't there on a Mac, so those cursors stay macOS's. Could fall back to a
        theme in the same archive.
      - KDE's SVG cursors (`cursors_scalable/`, Plasma 6): sharp at every scale. Only
        worth it once themes ship them without Xcursor files.
      - `.tar.zst`: the system's libarchive has no built-in zstd.
- [ ] **Frame chooser follow-ups.** Drag across the filmstrip to select ranges; show the
      gap pattern of the kept frames; open it straight from the library's problem banner.
- [ ] **Set the left-handed mode for several cursors at once.** Kiriko needs it for about
      ten.
- [ ] **Generate missing scales**, e.g. 1x from 2x, with a clear warning that resampled
      images look worse.
- [ ] **Discover cursor variants instead of listing them.** `CGSCursorNameForSystemCursor`
      returns the window server's own cursor names (learnt from Cursie). Up to macOS
      27.0.1 that is exactly the set the fork handles today
      ([NOTES.md](NOTES.md#system-cursor-names)). When a future macOS adds more, use this
      list for backup, reset and syncing instead of the fixed one.
- [ ] **Menu bar extra** for switching capes quickly.
- [ ] **Accessibility pointer size.** Mousecape's size and the system's pointer size
      (System Settings → Accessibility → Display → Pointer size) are the same setting
      underneath. Say so in Settings, or drop Mousecape's own slider.
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
      2026-10-22 it has no commits after `184f87b`.

Standing rule: keep the original licence's non-commercial clause and Alex Zielenski's
notice in every distribution. No paid builds, no donations tied to downloads.
