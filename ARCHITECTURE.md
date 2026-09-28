# Thuban Planner — architecture contract

Native macOS app (SwiftUI, macOS 15+, Xcode 26, Swift 5 language mode, XcodeGen, ad-hoc signed, no Keychain, no
iCloud, no iOS target). It rebuilds the Atlas **Course Planner** plugin — a degree-route planner: record the semesters
you have taken and the classes in them, list the classes still to take with credits, prerequisites (earlier term),
corequisites (same term or earlier) and summer availability, and the scheduler lays out the fastest (or evenest) route
to graduation under per-term credit caps, with summers you can switch off. Plus a read-only import from Atlas.

Sibling of Thuban Gym / Canvas / Study: same theme engine (Atlas colour schemes, Brass default, auto / light / dark,
custom scheme), typography, component vocabulary, window chrome, smoke harness and scripts. **Atlas is a feature
reference only** — take its rules and wording, never its look. Colours only come from theme tokens.

Three engineers build the UI in parallel from this document without talking to each other:

| Engineer | Owns (create / edit freely) |
|---|---|
| **A — Planner** | `ThubanPlanner/Views/Planner/**` |
| **B — Route map + class detail sheet** | `ThubanPlanner/Views/Route/**`, `ThubanPlanner/Views/ClassDetail/**` |
| **C — Settings** | `ThubanPlanner/Views/Settings/**` (all panes and the settings chrome — `SettingsGroup`, `SettingsRow`, `SettingsNote`, `SettingsPaneHeader`; may be restyled) |

Everything else is **shared and frozen**: `ThubanPlanner/App/**`, `Views/Shell/**`, `Views/Components/**`,
`Views/Theme/**`, `Shared/**`, `Packages/ThubanPlannerCore/Sources/**` (existing files), `project.yml`, `scripts/**`,
`tools/**`. Do not edit shared files — the three branches must merge without conflicts. If you need something more:

- A new helper view → your own folder, prefixed with your area (`PlannerTermChip`, `RouteRibbonLayer`, `SettingsCapField`).
- **Naming — every symbol you add is prefixed or private.** All three areas compile into ONE module, so two branches
  that each add `var coursesByCode` only collide after the merge. Every non-`private` / non-`fileprivate` top-level
  type, function, constant or extension member you add carries your area prefix: types `Planner…` / `Route…` /
  `ClassDetail…` / `Settings…`; members of an `extension AppModel` / `ResolvedTheme` / `View` / core type and free
  functions `planner…` / `route…` / `classDetail…` / `settings…` (`app.routeCoursesByCode`,
  `theme.plannerRowFill`, `.settingsCapFieldStyle()`). Helpers only one file uses → `private` / `fileprivate` (no
  prefix needed). Same for new core files (`RouteLayout`, `routeBoxRects(…)`).
- A new read-only query → an `extension AppModel` in a NEW file in YOUR folder (`Views/Route/AppModel+Route.swift`),
  built from `app.data` / `app.schedule` and the core's public API. Extensions cannot add stored properties; the shared
  UI state you may need is already on `AppModel` (below).
