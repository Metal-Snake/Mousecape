# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Animated cursor previews show each frame's own duration when a cursor has them
  (`FrameDurations`, e.g. from Windows `.ani` files); before, every frame showed equally
  long.

### Fixed

- The app no longer uses CPU while it shows animated cursors. Each animated preview made
  SwiftUI draw the window again for every frame, even while the window was hidden: about
  5 % CPU as long as a cape with animated cursors was selected. Core Animation now plays
  the previews.

## [3.2.0] - 2026-11-21

### Added

- Settings → History sets how much history each cape keeps: a number of saved states
  (1 to 100, 20 as before) or the disk space they may take (10 MB to 1 GB). The limit
  is per cape and the original doesn't count. Below it, the settings show the fullest
  history against the limit (the most states, or the largest by space, and which cape)
  and what all histories take together. A lower limit applies to all capes at once
  (older states go to the Trash).
- `mousecloak --create` takes the cape's details as options (`--name`, `--author`,
  `--identifier`, `--cape-version`, `--hidpi`/`--no-hidpi`) and defaults for all cursors
  (`--hot-spot`, `--frame-duration`). It reads each cursor's size and frames from its
  images, and a `cursor.plist` in a cursor's folder can set them. It asks only about what
  the images leave open, and only in a terminal, so it can run in a script.
- Undo and Redo in the editor (⌘Z, ⇧⌘Z). Quick edits of one field, like typing a name,
  are one step. Undo shows the cursor it changed, and brings back a removed cursor.
- A gallery of the cursor themes on pling.com (gnome-look.org), under File → Browse
  Cursor Themes Online… (⇧⌘O): search (⌘F on macOS 15 and later), sort, previews,
  licences, and installing with a double-click. Themes installed from the gallery are
  marked as such, and as "Update Available" when the author uploads a new version. A
  comparison shows what an update changes, cursor by cursor, before it is saved; the
  previous state stays in the cape's history. A cape from the gallery keeps its source
  (page, file and checksum) in an optional `Source` key of the cape file, so it travels
  with the file; the cape's page links to it. The app goes online only while the gallery
  is open.
- When a theme comes in several versions (a Linux and a Windows file, or one archive with
  a Regular, a Large and an Extra-Large version), Mousecape asks which one to install or
  import. It shows how they differ: a few cursors of each at their real size, and the
  number of cursors, size, sharpness and animation, with what differs in bold. It
  suggests the version with the most cursors, then the sharpest, then the regular size.
  Several versions can be installed at once, each as a cape of its own; versions of the
  same name get what tells them apart added to their name and identifier, and versions
  already in the library are replaced after one question for all of them. A cape from
  the gallery remembers which version it is (`Variant` in its `Source`), so an update
  takes the same one.
- Undo of Move to Trash in the library: the cape comes back with its history, and is
  applied again if it was applied.

### Changed

- Importing a cape again, or replacing it with another version of its theme, keeps its
  history: the import becomes the cape's new original, and its earlier original and
  current state stay as saved states that History can restore. Before, the history was
  moved to the Trash.
- Finder's Get Info and the About window show the build number with the version, such
  as "3.1.0 (404)". The copyright names the fork's years up to the current one.

### Fixed

- An archive with several themes no longer imports simply the first one by name: for
  Bibata's Windows zip that was the Extra-Large version.
- `mousecloak --create` without `-o` writes `<folder>.cape` next to the folder. It tried to
  write the cape over the folder's parent folder and failed.
- A reset removes the backups it brought back, so the next apply backs up the cursors on
  screen anew. Before, the first backup of a login session was the one every reset
  brought back until logout.
- On macOS 27, `ArrowS` and `IBeamS` get a backup of their own even when the original
  Mousecape backed up the arrow earlier in the session. A reset then brings back the
  system's variants instead of a copy of the arrow.
- After an update, the login agent runs the new version as soon as the app is started,
  even when the new version took the old one's place. Before, the old agent kept running
  until the next login in that case.

## [3.1.0] - 2026-11-14

### Added

- Import of MaCursor themes (`.cursor`): open them, drop them on the window, or use
  File → Import.
- The editor shows images at densities other than 1x, 2x, 5x and 10x (such as 3x), and
  lets you remove them.
- Applying a cape also gives core cursors 0 and 1, the arrow and the I-beam by number,
  the cape's arrow and I-beam, mirrored like them in left-handed mode, unless the cape
  has its own. Capes that do have them show them as "Arrow (Core)" and "I-Beam (Core)".

### Changed

- Images at any pixel density count as valid. macOS shows the smallest image dense
  enough for the screen, including 3x, 4x and fractional densities, so capes with such
  images are no longer marked as broken. Only frames that don't fit the image height
  are.
