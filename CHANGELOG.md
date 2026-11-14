# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[unreleased]: https://github.com/Metal-Snake/Mousecape/compare/v3.1.0...HEAD
[3.1.0]: https://github.com/Metal-Snake/Mousecape/compare/v3.0.0...v3.1.0
[3.0.0]: https://github.com/Metal-Snake/Mousecape/releases/tag/v3.0.0