- A new domain rule / pure computation (e.g. the board layout) → a NEW file in the core
  (`Packages/ThubanPlannerCore/Sources/ThubanPlannerCore/<Area>/…`) with tests in a NEW test file
  (`Tests/ThubanPlannerCoreTests/<Area>Tests.swift`). Never change an existing core signature. Never change the
  scheduler (it is proven identical to Atlas's; see "Scheduler").
- A new write → compose the `AppModel` mutations, or `app.mutate { data in … }` with `PlannerData`'s public mutating
  API. Never assign to `app.data` (it is `private(set)`).
- A new icon → `IconName` is shared; use an SF Symbol in your view and leave a `// ICON:` comment with the SVG `d`
  strings you want added by the lead.

## Layout

```
project.yml                 XcodeGen (one macOS target). ThubanPlanner.xcodeproj is generated, NOT committed.
Packages/ThubanPlannerCore/ SwiftPM library + tests (`swift test`)
  Model/     Terms (Season, TermKey helpers, Term), Models (Course, Strategy, PlannerSettings, PlannerSetting, PlannerID),
             PlannerData (the document; tolerant decoding = Atlas loadCourse()), PlannerData+Mutations (Atlas CRUD +
             CoursePatch)
  Schedule/  Schedule (BoardTerm, TermKind, RouteEdge, RequirementKind, CourseStatus), Scheduler (scheduleDegree,
             upcomingSummers, planStatus)
  Support/   JS (JavaScript Number/String/truthiness/Math.round/localeCompare semantics), JSONValue, V8Sort (V8 TimSort)
  Store/     PlannerStore (planner.json, atomic writes, 14 daily backups, 20 labelled snapshots), Preferences,
             AppPaths (THUBAN_PLANNER_HOME), JSONFile
  Import/    AtlasImporter (SQL, ssh command, fetch, convert, ImportSummary), AtlasDocument (tolerant rows +
             recompose), CommandRunner / ProcessRunner (tests use FixtureRunner)
  Sample/    SampleData (a mechanical-engineering degree for smoke / THUBAN_PLANNER_SEED=sample)
  Theme/     Copied from Thuban Gym — ColorScheme, SchemePresets, ThemeSelection, ThemeResolver, ResolvedTheme …
  Tests/     Fixtures/golden-schedule.json (400 cases from Atlas's own scheduler), atlas-psql-output.txt, atlas-legacy.json
Shared/
  Theme/     ThemeEnvironment (tokens → Color, ThubanFont, ThubanMetrics, modifiers, ChipKind)
  Art/       AppArt + AppArtSource (the mark: ~/Desktop/Claude/Thuban Icons/final/planner.svg), Icon (line icons)
ThubanPlanner/
  App/       ThubanPlannerApp (window, menus: New Class ⌘N, Go ⌘1–⌘3, Settings ⌘,, Route ▸ Calculate ⌘R / Fit ⌘0),
             AppModel (+Queries, +Mutations, +Import), Routes (AppSection, SettingsPane, ThubanScheme),
             AppIconRenderer (live dock icon), SmokeHarness, Smoke/SmokeScenes (registry, pre-wired)
  Views/Shell        ShellView: TitleBar (mark + serif "Thuban Planner", StatusChip), SectionBar (SectionTabs + the
                     section's toolbar), content switch, class detail sheet host, load / save error banner
  Views/Components   Buttons, Chip, SegmentedPicker, ToggleChip, EmptyState, ProgressBar, Common (copied from Gym),
                     Fields (`ThubanToggle`, `.thubanField` / `ThubanFieldStyle` — shared by every area)
  Views/Theme        PlannerTheme (term-kind / ribbon / status colour roles shared by A and B)
  Views/Planner      PlannerView, PlannerToolbar, PlannerSmokeScenes                              (A)
  Views/Route        RouteView, RouteToolbar, RouteSmokeScenes                                    (B)
  Views/ClassDetail  ClassDetailSheet, ClassDetailSmokeScenes                                     (B)
  Views/Settings     SettingsView (nav), SettingsToolbar, SettingsChrome, SettingsPaneHeader, PlanningSettings,
                     AppearanceSettings (working), ImportSettings, DataSettings, AboutSettings, SettingsSmokeScenes (C)
  Resources          Assets.xcassets (AppIcon from scripts/make_app_icon.sh), entitlements (no sandbox)
scripts/   build.sh, test.sh, smoke.sh, install.sh, regen.sh, make_app_icon.sh(+.swift), golden.sh, v8check.sh
tools/golden/  gen.mjs + atlas-course.js (Atlas's course.js, unmodified) + v8sort.js + sortcheck.mjs + v8trace.mjs (V8-only check)
```

Each placeholder (`PlannerView`, `RouteToolbar`, `ClassDetailSheet`, `PlanningSettings`, …) carries a TODO. Replace
the body; keep the type name (and `ClassDetailSheet(courseId:)`), since the shell references it. Split into as many
files as you like inside your folder.

## Data

`PlannerData` is ONE Codable value: `~/Library/Application Support/Thuban Planner/planner.json` (or
`$THUBAN_PLANNER_HOME/planner.json`). Same model as Atlas's `atlas.course.v1`:

- `Course {id, code, title, credits (Double ≥ 0), prereqs [code], coreqs [code], summerOk, term: String?}` —
  `term` = the recorded term key it was taken in; nil = still to take. Requirements are CODES, matched to classes
  case- and space-insensitively (the LAST class with a code wins); unknown codes are ignored by the scheduler.
  Codes are not unique. `coreqs` absorbs Atlas's retired "pre-or-co" bucket.
- `Term {key "fall-2025", season spring|summer|fall, year, current}` — at most one current; sorted by rank.
- `disabledTerms [key]` — terms the scheduler skips (usually summers; may name terms with no Term row).
- `settings {maxCredits (default 15), summerMax (default min(9, max)), strategy}` — strategies (Atlas labels):
  `soonest-summer` "Graduate soonest (use summers)", `soonest-optional-summer` "Soonest — summers only if they save a
  term", `even` "Lighter, even load".
- `importedAt`, `importSource` — provenance of an Atlas import.

Decoding is tolerant and applies Atlas's `loadCourse()` normalization exactly (JS coercions included); `AppModel`
re-normalizes after every write, exactly like Atlas reloads after every save — e.g. setting max credits to 0 snaps
back to 15. `PlannerStore` writes atomically (0600), makes a daily backup before the first write of a day (14 kept)
and labelled snapshots before an import / restore (20 kept) in `backups/`. `preferences.json` (theme, text size, Atlas
host / email, last section, `importOffered`) is separate and never touched by an import. Atlas keeps duplicate course
ids; the importer re-mints them (with a warning) because this app keys rows by id. Atlas's scheduler identifies
classes by id (rows sharing one share "done" state), so re-minting can change the route: the importer schedules both
ways and, when they differ, adds a warning saying how ("…finishes Summer 2026 in 2 more terms instead of Spring 2026
in 1 more term").

### Scheduler (core, frozen)

`Scheduler.scheduleDegree(data, now:, calendar:) → Schedule {board, edges, unplaceable, warnings, termsToFinish,
gradTerm}` is Atlas's greedy critical-path packer ported line for line: walk terms forward from the last recorded term
(or the calendar term containing `now` when none is recorded); in each, fill up to the cap (fall / spring `maxCredits`,
summer `summerMax`, `Math.round`ed) with eligible classes ordered by downstream depth desc, credits desc, code
`localeCompare`; a class drags its unmet to-take coreqs in as one atomic group; prerequisites must be in an EARLIER
term; summer takes only `summerOk` groups; disabled terms are skipped; 60-term guard; cycle-safe. Strategies: soonest;
optional summer = with summers only if the finish rank is strictly earlier; even = the same number of terms with cap ×
min(1, ceil(total / terms) / max), falling back to full caps (or to summers) rather than failing. Board = recorded terms
(past / current, incl. empty ones) + planned terms, chronological; edges only between placed classes; warning text
"Couldn't place: A, B — check for missing prerequisites or a prerequisite cycle."

It is PROVEN identical to Atlas: `GoldenScheduleTests` replays 400 seeded random plans (cycles, lecture ↔ lab coreq
loops, duplicate codes / ids, unknown refs, 0- and 15-credit classes, summer cap 0, disabled terms, no terms, > 64
classes, all strategies) produced by running Atlas's own `course.js` under JavaScriptCore (`scripts/golden.sh`), and
compares board, edges, unplaceable, warnings, termsToFinish, gradTerm, `upcomingSummers` and `planStatus`. Two
fidelity details: the class sort is V8's TimSort (`V8Sort`) because Atlas's comparator memoizes depths lazily and in a
requirement cycle the result depends on the comparator call order (a plain stable sort differs in half the cases);
codes compare with `JS.localeCompare`, an exact ICU-root table for printable ASCII (checked against JavaScriptCore;
non-ASCII goes to ICU itself — `ICUCollator`, libicucore loaded with dlopen — because Foundation's compare ties
"ﬁn"/"fin" and "φυς"/"φυσ").

`DifferentialParityTests` goes further: it runs Atlas's own JavaScript IN-PROCESS (JavaScriptCore; fixtures
`atlas-course.js`, `atlas-course-backend.js`, `v8sort.js`, byte-for-byte copies loaded by `AtlasJSHarness`) on 3,200
seeded documents — 2,400 realistic plans (0–90 classes, DAG / cyclic, unknown refs, duplicate codes and ids, ref case /
white-space variants, 0 / fractional / heavy credits, numeric-string and tiny caps, all strategies, 16 fixed local
"now"s at month edges) and 800 hostile documents (every field of every JSON kind) — through decompose → Postgres →
recompose → `loadCourse` → `scheduleDegree` / `upcomingSummers` / `planStatus`, and diffs the normalized document and
every output field against `PlannerData(json:)` + `Scheduler`. Where comparator call order cannot matter it also
re-runs Atlas under JavaScriptCore's native sort as an independent check of the V8 sort port.
`JSSemanticsParityTests` checks the primitives exhaustively against the engine: number → string (20k+ doubles),
`Number(string)`, `trim` and `toLowerCase` for every BMP code point, `localeCompare` (all ASCII pairs + 8k strings).
Rules this pinned down: JS white space is ECMA-262's set (not Foundation's, which also strips NEL / U+200B);
`toLowerCase` keeps Greek final sigma; numbers print like `Number::toString` ("0.000001", "123456789012345680000",
"1e-7"); ids / codes / term keys are compared as code units (`JSKey`), not by Swift's canonical equivalence;
`currentTermKey` is always Gregorian.

