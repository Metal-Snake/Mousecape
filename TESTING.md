# Testing

What has been tested on a real Mac, what still has to be, and how. `swift test` covers
the cape format, the importers, editing, the history and the rules the engine and CapeKit
share. It can't touch the window server, so applying, resetting and the login agent need
a manual test. What these tests found out about macOS is in [NOTES.md](NOTES.md).

## Tested

**On macOS 15.6 and 27.0.1:**

- Applying and resetting capes, from the app and with `mousecloak`, including capes with
  more than 24 frames and with `ArrowS`/`IBeamS`. On macOS 27.0.1, reset brings back the
  standard arrow and I-beam.
- Opening `.cape` files from Finder; the library window stays open.
- Left-handed mode with a cape applied.
- Cursor sizes, measured with `Scripts/cursor-size-probe.swift`.
- Reset Colors in System Settings, to compare with Mousecape's reset.

**On macOS 15.6:**

- The login agent re-applies the cape and the cursor size when it starts (as at login)
  and after a display change (simulated by switching the resolution). It keeps running
  across rebuilds without the app being opened.
- Left-handed mode without a cape: reset, the Settings switch, and the agent at start and
  on display changes all mirror the macOS cursors.
- Left-handed settings per cursor: a cape with an automatic arrow, an I-beam set to
  *Mirror*, an open hand set to *Don't Mirror* (normally mirrored) and a pointing hand
  with own images registers exactly that (checked through a cursor dump: images and hot
  spots).
- Capture Current Cursors: the capture has no problems and applies.
- The editor: setting the hot spot by click, Choose Frames, saving; resizable sheets.
- Windows cursors: a theme `.zip`, a theme folder and a single `.cur` import; the
  converted animated theme applies.

## Still to verify

- [ ] **A real login with a cape applied**, ideally on macOS 27. The agent's part is
      checked on macOS 15.6 (see above), but not a real logout and login.
- [ ] **Wait backup in a fresh session.** Reset backs up before restoring, so the first
      apply after a login should save the real beach ball. After the next login on macOS
      27, apply a cape and check `mousecloak --list`: the Wait backup should read
      24x24 pt, 15 fr (the 30-frame system cursor, reduced), not 28x40.
- [ ] **Left-handed mode without a cape on macOS 27.** Checked on macOS 15.6 only.
- [ ] **Own left-handed images on macOS 27.** Checked on macOS 15.6 only.
- [ ] **Images in the editor:** drop a PNG from Finder into a scale well, and use
      "Choose Image…".
- [ ] **Windows cursors in the editor:** drop a `.cur`/`.ani` on an image well.
- [ ] **MightyMouse import** with a real `.MightyMouse` file (none at hand).
- [ ] **Linux (Xcursor) themes:** import a theme folder and a `.tar.xz`, then apply the
      cape. Covered by `swift test` only.
- [ ] **Archives other than `.zip`:** `.7z` and `.tar.*` are covered by `swift test` only,
      `.rar` not at all (`tar` can't create one for a test).
- [ ] **Frames picked by time:** apply a cape with `FrameDurations` (e.g. an imported
      `.ani` with uneven step durations) and compare the animation with Choose Frames →
      By Time.
- [ ] **History:** compare two states, Restore This Version, Remove Saved States… and
      Revert to Original… in the app. Covered by `swift test` only.
- [ ] **Importing a theme again:** replace the earlier import, and keep both.
- [ ] **macOS 26.** Tested on 15.6 and 27.0.1 only.

## Tools

- **`mousecloak --list`** shows what the window server has registered for every cursor
  (size, hot spot, frames, pixel sizes), the backups, and the window server's own cursor
  names. Compare it before and after an apply or reset.
- **`MOUSECAPE_LIBRARY=/some/dir`** points the app at a throwaway library.
- **`Examples/ArrowS-Test.cape`** replaces only `ArrowS` with a magenta arrow marked "S".
  Apply it to see whether apps show `ArrowS` or `Arrow`, then reset: the normal arrow
  should come back.
- **`Scripts/cursor-size-probe.swift`** measures the size macOS really draws cursors at.
  Run it on each new macOS version.

## Test themes

Themes from [EXAMPLES.md](EXAMPLES.md) that exercise less common paths:

- **Many frames:** animated `.ani` themes from the RW Designer library can have more
  than 24 frames, which macOS can't show and Mousecape reduces.
- **Long Linux animations:** Bibata's busy cursors have 54 frames, apple_cursor's 40.
- **Left-handed variants:** Bibata's `-Right` packages are drawn for left-handed use;
  compare them with Mousecape's own mirroring.
- **Large collections:** Microtribute/mac-cursors and KingJayan/mousecape-cursors import
  dozens of capes at once.
- **File names with UUIDs:** GinoXiscatti/MacOS-Cursors-Collection, for the library's
  renaming to `<identifier>.cape`.
- **Size folders and `.7z`:** windows-cursors-modern keeps each size (`x1` … `x5`) in a
  folder of its own; the import should take the largest.
- **MightyMouse import:** the Macintosh Repository cursor packs, once unpacked.
