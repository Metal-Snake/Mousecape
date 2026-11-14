# Fork check

Last check: 2026-11-14

Once a month, the projects related to this fork are checked for work worth taking: the
original Mousecape and its forks, Mousecape-swiftUI and its forks, MaCursor and its forks,
Cursie and macOS27-Cursors. A SessionStart hook in Claude Code (`Scripts/fork-check.sh
hook`, set up in the user's own settings) reminds when the date above is more than a
month old.

## How to check

1. `Scripts/fork-check.sh changed` lists every branch that is new or moved since
   `Scripts/fork-heads.tsv` (repository, branch, old head or `new`). It takes about two
   minutes.
2. For each, read the new commits: `gh api repos/<owner>/<repo>/compare/<old>...<new>`,
   or, for a new fork, `repos/alexzielenski/Mousecape/compare/master...<owner>:<branch>`.
   Most new forks have no commits of their own. Never build or run fork code without
   asking.
3. Worth taking: fixes to the engine (apply, backup, reset, capture, the agent), findings
   about how macOS handles cursors, new cursor names on new macOS versions, importers,
   and hardening against broken files. Not: Xcode project or build changes, Intel builds,
   Sparkle, UI rewrites.
4. Licences: forks of the original are under its licence, so code may be taken with the
   source named. MaCursor is GPL-3.0 and Mousecape-swiftUI has no clear licence: ideas
   only, our own code.
5. Write the findings as TODO.md items (naming the source), update "State" below, set
   "Last check", then `Scripts/fork-check.sh snapshot`, and commit all three files.

## State

As of 2026-11-14:

- **alexzielenski/Mousecape** (the original): no commits after `184f87b`.
- **Forks of the original:** of 273, these have commits of their own:
  - SnowGlow-aww: macOS 26/27 fixes, faster apply, bug fixes. Its findings are in
    TODO.md (MightyMouse bounds, global unregister, backups, display changes, dumps,
    `--create`).
  - Alex-Simedrea: `ArrowS`/`IBeamS` and long animations; nothing new for us.
  - AdamWawrzynkowskiGF/Mousecape-TahoeSupport, branch `TahoeSupport`: finds the arrow's
    and I-beam's names through `CGSCursorNameForSystemCursor`, but also registers the
    arrow as `ArrowCtx` and `IBeamXOR`, which can hold other artwork. Nothing to take.
  - saltjsx: a fallback to `CGSGetRegisteredCursorImages` when capturing fails; capturing
    works here.
  - doctorllll (Windows import), chornthorn (SwiftUI port), MoriMeina and isandrel
    (forks of Mousecape-swiftUI: Windows import, UI): nothing we lack.
  - The rest only change build settings or signing.
- **sdmj76/Mousecape-swiftUI:** no commits since 2026-08-28.
- **kwd421/macOS_Cursie:** since v1.0.10 only its website.
- **Juwan-Hwang/macOS27-Cursors:** v1.0.1 fixes its Windows `.ani` files and Linux alias
  links; `docs/MAPPING.md` unchanged.
- **writronic/MaCursor** (GPL-3.0): v2.8.2, the version analysed for the `.cursor` import
  and the low-priority engine ideas in TODO.md.
- **Forks of MaCursor:** of 11, two have commits of their own: EKIKOUKA (README only) and
  playagain96 (the MD3E Cursors theme, which MaCursor itself now ships).