## Data flow — how a view reads and writes

`AppModel` (`@MainActor @Observable`) is injected at the root: `@Environment(AppModel.self) private var app`; the theme
with `@Environment(\.thubanTheme) private var theme`. Views are pure functions of `app`; `app.schedule` is recomputed
synchronously on every change (a degree is tiny — well under a millisecond), so never cache it. Every mutation saves
immediately (atomic); there is no "save". Text fields keep a local `@State` draft and commit on submit / focus loss
(one write, not one per keystroke); number fields likewise. Bindings: `Binding(get: { app.settings.maxCredits },
set: { app.setMaxCredits($0) })`.

### Reads (`App/AppModel.swift`, `App/AppModel+Queries.swift`)

| API | Returns |
|---|---|
| `app.data`, `app.schedule`, `app.now`, `app.isLoaded`, `app.isFirstRun`, `app.loadError`, `app.saveError` | raw state |
| `app.courses`, `app.terms`, `app.settings`, `app.currentTerm`, `app.toTake`, `app.taken`, `app.disabledTerms` | plan |
| `app.course(id)`, `app.term(key)`, `app.courses(inTerm: key)`, `app.isDisabled(key)` | lookups |
| `app.creditsToTake`, `app.creditsTaken`, `app.creditsTotal` | Double |
| `app.course(forRef: "math 1241")` | the class a code names (nil = unknown) |
| `app.requirements(of: course)` | `[ResolvedRequirement {ref, kind .prereq/.coreq, course?}]` (prereqs then coreqs) |
| `app.dependents(of: course)` | `[(course, kind)]` — "Required by" |
| `app.unknownRefs` | codes that match no class |
| `app.planStatus` | "14 to take · 40 credits · 3 more terms · finishes Spring 2028" (Atlas wording) |
| `app.warnings`, `app.gradTermLabel` | scheduler warnings; "Spring 2028" |
| `app.status(of: id)` | `CourseStatus` `.taken(key)` / `.inProgress(key)` / `.planned(key)` / `.unplaceable` / `.unscheduled` |
| `app.routeTerm(of: id)` | the `BoardTerm` holding a class |
| `app.upcomingSummers` | summer keys for the toggles (Atlas `upcomingSummers`: next 5 incl. switched-off ones) |
| `app.calendarTermKey` | term containing today ("fall-2026") — defaults for the Add-semester form |
| `app.creditsText(3.0)` → "3", `app.termLabel("fall-2025")` → "Fall 2025" | text |
| `app.schedule.board` / `.columns` (non-empty terms, what the map draws) / `.plannedTerms` / `.edges` / `.edges(into:)` / `.edges(outOf:)` / `.unplaceable` / `.termsToFinish` / `.gradTerm` | route |
| `BoardTerm {key, season, year, current, kind .past/.current/.future, courseIds, credits, label}` | a column |
| `TermKey.make/parse/label/rank/next/previous/current/season`, `Season.label`, `Strategy.label`, `Course.displayCode/displayName` | helpers |

