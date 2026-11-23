# CLAUDE.md

Mousecape is a cursor manager for macOS 14+, Apple silicon only. This fork keeps Alex Zielenski's Objective-C cursor engine and rewrites everything
around it in Swift/SwiftUI. It uses SwiftPM only: no Xcode project and no third-party
dependencies.

README.md is for users. CHANGELOG.md lists the changes per version (Keep a Changelog,
SemVer, starting at 3.0.0). CHANGES.md records in detail what 3.0.0 changed from upstream
`184f87b`.
TESTING.md records what has been tested on a real Mac and what still has to be. NOTES.md
holds what is known about how macOS handles cursors. TODO.md holds open work, known issues
and pending decisions. EXAMPLES.md lists where to find capes and themes. FORK-CHECK.md
says how to check related projects and their forks each month. Read the relevant
part of these before you change behaviour, and keep them current (see below). They
describe the fork as it is; earlier builds of the fork never left this machine, so don't
document them.

## Commands

```
swift build                       # debug build of all targets
swift test                        # all suites (Swift Testing, not XCTest)
swift test --filter CapeKitTests  # one target; --filter also takes a test name
Scripts/build-app.sh [--zip]      # release build → dist/Mousecape.app (signed, see script header)
Scripts/release.sh                # test, build, tag vX.Y.Z, push, GitHub release (newest CHANGELOG version)
MOUSECAPE_LIBRARY=/some/dir …     # point the app at a throwaway library folder
```

The Command Line Tools are enough. String catalogs (`.xcstrings`) can't be compiled
without Xcode, so don't add them.

## Layout and architecture

