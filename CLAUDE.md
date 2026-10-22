# CLAUDE.md

Mousecape is a cursor manager for macOS 14+, Apple silicon only. This fork keeps Alex Zielenski's Objective-C cursor engine and rewrites everything
around it in Swift/SwiftUI. It uses SwiftPM only: no Xcode project and no third-party
dependencies.

README.md is for users. CHANGES.md records what differs from upstream `184f87b`.
TESTING.md records what has been tested on a real Mac and what still has to be. NOTES.md
holds what is known about how macOS handles cursors. TODO.md holds open work, known issues
and pending decisions. EXAMPLES.md lists where to find capes and themes. Read the relevant
part of these before you change behaviour, and keep them current (see below). They
describe the fork as it is; earlier builds of the fork never left this machine, so don't
document them.

## Commands

```
swift build                       # debug build of all targets
swift test                        # all suites (Swift Testing, not XCTest)
swift test --filter CapeKitTests  # one target; --filter also takes a test name
Scripts/build-app.sh [--zip]      # release build → dist/Mousecape.app (signed, see script header)
MOUSECAPE_LIBRARY=/some/dir …     # point the app at a throwaway library folder
```

The Command Line Tools are enough. String catalogs (`.xcstrings`) can't be compiled
without Xcode, so don't add them.

## Layout and architecture

| Target | Language | Role |
|---|---|---|
| `MousecloakCore` | Objective-C, **manual retain/release** (`-fno-objc-arc`) | The original engine. It applies, backs up, restores and scales cursors through private CGS/CoreCursor calls (`include/CGSInternal`). `MousecloakCore.h` and `module.modulemap` expose it to Swift. |
| `CapeKit` | Pure Swift, no private API | The `.cape` format (`Cape`, `CapeCursor`), sprite sheets (`CursorSheet`), the editing model and validation (`CapeEditing`), diffs, left-handed rules, and the Windows (`Windows/`) and Xcursor (`Xcursor/`) importers. |
| `mousecloak` | Swift | CLI (`main.swift`). `mousecloak --listen` is also the background login agent. |
| `Mousecape` | SwiftUI | The app. `Model/` holds `AppModel` (UI state and actions), `Library` (the capes folder), `CapeHistory`, `Engine` (the Swift face of the engine plus `EnginePreferences`), `LoginAgent` and `ThemeImport` (archives and folders). `Views/` holds the UI, with the editor under `Views/Editor/`. |
| `TestSupport` | Swift | Builders for test files (PNG, `.cur`, Xcursor), shared by both test targets. |

Key facts:

- **Cape format.** A `.cape` is an XML plist, format version 2.0, type
  `com.alexzielenski.mousecape.cape`. Each cursor has one sprite sheet per scale
  (1x/2x/5x/10x), with frames stacked vertically and frame 0 at the top. Original
  Mousecape must still open the files. New keys must be optional per-cursor keys, and
  `MinimumVersion` stays 2.0. Unknown keys must survive a save: they go through
  `OtherKeys`, at both the cape and the cursor level.
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
  n-th frame, or by time when `FrameDurations` exists). Only the process that registered a
  cursor can unregister it, so backups last for the whole login session. On macOS 27,
  `ArrowS`/`IBeamS` shadow `Arrow`/`IBeam`.

## Logic that exists twice

Some rules live in both the Objective-C engine and CapeKit. `Tests/MousecapeTests/EngineAgreementTests.swift`
checks that they agree. If you change one side, change the other in the same commit:

- the identifier rule: `MCIsSafeIdentifier` ↔ `Cape.isValidIdentifier`
- the pointer list for left-handed mirroring: `MCPointerCursorIdentifiers` ↔ `CursorNames.pointers`
- frame choice by time: `MCFramesByTime` ↔ `FrameSelection.byTime`

## Security posture

Capes, themes and archives are untrusted input (see "Hardening" in CHANGES.md):

- Cape and cursor identifiers become file names. Reject anything `isValidIdentifier`
  refuses.
- Check image dimensions from the header before decoding. Use `CursorSheet.decode`,
  which enforces `maximumPixels`, rather than decoding directly. The `.ani` step count and
  the size of PNGs in `.cur` files are also bounded.
- Ignore symlinks in themes that point outside the theme folder.
- A save that can't keep the state it replaces must not overwrite anything.

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
  releases by hand. The target also hides deprecation warnings (a known issue in TODO.md).
- Commit messages have a short imperative subject, sometimes with an area prefix
  (`Engine:`, `Editor:`, `README:`, `TODO:`), and a body explaining what and why. When you
  change behaviour, update CHANGES.md (and README.md if users would notice) in the same
  commit. Tick off or add TODO.md items as needed. New findings about macOS go in NOTES.md.

## Things not to do

- Don't commit anything from `Examples/Local/` (ignored by `.gitignore`). Its capes contain
  third-party artwork whose redistribution isn't cleared.
- Keep the licence's non-commercial clause and Alex Zielenski's notice in every
  distribution.
- Don't add x86_64 builds, third-party packages or an Xcode project.
- Behaviour that touches the live window server (apply, reset, agent) can't be checked by
  `swift test`. Say so when a change needs manual testing on a real Mac, and note what was
  tested, or still needs a test, in TESTING.md.