### Writes (`App/AppModel+Mutations.swift`)

- Semesters: `addTerm(season:year:current:) -> Term?` (existing key returned unchanged), `setCurrentTerm(key)`,
  `removeTerm(key)` (its classes go back to "To take"), `toggleDisabledTerm(key)`.
- Classes: `addCourse(code: "", title: "New class", credits: 3, …) -> Course?` (selects it and sets
  `editRequestCourseId`), `updateCourse(id, CoursePatch(code:title:credits:prereqs:coreqs:summerOk:term:))`
  (`term: .some(nil)` = To take), `setTerm(of:to:)`, `setPrereqs(of:text:)` / `setCoreqs(of:text:)` (comma-separated),
  `removeCourse(id)`.
- Planning: `setMaxCredits(_:)`, `setSummerMax(_:)`, `setStrategy(_:)`.
- Theme / preferences: `app.preferences.x = …` (auto-saved), `setAppearanceMode`, `selectScheme(id:)`,
  `setThemeSelection`.
- Escape hatch: `app.mutate { data in … }` (any `PlannerData` public mutating API; normalized, recomputed, saved once).

### Navigation and shared UI state

`app.section` (.planner / .route / .settings; ⌘1–⌘3), `app.openSettings(.importAtlas)` (⌘, opens the last pane;
`app.settingsPane` is the selected pane), `app.showRoute()` ("Calculate route": fits and switches to Route; ⌘R),
`app.presentCourse(id)` / `app.presentedCourseId` (class detail sheet, hosted by the shell). Shared between a section
and its toolbar: `app.selectedCourseId` (Planner selection; Route highlights it), `app.editRequestCourseId` (a row
starts editing, then clears it), `app.routeZoom` (1 = fitted), `app.routeFitRequest` (bump to re-fit; ⌘0). Everything
else is local `@State`. Toolbars may own their popovers (e.g. "+ Semester").

