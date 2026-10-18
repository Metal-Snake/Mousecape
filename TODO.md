# TODO

Open work, known issues and ideas for this fork. CHANGES.md records what is already done
and what has been tested.

## Still to verify

- [ ] **A real login with a cape applied**, ideally on macOS 27. The agent's part is
      checked on macOS 15.6 by restarting it (as at login) and by switching the display
      resolution (as when plugging in a monitor): cape and cursor size come back both
      times. A real logout and login with an applied cape hasn't been done yet.
- [ ] **Images in the editor:** drop a PNG from Finder into a scale well, and use
      "Choose Image…". Hot spot clicks, frame choosing and saving are checked.
- [ ] **Windows cursors in the editor:** dropping a `.cur`/`.ani` on an image well. The
      import itself is checked with a real theme (zip, folder, single file).
- [ ] **MightyMouse import** with a real `.MightyMouse` file (none at hand).
- [ ] **Left-handed mode with the macOS cursors on macOS 27.** Mirroring a cape works
      there (confirmed 2026-10-18). Mirroring the macOS cursors without a cape is checked
      on macOS 15.6 (reset, Settings switch, agent at start and on display changes), not
      yet on macOS 27.
- [ ] **Wait backup in a fresh session.** Reset now backs up before restoring, so the first
      apply after a login should save the real beach ball. After the next login on macOS 27,
      apply a cape and check `mousecloak --list`: the Wait backup should read 24x24 pt,
      15 fr (the 30-frame system cursor, reduced), not 28x40.
- [ ] **macOS 26.** Tested on 15.6 and 27.0.1 only. The engine relies on private
      CGS/CoreCursor calls that any macOS version can change.

## Known issues

- [ ] **Hidden deprecation warnings.** The engine builds with
      `-Wno-deprecated-declarations`, which hides three warnings:
      `kUTTypePNG` in `MCDefs.m:73` and `MCDefs.m:94` (use `UTTypePNG`), and
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
      process remove them, so the first backup in a session is the one that counts. If
      another tool changed the cursors before Mousecape's first apply, that is what reset
      brings back. Logging out clears it.
- [ ] **No undo** in the editor, or for deleting a cape. The original had both.
- [ ] **`mousecloak --create` asks questions on stdin** (`scanf` in `create.m`), so it
      cannot be scripted. Add options such as `--name` and `--author`.
- [ ] **Login Items shows the agent as "mousecloak"**, not Mousecape: for a plain launch
      agent macOS names the program, and `AssociatedBundleIdentifiers` only counts for
      apps with an Apple team ID. Cosmetic; a Developer ID would fix it.
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
- [ ] **Time-based reduction for uneven animations.** For a Windows `.ani` whose steps have
      different durations and too many frames for the gcd approach, sample the whole loop
      at 24 evenly spaced moments and keep the frame shown at each (Cursie does this),
      instead of averaging the durations.
- [ ] **Localised file names in Windows packs.** Without an `install.inf`, roles are
      guessed from English file names only. Packs from Korea, Japan or China often use
      names like `일반선택.ani` (Normal Select). Add keywords in more languages.
- [ ] **Frame chooser follow-ups.** Drag across the filmstrip to select ranges; show the
      gap pattern of the kept frames; open it straight from the library's problem banner.
- [ ] **Left-handed capes.** Some themes are already drawn for the left hand (e.g. Bibata's
      `-Right` Windows packages); Mousecape's left-handed mode mirrors them back the wrong
      way. Add a flag that says which hand the cape is drawn for:
      - Stored **only in the cape file** (a new top-level key, e.g. `Handedness` = `right`
        (default when missing) / `left`), never in user settings, so it travels with the
        cape. Set in the editor's cape details; when importing a Windows pack, suggest it
        from names like `-Right` or `Left`.
      - Applying: mirror only when the cape's hand differs from the user's left-handed
        setting. A left-drawn cape in right-handed mode is mirrored to the right.
      - Optional per-cursor left-handed artwork: a cursor can carry its own left-handed
        representations and hot spot (e.g. `LeftHandedRepresentations`, `LeftHandedHotSpotX/Y`),
        used instead of mirroring. Useful where mirroring looks wrong (text, a hand, a
        shadow cast to one side). Cursors without it fall back to mirroring. The editor
        needs a "Left-handed" image slot per cursor, alongside the scales.
      - Compatibility: keep `MinimumVersion` at 2.0 so the original Mousecape still opens
        such capes; check that it ignores the unknown keys.
- [ ] **Generate missing scales**, e.g. 1x from 2x, with a clear warning that resampled
      images look worse.
- [ ] **Discover cursor variants instead of listing them.** `CGSCursorNameForSystemCursor(i)`
      returns the window server's names of its own cursors (learnt from Cursie; shown by
      `mousecloak --list`). macOS 15.6: the 9 standard ones. macOS 27.0.1: the same plus
      `ArrowS` and `IBeamS`, which is exactly what the fork handles today; the extra
      names Cursie lists (`CopyDrag`, `ResizeUp`, …) don't exist there. When a future
      macOS adds more, use this list for backup, reset and syncing instead of the fixed one.
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
      2026-10-18 it has no commits after `184f87b`.

Standing rule: keep the original licence's non-commercial clause and Alex Zielenski's
notice in every distribution. No paid builds, no donations tied to downloads.