- Importing a MaCursor theme leaves out core cursors 0 and 1 when they are exact copies
  of its arrow and I-beam.

### Fixed

- The sidebar scrolls to a cape the app selects, after an import for example, instead of
  leaving it outside the visible part of the list.
- `mousecloak --export` writes real PNG files. Images stored as TIFF, as in captured
  cursors, were written into `.png` files unchanged.
- Importing several capes or themes that are already in the library asks about each, one
  after the other. Before, the first question stopped the rest of a `.cape` import, and
  further themes were added as copies without asking.
- Cursor tiles show a spinner while their images load, and a sign for images that can't
  be read, instead of an empty square.
- The login agent applies the cape once per display change. It applied it for every
  display, before and after each change.
- `mousecloak --create` keeps every cursor of the folder (it stored them all under the
  cape's identifier, so one was left), and the HiDPI answer is no longer skipped.
- A cancelled cursor capture puts back the cursor size and shows the cursor again.

### Security

- Importing a MightyMouse file checks every value in it. A broken or hostile file could
  make Mousecape read past the end of its image data, or crash it with values of the
  wrong type; such cursors are now left out, and files with a broken structure are
  refused. Images over the size limit are refused too, as for every other import.
- `mousecloak` no longer writes one byte past its input buffer when it asks for cape
  details on the command line.

## [3.0.0] - 2026-11-10

The first release of this fork, after the original's last release (build 1813). The cursor
engine is the original; the app around it is new. [CHANGES.md](CHANGES.md) describes every
difference from the original in detail.

### Added

- A new SwiftUI app. The library animates every cursor of a cape, with an optional hot
  spot overlay, and marks capes with problems: which cursors macOS will reduce or
  reject, and why. Each problem opens its cursor in the editor.
- A new cape editor: cape details, adding and removing cursors, hot spot by click, frame
  count and duration, and one image well per scale (1x, 2x, 5x, 10x).
- Choose Frames: pick which frames of a long animation to keep (every n-th, spread
  evenly, the first ones, by time, or by hand), with the original and the result side by
  side.
- History for every cape: compare any two states, restore any of them, or revert to the
  imported original.
- Left-handed mode per cursor: Mirror, Don't Mirror, or Own Images with their own hot
  spot. Saved in the cape, so it travels with it.
- Left-handed mode mirrors the macOS cursors too when no cape is applied.
- Import of Windows cursor themes (`.cur`, `.ani`, `install.inf`) and Linux Xcursor themes,
  from folders or archives (`.zip`, `.7z`, `.rar`, `.tar.gz`, `.tar.xz`, …). Imported
  cursors lose their empty margins.
- Animations whose frames last differently long keep their timing when applied.
- `mousecloak --list` shows what the window server has registered, for bug reports.

### Changed

- Requires macOS 14 Sonoma or later on Apple silicon.
- New bundle identifier `io.github.metal-snake.Mousecape`. The library folder, the cape
  format and the settings of the original carry over.
- The login helper is replaced by a launch agent, turned on in Settings → Apply cape at
  login. It re-applies the cape at login, on user switches and when displays change.
- Cursor names follow Apple's own names for the cursor resources.
- Importing a cape whose identifier is taken asks whether to replace the existing one.
- Saving keeps keys of a cape that Mousecape doesn't know.
- `mousecloak` exits with an error status when a command fails.

### Removed

- Automatic updates (Sparkle). Download new versions from the GitHub releases.
- Intel (x86_64) builds.
- Undo in the editor and for deleting capes, for now.
- The setting that made a double click edit a cape instead of applying it.

### Fixed

- Capes with animations of more than 24 frames apply; the animation is reduced instead
  of the whole apply stopping.
- A cursor that fails no longer stops the rest of the cape from applying.
- Reset brings back the Wait cursor and reports cursors it could not restore.
- Capes show on macOS 27, and reset works there (`ArrowS` and `IBeamS`).
- Captured cursors can be applied.
- Left-handed mode mirrors Zoom Out.
- Capes saved under another file name are restored at login.
- The login agent no longer resets the cursor size to 1x, and restores the chosen size
  after display changes on macOS 27.

### Security

- Capes and themes are treated as untrusted: identifiers that would leave the library
  folder are refused, image sizes and animation lengths are checked before decoding, and
  links in themes that point outside the theme are ignored.

[unreleased]: https://github.com/Metal-Snake/Mousecape/compare/v3.2.0...HEAD
[3.2.0]: https://github.com/Metal-Snake/Mousecape/compare/v3.1.0...v3.2.0
[3.1.0]: https://github.com/Metal-Snake/Mousecape/compare/v3.0.0...v3.1.0
[3.0.0]: https://github.com/Metal-Snake/Mousecape/releases/tag/v3.0.0