### Import and data (`App/AppModel+Import.swift`, core `Import/`)

`app.importPhase`: `.idle → .fetching → .preview(ImportPreview) → .applying → .done(summary, backup:)` or
`.failed(message)`. Calls: `fetchAtlasPreview()` (ssh, read-only), `loadImportFile(url)` / `chooseImportFile()`,
`applyImport()` (snapshot "before-import", then replace), `cancelImport()`. `ImportPreview {summary, data, source,
replacesExisting, localCourses, localTerms}`; `ImportSummary {email, courses, taken, toTake, creditsTaken,
creditsToTake, terms, termLabels, currentTerm, disabledTerms, settings, unknownRefs, gradTerm, termsToFinish,
warnings}`. When `replacesExisting`, confirm before `applyImport()`. First run: `app.shouldOfferImport` (no file at
launch, nothing entered, not answered) → offer it; `app.dismissImportOffer()` records the answer. Host / email:
`app.preferences.atlasHost` / `.atlasEmail` (defaults "beelink" / the user's address); `app.atlasImporter.
commandDescription` shows the command. Data: `app.dataFolder`, `revealDataFolder()`, `backups()`, `restoreBackup(url)`
(confirm first), `exportData(to:)`.

The importer runs `/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=10 <host> docker exec -i stack-postgres-1 psql -U
atlas_user -d atlas -At` and feeds `AtlasImporter.sql(email:)` on stdin: `BEGIN TRANSACTION READ ONLY`, ONE
SELECT building a JSON document from `course.settings / terms / courses` for that `auth.users.email`, `ROLLBACK`. The
rows are recomposed into Atlas's blob and normalized like `loadCourse()` / the backend mapper's `decompose()`. A file
saved from plain psql output may carry Postgres TEXT forms; `AtlasDocument.recomposed` turns `text[]` literals
(`{a,"b c",NULL}`) into arrays and `t` / `f` into booleans first, and the importer warns about requirement lists or
switched-off terms it still cannot read.
NEVER add anything that writes to Atlas. Tests use `FixtureRunner`. Never run the import against the live Beelink from
a build / smoke / test script.

## Design rules

Quiet, precise, native; consistent with Gym and Canvas. Colours ONLY from `theme` (never a hex or `Color.red` in a
view): `bgColor`, `panelColor`, `panel2Color`, `lineColor`, `line2Color`, `inkColor` / `inkDimColor` / `inkFaintColor`,
`accentColor` (primary fills), `brassInkColor` (accent as text / icon), `accentTintColor` (selected fill),
`onAccentColor`, `signal*` (current / live), `pos*` (taken / done), `neg*` (can't place, errors), `warnSoftColor`.
Planner roles for terms, ribbons and statuses are in `Views/Theme/PlannerTheme.swift` (`theme.termFill(kind)`,
`termInk`, `termBorder`, `termCaption(boardTerm)`, `ribbonColor(kind)`, `ribbonStyle(kind, scale:)`,
`statusChip(status)`) — use them so A and B match. Dark mode is automatic; check the `-dark` screenshots.

- Fonts: `ThubanFont.display(size)` (serif: page titles 32, class codes in the sheet 28, big numbers 30),
  `ThubanFont.body(size, weight:)` (15 body, 14 secondary, 13 small), `ThubanFont.micro` / `Eyebrow` (12 pt uppercase),
  `ThubanFont.mono(13)` for codes / credits in tables; `.monospacedDigit()` on numbers. Scale dense text by
  `@Environment(\.thubanTextScale)`.
- Metrics (`ThubanMetrics`): cards radius 10, controls 8, chips 6, title bar 52, section bar 50, buttons 36 (toolbar
  32). 1 px hairlines, no shadows, no gradients, no emoji. Page padding 24–28.
- Icons: `Icon(.planner / .route / .settings / .graduation / .sun / .fit / .zoomIn / .zoomOut / .arrowRight / .edit /
  .plus / .check / .close / .trash / .dragHandle / .history / .file / .download / .info / .calendar / .archive /
  .sliders / .more / .clock / .search / .chevronDown …, size:)`; `Glyph(.chevronRight …)`; app mark `AppArtView`.
- Components: `.thubanPrimary` / `.thubanSecondary` / `.thubanGhost` buttons, `IconButton`, `ToolbarButton(label,
  icon:, kind:)` + `ToolbarDivider`, `Chip(text, kind:, dot:)`, `SegmentedPicker`, `ToggleChip`, `EmptyState`,
  `SectionPlaceholder`, `ProgressBar(value:)`, `Eyebrow`, `SectionHeader`, `PageHeader(eyebrow:title:subtitle:)`,
  `StatTile`, `ListRowCard`, `Hairline`, `SearchField`, `ImportFromAtlasButton`, modifiers `.thubanPanel`,
  `.thubanHairline`, `.thubanChip`, `.thubanField(invalid:mono:height:)`, `ThubanToggle(isOn:label:)` (these two are
  in `Views/Components/Fields.swift` — frozen, so A can use them in the class table and "+ Semester" popover without
  depending on C's folder). Settings chrome (C's, may change — other areas must not use it): `SettingsPaneHeader`,
  `SettingsGroup`, `SettingsRow`, `SettingsNote`.
- Every control has an accessibility label; lists are keyboard-navigable; hit targets ≥ 28 pt; nothing reflows
  when a value changes (fixed column widths, monospaced digits).

## Screens

### Planner (A) — `Views/Planner`

The working surface: what you've taken, what's left, and a one-line answer to "when do I finish?".

- **Toolbar** (right of the section tabs): `+ Semester` (ghost, `.calendar`; popover: Season segmented picker, Year
  stepper field defaulting from `app.calendarTermKey`, "This is my current semester" toggle, Add) · `Add class`
  (secondary, `.plus`; `app.addCourse()`, the new row scrolls into view and its Code field takes focus) |
  `Calculate route` (primary, `.route`; `app.showRoute()`).
- **Header**: eyebrow "PLANNER", serif title "Your degree", subtitle `app.planStatus`. Right: three `StatTile`s —
  "Credits done" (`creditsTaken` of `creditsTotal`, `ProgressBar`), "To take" (`toTake.count` classes · credits),
  "Finishes" (`gradTermLabel`, caption "N more terms").
- **Warnings**: each `app.warnings` line as a `negSoft` banner card with "Show on route"; unknown refs as a quiet
  `warnSoft` note ("STAT 3128 isn't in your plan, so it's ignored").
- **Semesters** group (caption "Your past & current terms — the classes you've taken."): a wrapping row of term chips
  in rank order — label, credits taken in it, a signal dot + "Current" on the current one; a menu per chip: "Mark as
  current", "Remove semester…" (confirm when it has classes: "Its N classes go back to To take"). Empty: "No
  semesters yet — add your past and current terms."
- **Summer terms** group (only when `app.upcomingSummers` is non-empty; caption "Switch a summer off (internship,
  travel) to keep the planner out of it."): one `ToggleChip` per key with `.sun`, on = planned, off = disabled
  (`toggleDisabledTerm`).
- **Classes**: a native table-like list (fixed columns): Code (mono, editable), Title (editable), Cr (numeric field),
  Prerequisites and Corequisites (comma-separated fields; each ref that resolves shows as a small chip, an unknown one
  in `inkFaint` italic), Summer (checkbox "Offered in summer"), Term (menu: "To take" + every recorded term), Route
  status chip (`theme.statusChip(app.status(of:))`), and a trailing remove button (confirm). Grouping: segmented filter
  "All · To take · Taken" (local state); sort by term then code. Clicking the status chip / double-clicking a row
  opens the class detail sheet. Keyboard: ↑↓ selects (`app.selectedCourseId`), Return edits, ⌫ removes (confirm).
- **Empty / first run**: `EmptyState(.planner, "Plan your degree", "Add the semesters you've taken and the classes
  left, and Thuban Planner lays out the fastest route to graduation.")` with `Add class` and, when
  `app.shouldOfferImport`, `ImportFromAtlasButton` + "Not now" (`dismissImportOffer()`).

### Route (B) — `Views/Route`

A zoomable Sankey-style board of the route (Atlas's "Map"), drawn natively in a `Canvas` (or shapes) — not Atlas's SVG.

- **Toolbar**: legend chips (Taken · Current · Planned; prereq solid ribbon, coreq dashed) | zoom − / + (`.zoomOut` /
  `.zoomIn`, 0.25–2.5×) · `Fit` (`.fit`, ⌘0).
- **Header strip** above the board: serif "Finishing Spring 2028" (or "Your route"), `app.planStatus`, warnings.
- **Columns** = `app.schedule.columns` in order (terms with classes only), fixed column width ~210 pt with a gutter;
  header per column: term label (serif 16) and `theme.termCaption(term)` ("15 cr · planned"). Column background:
  past `panel2`, current `signalSoft` with a `signal` hairline, future `panel` with `line2`; disabled summers never
  appear (they have no classes).
- **Boxes**: one per class, stacked top-down in `courseIds` order; height ∝ credits (≈24 pt per credit, min 42), gap
  14, radius 7; code (mono semibold), title (clipped, 1 line), credits right-aligned. Fill / ink by term kind (past
  muted, current signal, future panel with an accent credit badge); selected (`app.selectedCourseId`) / hovered gets
  `accentTint` + `accent` border, and its incoming / outgoing ribbons are emphasized while the rest dim to 25 %.
- **Ribbons**: `app.schedule.edges`, from the source box's right edge (vertical middle) to the target's left edge, as a
  cubic bezier with both control points at the horizontal midpoint (Atlas's `M x1,y1 C mx,y1 mx,y2 x2,y2`); prereq =
  `ribbonColor(.prereq)` solid 2 pt, coreq = `ribbonColor(.coreq)` dashed 1.5 pt (`ribbonStyle`). Drawn beneath boxes.
- **Zoom / pan**: pinch (`MagnifyGesture`) and ⌘-scroll zoom around the pointer, scroll / drag pans; `Fit` and
  `app.routeFitRequest` changes animate back to the whole board; `app.routeZoom` mirrors the level. Put the pure
  layout (box rects, ribbon endpoints, board size from a `Schedule` + courses) in a NEW core file with tests.
- **Click** a box → `app.presentCourse(id)` (class detail sheet); hover shows a tooltip "MEGR 3114 · Fluid Mechanics ·
  3 cr · planned Spring 2027".
- **Empty**: `EmptyState(.route, "No route yet", "Add classes on the Planner — the route draws here.")` with a
  button to the Planner. Unplaceable classes: a strip under the board listing them as `neg` chips (click → sheet).

### Class detail sheet (B) — `Views/ClassDetail`

Sheet ~560 × 480: eyebrow with the route status chip, serif code (28) + credits, title; two columns
"Prerequisites (earlier term)" and "Corequisites (same term or earlier)" listing `app.requirements(of:)` — each
resolved ref as a row (code, title, its status chip; click → show that class), unknown refs "not in your plan"; below,
"Required by" (`app.dependents(of:)`). Facts row: offered in summer yes/no, taken in / planned for. Footer: "Edit in
Planner" (switches to Planner, selects the row, dismisses) and Done (default). Esc closes.

### Settings (C) — `Views/Settings` (section ⌘3 / ⌘,)

Pane list on the left (Planning, Appearance, Import, Data, About), pane on the right (`app.settingsPane`).

- **Planning**: "Max credits per semester" (numeric field 1–30, "The most credit hours the planner will pack into a
  fall or spring term."), "Max credits in summer" (0–30, "Summers usually carry a lighter cap."), "Route strategy"
  (three selectable rows with Atlas's labels, a one-line explanation each, and a live preview "With this: finishes
  Spring 2028 · 3 more terms" computed with `Scheduler.scheduleDegree` on a copy). Commit on submit / blur.
- **Appearance**: working copy from Gym (mode, eight schemes, text size, preview). Keep.
- **Import**: header "Bring your plan over from Atlas" / "Read-only: Atlas is never changed."; host + email fields,
  the exact command (`app.atlasImporter.commandDescription`, mono, selectable); `Check Atlas` (primary) →
  fetching (progress + Cancel) → preview card (counts: classes taken / to take with credits, semesters with the
  current one, switched-off terms, settings, unknown refs, "Finishes …", warnings) → `Replace my plan` (confirm when
  `replacesExisting`: "This replaces 43 classes and 5 semesters. A backup is made first.") → done card (backup path,
  "Open Planner"); failed card with the message and Try again. Secondary: "Import a file…" (`chooseImportFile`).
- **Data**: planner.json location (Reveal in Finder), last saved, backups list (label, date, size; Restore… with
  confirm), Export… (save panel → `exportData`).
- **About**: mark, "Thuban Planner", version, one paragraph on what it does, where data lives, the Atlas rule.

## Smoke screenshots

`SmokeHarness` seeds `SampleData` into a temp home (43 classes of a mechanical-engineering degree, fall 2024 → current
fall 2026, summer 2027 switched off, route to Spring 2028), sizes the window to 1440 × 900, then captures `10-planner`,
`11-route`, `12-settings`, every registered scene (`30+`), `900-planner-dark`, `901-route-dark`, and every Settings pane
(`950-settings-…`; these sit above the scene range so scene numbers never collide). Register extra states in YOUR area's file — the registry line
`SmokeScenes.all = planner + route + classDetail + settings` is pre-wired and frozen:

```swift
extension SmokeScenes {                       // Views/Route/RouteSmokeScenes.swift
    static var route: [SmokeScene] {
        [SmokeScene(name: "route-zoomed") { app in app.section = .route; app.routeZoom = 2 }
                    cleanup: { app in app.routeZoom = 1; app.routeFitRequest += 1 }]
    }
}
```

`window: .main` (default) or `.sheet` (the class detail sheet: `app.presentCourse("c-sample-31")`); `settle:` seconds.
The empty / first-run Planner (with the import offer) — `isFirstRun` is `private(set)` and a smoke run seeds sample
data, so use the smoke-only setter:

```swift
SmokeScene(name: "planner-first-run") { app in
    app.section = .planner
    app.replaceData(.empty); app.smokeSetFirstRun(true); app.preferences.importOffered = false
} cleanup: { app in app.replaceData(SampleData.make(now: app.now, calendar: app.calendar)) }
```

Always undo state in `cleanup`. Look at your PNGs (Read tool) before you finish. Sample ids are `c-sample-01 … 43`
(01–29 taken, 30–43 to take; 38 = Senior Design II, the last class).

## Build / test / smoke

- `DERIVED=.build/DerivedData-<you> scripts/build.sh` — ALWAYS a private DerivedData, run from your own worktree
  (see Git). Regenerates the project first.
- `scripts/test.sh` — core tests (`swift test`, 110 tests incl. 400 golden cases and the 3,200-case differential run against Atlas's JS). Add tests for core logic you add.
- `scripts/golden.sh` — regenerates the golden cases from Atlas's own scheduler (macOS JavaScriptCore; no Node).
- `scripts/v8check.sh` — needs a real V8 (`node` / `deno`, or `V8_NODE=<Electron binary>`): checks the V8 sort port's
  comparator call order against V8's own sort and regenerates the golden cases on V8's own sort, diffing them with the
  committed file. Exits 2 when no V8 is installed (none is on the lead's Mac today; JavaScriptCore's native sort
  independently confirms the port only where call order cannot matter).
- `DERIVED=.build/DerivedData-<you> scripts/smoke.sh .build/smoke-<you>` — builds, runs the smoke walk on a temp home
  (never your real data, never ssh), writes PNGs. It only stops the process it launched.
- `scripts/install.sh` — Release → `/Applications/Thuban Planner.app` (lead only, after merging).
- `scripts/make_app_icon.sh` — regenerates the static AppIcon from `Shared/Art/AppArtSource.swift`.
- Manual run on sample data: `THUBAN_PLANNER_HOME=/tmp/planner-demo THUBAN_PLANNER_SEED=sample "<app>/Contents/MacOS/Thuban Planner"`.

Git — **one git worktree per engineer** (a checkout holds one branch, and `scripts/build.sh` regenerates
`ThubanPlanner.xcodeproj` in whatever directory it runs from, so sharing the main checkout would clobber branches and
the project):

```sh
cd ~/Desktop/Claude/"Thuban Planner"
git worktree add .claude/worktrees/planner -b planner main   # A (route / settings for B / C)
cd .claude/worktrees/planner
DERIVED=.build/DerivedData-planner scripts/build.sh          # run every script from YOUR worktree
```

`.claude/worktrees/` and `.build/` are gitignored; each worktree has its own `.build/` and generated project. Never
check out another branch in the main checkout. Small commits on your branch, messages ending with
`Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not merge to main and do not install.