| Target | Language | Role |
|---|---|---|
| `MousecloakCore` | Objective-C, **manual retain/release** (`-fno-objc-arc`) | The original engine. It applies, backs up, restores and scales cursors through private CGS/CoreCursor calls (`include/CGSInternal`). `MousecloakCore.h` and `module.modulemap` expose it to Swift. |
| `CapeKit` | Pure Swift, no private API | The `.cape` format (`Cape`, `CapeCursor`), sprite sheets (`CursorSheet`), the editing model and validation (`CapeEditing`), capes from folders of images (`CapeFolder`, for `mousecloak --create`), Undo steps (`EditHistory`, `CapeEditPart`), the pling.com catalogue (`Pling/`), what tells versions of a theme apart (`CapeSummary`) and names them when several are installed (`ThemeVersions`), diffs, left-handed rules, and the Windows (`Windows/`), Xcursor (`Xcursor/`) and MaCursor (`MaCursor/`) importers. |
| `mousecloak` | Swift | CLI (`main.swift`, `--create` in `CreateCape.swift`). `mousecloak --listen` is also the background login agent. |
| `Mousecape` | SwiftUI | The app. `Model/` holds `AppModel` (UI state and actions), `Library` (the capes folder), `CapeHistory`, `EditorSession` (the editor's draft and its Undo), `CursorGallery` (the online gallery and its downloads), `Engine` (the Swift face of the engine plus `EnginePreferences`), `LoginAgent` and `ThemeImport` (archives and folders). `Views/` holds the UI, with the editor under `Views/Editor/`. |
| `TestSupport` | Swift | Builders for test files (PNG, `.cur`, Xcursor), shared by both test targets. |

Key facts:

- **Cape format.** A `.cape` is an XML plist, format version 2.0, type
  `com.alexzielenski.mousecape.cape`. Each cursor has one sprite sheet per scale
  (1x/2x/5x/10x), with frames stacked vertically and frame 0 at the top. New keys are
  optional, at the cape level (`Source`, where a cape was downloaded from) or per cursor
  (`FrameDurations`, the left-handed keys), and `MinimumVersion` stays 2.0, so the
  original Mousecape still opens the files and ignores what it doesn't know. Keeping
  that is good, but no longer a must: the original isn't developed any more, and a new
  feature that needs a break may make one (the user's decision, 2026-11-20). Unknown keys
  must survive a save: they go through `OtherKeys`, at both the cape and the cursor level.
- **Preferences domain.** The engine, the agent and the app all use the
  `com.alexzielenski.Mousecape` domain (`MCAppliedCursor`, `MCCursorScale`,
  `MCHandedness`, …). The engine writes some values per host, so read them with
  CFPreferences, as `EnginePreferences` does.
- **Library.** `~/Library/Application Support/Mousecape/capes/<identifier>.cape`. History
  lives in `…/Mousecape/Versions` (outside `capes/` on purpose). Deleting moves files to
  the Trash. Tests replace `Library.moveToTrash`.
- **Agent.** A plain launch agent at
  `~/Library/LaunchAgents/<bundle id>.listener.plist`, written by `LoginAgent` and loaded
  with `launchctl`. It is deliberately not SMAppService: that pinned the agent to the exact
  build of an app without a team ID. Don't switch it back.
- **Window server limits** shape much of the code. It allows at most 24 frames per cursor
  (`CapeCursor.maximumFrameCount`). Longer animations are reduced at apply time (every
  n-th frame, or by time when `FrameDurations` exists). A reset removes the backups it
  restored (with the global flag, the only one that works across processes), so the next
  apply backs up afresh. Names under `com.apple.coregraphics.` can't be unregistered at
  all, so a variant like `ArrowS` lasts until logout (NOTES.md has the details). On macOS 27,
  `ArrowS`/`IBeamS` shadow `Arrow`/`IBeam`.

## Logic that exists twice

Some rules live in both the Objective-C engine and CapeKit. `Tests/MousecapeTests/EngineAgreementTests.swift`
checks that they agree. If you change one side, change the other in the same commit:

- the identifier rule: `MCIsSafeIdentifier` ↔ `Cape.isValidIdentifier`
- the pointer list for left-handed mirroring: `MCPointerCursorIdentifiers` ↔ `CursorNames.pointers`
- frame choice by time: `MCFramesByTime` ↔ `FrameSelection.byTime`
- core cursors 0 and 1 as the arrow and the I-beam: `MCBaseCursorForCoreAlias` ↔ `CursorNames.coreAliases`
- a cape drawn for the left hand (its arrow's hot spot): `MCHotSpotIsLeftHanded` /
  `MCCapeIsDrawnLeftHanded` ↔ `CapeCursor.pointsLikeLeftHandedArrow` / `Cape.isDrawnLeftHanded`

## Security posture

Capes, themes and archives are untrusted input (see "Hardening" in CHANGES.md):

- Cape and cursor identifiers become file names. Reject anything `isValidIdentifier`
  refuses.
- Check image dimensions from the header before decoding. Use `CursorSheet.decode`,
  which enforces `maximumPixels`, rather than decoding directly. The `.ani` step count and
  the size of PNGs in `.cur` files are also bounded, as is the number of themes taken
  from one archive (`ThemeImport.maximumThemes`).
- Ignore symlinks in themes that point outside the theme folder.
- A save that can't keep the state it replaces must not overwrite anything.
- The online gallery (`PlingCatalog` and `CapeSource` in CapeKit, `CursorGallery` in the
  app) is the only network access. It runs only while its window is open, follows HTTPS links only,
  cleans file names from the catalogue, limits download sizes and checks checksums.
  Send nothing about the user (the User-Agent names only the app and its version).

## Conventions

- Match the existing style: doc comments (`///`) on types and on non-obvious members,
  explaining *why*. Use short, plain English sentences, the same in docs and commit
  messages.
- Wrap user-facing strings in `String(localized:)`.
- Apps and models are `@MainActor @Observable`. CapeKit types are value types and
  `Sendable`.
- Use Swift Testing (`@Test`, `#expect`, parameterized `arguments:`). Put shared file
  builders in `TestSupport`, not in copies.
- Objective-C in `MousecloakCore` uses manual retain/release. Balance retains and
  releases by hand. The target builds without warnings; keep it that way.
- Commit messages follow Conventional Commits (https://www.conventionalcommits.org/),
  with the area as scope: `fix(engine):`, `feat(editor):`, `docs(readme):`,
  `docs(todo):`, `build(release):`. The body explains what and why. When you
  change behaviour, add an entry under `[Unreleased]` in CHANGELOG.md (and update
  README.md if users would notice) in the same commit. CHANGES.md stays the record of
  3.0.0; correct it only where it is wrong. Tick off or add TODO.md items as needed. New findings about macOS go in NOTES.md.

## Things not to do

- Don't commit anything from `Examples/Local/` (ignored by `.gitignore`). Its capes contain
  third-party artwork whose redistribution isn't cleared.
- Keep the licence's non-commercial clause and Alex Zielenski's notice in every
  distribution.
- Don't add x86_64 builds, third-party packages or an Xcode project.
- Behaviour that touches the live window server (apply, reset, agent) can't be checked by
  `swift test`. Say so when a change needs manual testing on a real Mac, and note what was
  tested, or still needs a test, in TESTING.md.
