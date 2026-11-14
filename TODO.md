# TODO

Open work, known issues and ideas for this fork. [CHANGES.md](CHANGES.md) records what is
already done, [TESTING.md](TESTING.md) what has been tested and what still needs a test on
a real Mac.

## Known issues

- [ ] **Reset can't remove what it doesn't own** ([NOTES.md](NOTES.md#registrations-last-for-the-session)):
      backups stay for the session, and a variant like `ArrowS` from an earlier cape can
      only be overwritten. Unregistering with the global flag removes registrations of
      other processes too (measured on macOS 15.6 and 27.2.1). Removing backups after a
      reset would end the "first backup of a session counts" limitation. Never remove the
      `ArrowS`/`IBeamS` that macOS 27 registers itself. This may make the
      low-priority "reset from a stored copy" below unnecessary.
- [ ] **Backups stop at the arrow.** `backupAllCursors` skips everything once a backup of
      `Arrow` exists. If the original Mousecape backed up the arrow earlier in the session,
      `ArrowS` and `IBeamS` never get a backup. Simply dropping the early return, as
      SnowGlow-aww and Alex-Simedrea did, isn't safe here: once a cape is applied, the
      cursors without a backup can be the cape's own (on macOS 15.6, `ArrowS` exists only
      because a cape registered it), and they would be saved as the system's. Back up an
      extra cursor late only when no cape put it there (`MCAppliedExtraCursors`); test with
      the original Mousecape on macOS 27.
- [ ] **Blocking work on the main thread.**
  - Applying runs there, so a large cape can freeze the UI for a moment. SnowGlow-aww
    decodes each cursor's images on all cores into premultiplied BGRA, the window
    server's own layout, before registering them in order: 0.40 s → 0.16 s for 52 cursors.
  - A library reload parses every cape fully (often several MB each). It happens only
    when the folder changed, but a big library still stalls. Load the metadata first and
    the images on demand.
- [ ] **No undo** in the editor, or for deleting a cape. The original had both.
- [ ] **`mousecloak --create` asks questions on stdin** (`scanf` in `create.m`). Piped
      answers work, but options such as `--name` and `--author` would be easier to script.

## Build and release

Apple silicon only, on purpose. Apple's support for Intel Macs ends soon, and fewer of
them are in use every year, so this version puts no more work into the old architecture:
there is no x86_64 build.

- [ ] **CI.** A GitHub Actions workflow running `swift test` and `Scripts/build-app.sh` on
      a macOS runner.
- [ ] **Notarization** needs a paid Developer ID. Until then, users run `xattr -cr` after
      downloading (README, release notes).
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

- [ ] **Localization**, String catalogs (`.xcstrings`) need
      `xcstringstool`, which the Command Line Tools don't include. Use plain
      `Localizable.strings` with SwiftPM resources instead, or compile the catalog on CI.
- [ ] **Export a cape as a MaCursor theme** (`.cursor`). Import exists
      (`MaCursorTheme`); writing is the same mapping the other way round.
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
- [ ] **Cursor trails:** a line that follows the pointer and shrinks back into it when it
      stops (MaCursor has one; GPL-3.0, so only the idea).
- [ ] **Accessibility pointer size.** Mousecape's size and the system's pointer size
      (System Settings → Accessibility → Display → Pointer size) are the same setting
      underneath. Say so in Settings, or drop Mousecape's own slider.
- [ ] **Library search and sorting** for big libraries.
- [ ] **Hot spot fine-tuning** with the arrow keys in the editor preview.
- [ ] **Quick Look preview and thumbnail** for `.cape` files in Finder. These are app
      extensions, which SwiftPM cannot build; it would need an Xcode project or a manual
      `.appex` build.

## Low priority

Ideas from MaCursor's engine (GPL-3.0: the idea only, our own code). Only once everything
above is done, or a real problem calls for them.

- [ ] **Reset from a stored copy of the system cursors**, not from backups registered in
      the window server ([NOTES.md](NOTES.md#registrations-last-for-the-session)). Once per
      boot (`kern.bootsessionuuid`): reset the core cursors, capture the system cursors at
      scale 16 into a file, and reset and apply from that file. Captures that come back as
      red placeholders fall back to Apple's PDFs in HIServices' `cursors` folder (which
      has no arrow, I-beam or wait cursor). Takes away most of the "first backup of a
      session counts" limitation.
- [ ] **Guard against a cursor scale stuck at 16.** Capturing sets the scale to 16 and back;
      if it stops halfway, the scale stays at 16. Treat 16 as "not the user's choice" when
      reading the scale, as MaCursor does.

## Housekeeping

- [ ] **Related projects.** Once a month, check the original Mousecape, MaCursor, the
      other related projects and all their forks for work worth taking:
      [FORK-CHECK.md](FORK-CHECK.md).

Standing rule: keep the original licence's non-commercial clause and Alex Zielenski's
notice in every distribution. No paid builds, no donations tied to downloads.
