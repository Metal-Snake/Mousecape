# Fork check

Last check: 2026-11-25

Once a month, the projects related to this fork are checked for work worth taking: the
original Mousecape and MaCursor with all their forks - forks of forks too, so
Mousecape-swiftUI and its forks are part of the original's - plus Cursie and
macOS27-Cursors. What is watched is set in `Scripts/fork-check.conf`;
`Scripts/fork-check.sh` is generic and comes from the `fork-check` skill (replace it with
a newer copy from there, keep the conf). A SessionStart hook in Claude Code
(`Scripts/fork-check.sh hook`, set up in the user's own settings) reminds when the date
above is more than a month old.

## How to check

1. `Scripts/fork-check.sh changed` lists every branch that is new or moved since
   `Scripts/fork-heads.tsv` (repository, branch, old head or `new`). It takes about two
   minutes. `Scripts/fork-check.sh upstream` lists the pull requests and issues of the
   original, Mousecape-swiftUI and MaCursor opened or updated since the last check.
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

Since 2026-11-28 the check also follows forks of forks. About 19 of them were never
looked at (13 forks of AdamWawrzynkowskiGF/Mousecape-TahoeSupport, four of isandrel's and
MoriMeina's Mousecape-swiftUI, one of Vanyoo/Mousecape); `changed` lists their branches as
`new` at the next check.

As of 2026-11-25:

- **alexzielenski/Mousecape** (the original): no commits after `184f87b`.
- **Forks of the original:** of 276, these have commits of their own:
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
  - pulkitxm (new): the original's branches, unchanged.
  - The rest only change build settings or signing.
- **sdmj76/Mousecape-swiftUI:** a cape per light/dark appearance and cape switching in its
  menu bar extra (both in TODO.md as ideas), Quick Look fixes, a new engine submodule
  (sidebar UI). Forks: CX330-YCH (new) registers animations longer than 24 frames through
  SkyLight's internal IPC call, found by per-build code digests, and reapplies the cape on
  wake (the long animations are in TODO.md, low priority; for wake, our agent reapplies
  on display changes); MicroSharpAnt (new) has nothing of its own.
- **kwd421/macOS_Cursie:** since v1.0.10 only its website.
- **Juwan-Hwang/macOS27-Cursors:** v1.0.1 fixes its Windows `.ani` files and Linux alias
  links; `docs/MAPPING.md` unchanged.
- **writronic/MaCursor** (GPL-3.0): v2.8.2 was analysed for the `.cursor` import and the
  low-priority engine ideas in TODO.md. v2.8.5 adds a clipboard history (nothing for us);
  after it, PR #47 pads cursor frames to 96 × 96 points on a MacBook Neo, where custom
  cursors fall back to the system's (TODO.md, known issues), and the M3E themes moved
  into its gallery.
- **Forks of MaCursor:** of 13, these have commits of their own: EKIKOUKA (README only),
  playagain96 and XDanfr (M3E themes, which MaCursor itself now ships) and gulzxeric
  (PR #47 and its test branch).
