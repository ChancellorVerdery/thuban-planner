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
  Registration/ Schedule tab core: BannerTerms (term codes ↔ keys, course-code parsing), BannerSections (sections,
             meetings, conflicts, clock), BannerPage (meta tags, sign-in-redirect / HTML detection),
             BannerRequestGuard (allow / deny lists, BannerExportAuthorization, content rules, page fence),
             BannerPlan (Plan Ahead bootstraps parser), BannerPlanExport (export items, name, request bodies,
             responses, verification, BannerPlanPageInfo), BannerClient (public class search over
             URLSession), Timetable (generator, sorts incl. multi-criteria), TimetableRatings (professor-rating sort
             input), TimetableStore (schedule.json + schedule-cache.json)
  RateMyProfessors/ RMPModels (UNCC school pages, RMPTeacher, RMPRating, RMPMatch), RMPNames (Banner name parsing),
             RMPMatcher (+ RMPDepartments), RMPClient (+ RMPRequestGuard, transport, response decoding), RMPCache
             (rmp-cache.json)
  Store/     PlannerStore (planner.json, atomic writes, 14 daily backups, 20 labelled snapshots), Preferences,
             AppPaths (THUBAN_PLANNER_HOME), JSONFile
  Import/    AtlasImporter (SQL, ssh command, fetch, convert, ImportSummary), AtlasDocument (tolerant rows +
             recompose), CommandRunner / ProcessRunner (tests use FixtureRunner)
  Catalog/   UNC Charlotte catalog data: CatalogDataset (bundled program + elective list + course requirements),
             CatalogRequirementParser (+ CourseCode: normalize, equivalents), RequirementChainResolver (missing
             prerequisite closure, OR-choices), TechElectives (statuses, progress, apply / removal, tags),
             CourseOfferings + OfferingsStore (offerings-cache.json), OfferingsFetcher (Banner subject searches)
  DegreeImport/ DegreeDocumentText (PDF / HTML / MHTML / DOCX / text → lines), DegreeDocumentParser (catalog page,
             DegreeWorks audit, checksheet), DegreeImportMerge (add-only plan + apply)
  Resources/ uncc-bsme-2025-26.json (tools/catalog), uncc-offerings-snapshot.json (Banner, 2026-10-05)
  Sample/    SampleData (a mechanical-engineering degree for smoke / THUBAN_PLANNER_SEED=sample), BSMESampleData (a
             fictional UNCC BSME 2025-26 student, real codes — electives / import scenes and tests), BannerSampleData
             (deterministic terms / sections, fictional instructors, for the offline Schedule smoke scenes), RMPSampleData
             (fictional RMP profiles for those instructors)
  Theme/     Copied from Thuban Gym — ColorScheme, SchemePresets, ThemeSelection, ThemeResolver, ResolvedTheme …
  Tests/     Fixtures/golden-schedule.json (400 cases from Atlas's own scheduler), atlas-psql-output.txt, atlas-legacy.json,
             banner/ (real getTerms / searchResults / linkedSections captures, a reconstructed plan, the term page head)
Shared/
  Theme/     ThemeEnvironment (tokens → Color, ThubanFont, ThubanMetrics, modifiers, ChipKind)
  Art/       AppArt + AppArtSource (the mark: ~/Desktop/Claude/Thuban Icons/final/planner.svg), Icon (line icons)
ThubanPlanner/
  App/       ThubanPlannerApp (window, menus: New Class ⌘N, Technical Electives… ⇧⌘T, Import Degree Requirements… ⇧⌘I, Go ⌘1–⌘4, Settings ⌘,, Route ▸ Calculate ⌘R / Fit ⌘0,
             Schedule ▸ Previous / Next ⌘[ ⌘], Block Times ⌘B, Copy CRNs ⇧⌘C, Export to Banner… ⇧⌘E, Refresh
             Sections ⇧⌘R), Schedule/ (ScheduleModel — the tab's own @Observable model, `app.scheduleTab`;
             ScheduleModel+Export — sign-in state and the export flow; BannerWebSession — WebKit store, guards,
             BannerPlanExporter),
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
  Views/Schedule     ScheduleView, ScheduleToolbar, ScheduleSidebar, ScheduleCourseCard, ScheduleWeekGrid,
                     ScheduleClassDetailSheet, ScheduleRatingCard, ScheduleSortControl, ScheduleSignInSheet,
                     ScheduleExportSheet,
                     ScheduleTheme (course colours), ScheduleSmokeScenes
  App/DegreeTools    DegreeToolsModel (`app.degreeTools`: dataset, offerings, the two sheets' state and writes)
  Views/Electives    ElectivesSheet (list, progress), ElectivesConfirmView (chain tree, OR pickers, remove), smoke scenes
  Views/DegreeImport DegreeImportSheet (choose / preview / done)
  Views/Settings     SettingsView (nav), SettingsToolbar, SettingsChrome, SettingsPaneHeader, PlanningSettings,
                     AppearanceSettings (working), ImportSettings, DataSettings, AboutSettings, SettingsSmokeScenes (C)
  Resources          Assets.xcassets (AppIcon from scripts/make_app_icon.sh), entitlements (no sandbox)
scripts/   build.sh, test.sh, smoke.sh, install.sh, regen.sh, make_app_icon.sh(+.swift), golden.sh, v8check.sh,
           refresh_catalog.sh (catalog dataset via headless Chromium; `--offerings` for the Banner snapshot)
tools/catalog/ fetch.py (Playwright's chrome-headless-shell, page cache), refresh_catalog.py (crawler), reqparse.py
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
  term", `even` "Lighter, even load". Thuban-only: `minCredits` and `summerMin` (default 0 = off; Atlas data always
  loads them as 0) — see "Minimum credits".
- `importedAt`, `importSource` — provenance of an Atlas import.
- `Course.tags: [String]?` (Thuban-only, 2026-10-05): "tech-elective", "prereq:PHYS 4242", "program:Minor in
  Mathematics". nil by default and for every Atlas document (decoded only from an array of strings; empty → nil), so
  the encoded document and every parity / golden test are unchanged; the scheduler never reads it.

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

**Minimum credits (Thuban-only, 2026-09-30).** With `minCredits` / `summerMin` at 0 every line above holds unchanged
(the parity tests assert Atlas documents load both as 0). Otherwise, with each minimum clamped to its cap
(`PlannerSettings.effectiveMin`): a planned summer that would carry fewer than `summerMin` credits is skipped (its
classes wait); the even strategy's lighter cap never drops below `minCredits`; after packing, `MinimumBalancer` lifts
fall / spring terms under `minCredits` by moving classes LATER from earlier planned terms when every requirement
still holds (prereq users stay strictly later, coreq users same-or-later, target within `maxCredits`, source keeps its
own minimum) — never adding or removing terms, so the finish term never moves; terms still short get the warning
"Fall 2027 has 9 credits — under your 12-credit minimum. Add an elective or lower the minimum."
Tests: `MinimumCreditsTests`.

**Transfer column (Thuban-only post-step, 2026-10-05).** `Scheduler.withTransferColumn(schedule, data)` runs AFTER
`scheduleDegree` (AppModel: `schedule = withTransferColumn(scheduleDegree(data), data)`): it prepends a `BoardTerm`
{key "transfer", kind `.transfer`, label "Transfer credit"} with every transfer class (document order, credits summed)
and APPENDS ribbons that start at a transfer class and end at any placed class (incl. a same-column coreq), resolved
with the scheduler's rules. Ribbons INTO a transfer class from a semester would run backwards and are not drawn.
Atlas's board (after the column), edges (as a prefix), unplaceable, warnings, termsToFinish, gradTerm and planStatus
are untouched; no transfer class → the schedule is returned unchanged, so no Atlas document ever gets the column.
`Schedule.status` → `CourseStatus.transfer` (termKey "transfer"); `Schedule.transferColumn`.

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
| `BoardTerm {key, season, year, current, kind .past/.current/.future/.transfer, courseIds, credits, label}` | a column |
| `app.transferCourses`, `app.transferCredits`, `app.schedule.transferColumn` | transfer credit |
| `TermKey.make/parse/label/rank/next/previous/current/season`, `Season.label`, `Strategy.label`, `Course.displayCode/displayName` | helpers |

### Writes (`App/AppModel+Mutations.swift`)

- Semesters: `addTerm(season:year:current:) -> Term?` (existing key returned unchanged), `setCurrentTerm(key)`,
  `removeTerm(key)` (its classes go back to "To take"), `toggleDisabledTerm(key)`.
- Classes: `addCourse(code: "", title: "New class", credits: 3, …) -> Course?` (selects it and sets
  `editRequestCourseId`), `updateCourse(id, CoursePatch(code:title:credits:prereqs:coreqs:summerOk:term:))`
  (`term: .some(nil)` = To take), `setTerm(of:to:)`, `setPrereqs(of:text:)` / `setCoreqs(of:text:)` (comma-separated),
  `removeCourse(id)`.
- Transfer credit: `moveToTransfer(ids)`, `addTransferCourse()` (a new class already in Transfer credit, focused),
  `clearTransferCredit()` (all back to To take), or `setTerm(of:to: TermKey.transfer)`.
- Planning: `setMaxCredits(_:)`, `setSummerMax(_:)`, `setStrategy(_:)`.
- Theme / preferences: `app.preferences.x = …` (auto-saved), `setAppearanceMode`, `selectScheme(id:)`,
  `setThemeSelection`.
- Escape hatch: `app.mutate { data in … }` (any `PlannerData` public mutating API; normalized, recomputed, saved once).

### Navigation and shared UI state

`app.section` (.planner / .route / .schedule / .settings; ⌘1–⌘4), `app.openSettings(.importAtlas)` (⌘, opens the last pane;
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
- **Transfer credit** (2026-10-05): the Semesters row starts with a `posSoft` "Transfer credit · 12 cr" chip
  (`.transfer` glyph; menu "Add a transfer class", "Move all to To take…" with a confirmation) whenever a class has
  transfer credit, else a dashed "Add transfer credit" chip in that first slot. Every Term menu (and the row context
  menu's Term submenu) offers "To take", then "Transfer credit", then the semesters. The table groups transfer
  classes FIRST ("Transfer credit · 4 classes · 12 cr · AP, IB, …"), the status chip says "Transfer" (pos), the
  Term cell "Transfer"; "Credits done" includes them with the caption "incl. 12 transfer"; the footer says
  "33 taken (4 transfer)". No multi-select (the table is single-selection) — move classes one by one.
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
  `.zoomIn`, 0.25–6× of fitted; fitted never below 80 % scale; the label shows the real scale) · `Fit` (`.fit`, ⌘0).
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
- **Transfer column**: leftmost (it is `schedule.columns[0]`), `posSoft` card with a `pos` hairline, `posText` label
  "Transfer credit" and caption "12 cr · transfer", boxes on `panel` with `pos` borders; ribbons from transfer
  classes to later ones; hover / selection / chain highlight and Fit include it (when the fitted board is wider than
  the window it still opens at the current term, like past terms). Legend gains "Transfer" when the column exists.
  Class detail: chip "Transfer", facts "Transfer credit — counts as taken". The Schedule tab never sees transfer
  classes (Banner terms map to season keys only).
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

### Schedule — `Views/Schedule`, `App/Schedule`, core `Registration/` (section ⌘3)

Builds every weekly timetable for a UNC Charlotte term from the classes planned for it, from UNC Charlotte's PUBLIC
class search (no sign-in needed). One optional write, only on the user's explicit confirmation: "Export to Banner…"
creates a NEW Plan Ahead plan from the timetable on screen, in a session the user signed in to themselves on UNC
Charlotte's own page. It never registers, never saves a term, never changes or deletes an existing plan; the user
registers in Banner themselves. (History: a read-only sign-in + Plan Ahead reader shipped in 4df99f3, was removed in
e0fa079 at the user's request, and sign-in came back 2026-09-30 for export only — the "Banner plan" course source did
not come back.)

- **Model**: `app.scheduleTab` (`ScheduleModel`, `@MainActor @Observable`, owned by `AppModel`; activated the first time
  the tab shows). Rows (`ScheduleCourseRow`) are the classes `app.schedule` (the route) places in the term, minus
  removed, plus added codes ("MEGR 2144"). Each row shows code, title, credits, sections found and open.
- **Terms**: `classSearch/getTerms` (cached 12 h); the picker shows the newest six plus the calendar term; default =
  the last term used, else the next term the route plans, else the calendar term. `BannerTermCode`: YYYY + 10 spring /
  60 summer (50 / 70 read as summer) / 80 fall ↔ "spring-2027"; " (View Only)" is stripped.
- **Sections**: `BannerClient` — one anonymous session (synchronizer token from `term/termSelection?mode=search`,
  `term/search?mode=search` POST with the term, then per course `classSearch/resetDataForm` + `searchResults/
  searchResults`, 500 per page, exact course-number match, one re-established-session retry on 0 results), fetched
  sequentially with a 450 ms pause, cached per term + course with the fetch time (`schedule-cache.json`, stale after
  6 h; "Refresh sections" refetches all). Linked sections (`isSectionLinked`) fetch `fetchLinkedSections`; a choice is
  then a linked set (`TimetableChoice`). UNC Charlotte doesn't appear to link (labs are separate "L" courses).
- **Generator** (`TimetableGenerator.generate`, pure): exactly one choice per course; conflict = two timed meetings on a
  shared weekday with overlapping [begin, end) AND overlapping date ranges; online / TBA meetings never conflict (listed
  under the grid). Filters: open seats only (> 0), hide full or wait-listed, allow online, campuses; user exclusions and
  pins; weekly blocks (`TimetableBlock`) remove any section meeting inside one. Most-constrained-course-first
  backtracking with forward checking, capped at 10,000 ("showing the first 10,000"). Zero results explain themselves:
  a course with no sections, a course whose sections were all filtered (with counts per reason), a pair of courses
  that always clash, or "no combination fits". Sorts: fewest class days, fewest class sessions (timed meetings a
  week: MWF = 3, TR = 2; then days, gaps), highest professor rating, latest start, earliest finish, least time
  between classes, most open seats — ties broken by the option id, so output is deterministic.
- **Combined sorts**: `TimetableTermState.sorts` is an ordered priority list (never empty, no duplicates; default
  [fewestDays]; an old file's single `sort` loads as [that]; `sort` is still written for older builds). Timetables
  compare by each criterion's own key in order (`primaryKey`: days / sessions / scored-then-−score / −start, −avg
  start / end, avg end / gaps / −seats), then the first criterion's usual tie-breaks, then the option id. A
  one-element list orders exactly like the single sort. UI: `ScheduleSortControl` — header button "Fewest days →
  Highest rating" (full list in the tooltip, accent-tinted when combined) opening a popover with a checkbox per
  criterion (check appends, uncheck removes, never the last), numbers 1…n, move up / down, Reset to default,
  "Look up ratings".
- **Highest professor rating**: score = Σ(rating × credits) / Σ credits over the courses whose chosen section has a
  rated professor (`TimetableRatings`: CRN → the primary instructor's combined RMP rating; several rated
  instructors → numRatings-weighted mean; a linked set uses its first section's credits once). Not on RMP, 0
  ratings, ambiguous, unassigned / "TBA" → scored internally as `TimetableRatings.unratedScore` = 2.5 (user's rule,
  2026-09-30; the UI still shows "no rating"); only a section whose lookup is still pending is left out until it
  resolves. A timetable with no scored course sorts after every scored one (ties: days, gaps, id). The generator stays pure — `ScheduleModel` builds the table
  from the RMP cache. With this sort anywhere in the list (or "Look up ratings"), every distinct instructor of the
  term's loaded sections is looked up (cache first, one at a time, ~0.6 s between requests; header shows "Rating
  professors 7 / 23"); results re-sort as they arrive (on #1 you stay on the new #1; after browsing, the timetable
  on screen is kept). The header summary shows "4.3 prof rating" whenever the current timetable has a score.
- **Class detail + Rate My Professors**: clicking a meeting block (not in Block-times mode), an Online / TBA entry
  or a CRN chip — or a section's text in the sidebar — sets `scheduleTab.detail` and opens
  `ScheduleClassDetailSheet` (640 × 700 sheet: taller than a popover allows, matches the app's other detail sheet,
  capturable by the smoke run). It shows code, title, section, CRN (click to copy), credits, type, method, campus,
  seats, waitlist; every meeting (days, time, "Building Room" / Online / TBA, dates when they differ from the
  course's usual range); each instructor ("Last, First" shown as "First Last"; "Instructor not assigned yet") with a
  `ScheduleRatingCard`: rating x.x / 5, count, difficulty, would-take-again, per-profile breakdown when combined
  ("Combined from 2 UNC Charlotte pages, weighted by number of ratings"), profile links (NSWorkspace), "no ratings
  yet", ambiguous (candidates + links, no score), "No Rate My Professors page at UNC Charlotte" (+ RMP search link),
  error with Try again. Lookups start when the sheet opens (cache first). Esc / Done close. The sidebar's section
  rows show the primary instructor's rating as a small badge — cache only, never a lookup.
- **Rate My Professors (core `RateMyProfessors/`)**: RMP's public GraphQL (`POST https://www.ratemyprofessors.com/
  graphql`, header `Authorization: Basic dGVzdDp0ZXN0`, `newSearch.teachers(query: {text, schoolID})`). UNC
  Charlotte has TWO RMP pages (found 2026-09-30): 1253 "University of North Carolina at Charlotte" (`U2Nob29sLTEyNTM=`,
  every professor) and 19352 "University of North Carolina at Charotte" (`U2Nob29sLTE5MzUy`, empty today) — both are
  searched, nothing else ever is. `RMPRequestGuard`: HTTPS POST to that path only, no query string, JSON body with a
  read-only `query` (anything containing "mutation" refused), `variables.query.schoolID` must be a UNCC page;
  ephemeral session, no cookies, redirects refused, 15 s timeouts. RMP's search matches whole names (not
  substrings), so a name is searched by its family name, plus each part of a hyphenated / multi-word one.
  Matching (`RMPMatcher`, normalized — case / diacritics / punctuation ignored): strong = exact family + exact given;
  good = exact family + nickname / prefix given ("Chris"/"Christopher", "Richard"/"Ritchie") or hyphen-partial
  family + exact given; weak = exact family + initial. All strong profiles (plus compatible good ones) are one person
  and combined — across both pages and RMP's duplicate profiles on one page. Otherwise good, then weak, profiles are
  grouped into people; one → found, several → the one whose RMP department fits the course subject
  (`RMPDepartments`), else ambiguous. `RMPRating`: avgRating / avgDifficulty = Σ(x × n) / Σ n over profiles with
  ratings; would-take-again weighted the same, skipping −1; total = Σ n.
- **Sign-in (optional; `App/Schedule/BannerWebSession.swift`, `Views/Schedule/ScheduleSignInSheet.swift`)**: the app
  never signs in by itself. The sheet opens only when the user clicks "Sign in" in the sidebar's account footer
  ("UNC Charlotte account · Not signed in · Sign in" / "Signed in as X · Sign out" / "Signed in earlier" / "Sign-in
  ended") or starts an export while signed out. It is an embedded WKWebView on `WKWebsiteDataStore.default()` showing
  `BannerPlanExport.signInURL` — UNC Charlotte's own CAS / Shibboleth page (webauth.uncc.edu, TARGET =
  StudentRegistrationSsb/login/cas, which starts the Banner session). NOT `term/termSelection?mode=plan`: signed out,
  that silently redirects to Banner's public landing page (verified live 2026-09-30 — the first build started there,
  and clicking around the landing page was mistaken for a sign-in). The app never sees or stores the password (no
  Keychain) and never reads another browser's cookies. Signed in is decided ONLY by asking Banner: on every
  selfservice page the sheet runs `BannerPlanExport.sessionCheckScript` (GET `plan/getTerms`, redirects not
  followed): JSON = signed in, redirect / HTML = signed out (the footer then offers "Go to sign-in page"). The
  exporter runs the same check after opening Plan Ahead. Activation only checks locally whether uncc.edu cookies exist ("Signed in earlier"). Sign out
  deletes every uncc.edu cookie and website-data record. The old one-time `forgetOldBannerSignIn` cleanup is DELETED
  (it can never wipe a new sign-in); its `didForgetBannerSignIn` default is simply ignored.
- **Export to Banner… (`ScheduleModel+Export.swift`, `Views/Schedule/ScheduleExportSheet.swift`, core
  `BannerPlanExport`)**: CRN strip button + Schedule ▸ Export to Banner… (⇧⌘E), enabled when a timetable is shown.
  Signed out → sign-in sheet first ("Continue to export"). Then the 680 × 720 confirmation sheet: editable plan name
  (default "Thuban · Spring 2027 · Schedule 3", count / limit), term + Banner code + schedule number, every section
  (code, section, title, times, credits, CRN; a linked set adds each CRN, credits once per course), and the notes
  "Creates a NEW plan in Plan Ahead. Does not register you or change existing plans." + "You have 2 of 5 plans…"
  (read while the sheet shows "Checking your Plan Ahead plans…" — read-only). At Banner's limit (planCount >=
  maxPlans; UNC Charlotte documents 5 a term) the sheet says so and export is impossible ("delete a plan in Banner").
  Only "Create plan" writes: it mints a `BannerExportAuthorization` for exactly that term + CRNs and runs the hidden
  exporter; progress per step; then success ("Plan “…” created with 5 classes", checked against Banner, "Open Plan
  Ahead" → default browser) or a precise failure with Banner's message, saying whether anything was written ("Try
  again" only when nothing was). A running write can't be dismissed.
- **Export request sequence (`BannerPlanExporter`, hidden WKWebView, same store)**: (1) GET term/termSelection?mode=plan
  (sign-in page → signed out → sign-in sheet); (2) POST term/search?mode=plan `term=<code>&studyPath=…` (read-only);
  (3) GET plan/selectPlan → `window.bootstraps` planCount / maxPlans / existing sequence numbers (stop if full);
  (4) GET plan/plan → must be a NEW empty plan (`selectedPlan.planHeader.sequenceNumber` empty, no planCourses —
  otherwise stop, nothing sent); `#saveButton[data-plan-save-endpoint]` + "/batch" and `#addPlanItem[data-endpoint]`
  must be the expected URLs when present; `#txt_planDesc` maxlength (if any) checks the name; (5) per CRN POST
  plan/addPlanItem `term=…&courseReferenceNumber=…&section=section` (form, as the page's jQuery sends it) → `{success,
  model}`; any rejection stops with "No plan was saved"; (6) ONE POST plan/submitPlan/batch, `application/json`,
  `{"create":[<each model + headerDescription:name, headerComment:null>],"update":[],"destroy":[]}`; answer `{success,
  data:{planHeader:{sequenceNumber}, create:[{messages:[{type}]}]}}` or `{success:false, message:[{message,type}]}`;
  (7) GET plan/selectPlan and verify a plan (by the returned sequence, else a new plan with that name) has exactly the
  CRNs. Requests are built and guarded in Swift, sent with `fetch` (credentials, `X-Synchronizer-Token` from the page's
  meta, `X-Requested-With: XMLHttpRequest`) via `callAsyncJavaScript` in a private content world ("thuban-export").
  Dry run: `THUBAN_PLANNER_EXPORT_DRY_RUN=1` skips sign-in and all network, logs every planned request (os_log
  org.thuban.planner + stdout) and shows a "Dry run finished" state. The smoke run (offline) behaves like a dry run.
- **What is from source vs guessed**: FROM UNC CHARLOTTE'S JS (planView-mf.js, bannerWeb-mf-22d3cf2a…js): the
  addPlanItem form body and response handling; new plan = collection id "pnew" when planHeader.sequenceNumber is
  empty; the name dialog sets headerDescription / headerComment on every dirty model; `Collection.save` batch =
  POST `<save endpoint>/batch` JSON {create, update, destroy} and its response handling; the synchronizer-token
  prefilter; planCount / maxPlans disabling "Create a New Plan". FROM lwgw/UCR-Course-Scheduler term_plan.py (a working
  Banner 9 client elsewhere): the URLs plan/addPlanItem and plan/submitPlan/batch, opening plan/plan after
  term/search, create-only batches. GUESSED / UNVERIFIED: that GET plan/plan opens a new plan at UNC Charlotte (guarded
  by the new-empty check); whether addPlanItem models carry an id (they are sent as `create` like the UCR script); the
  name limit (fallback 60 unless the page has a maxlength); success / error shapes beyond the JS handlers (synthetic
  fixtures). NOTHING of the write path has run against UNC Charlotte — the user's first export is the real test.
- **Enforcement (`BannerRequestGuard`)**: registration is denied everywhere, always — classregistration/,
  addRegistrationItem, addCRNRegistrationItems, submitRegistration, "register", saveTerm; existing-plan writes are
  denied everywhere, always — deletePlan, makePreferred, savePlanNote, markApproved. addPlanItem and submitPlan are
  denied by default and allowed ONLY with a live `BannerExportAuthorization`: POST, no query, exact paths, one
  addPlanItem per confirmed CRN (form keys term / courseReferenceNumber / section=section, confirmed term), then one
  batch after every add, with empty update / destroy and create items = exactly the confirmed CRNs (term, when
  present, the confirmed one); revoked when the export ends. App-made read requests: HTTPS selfservice.uncc.edu
  /StudentRegistrationSsb/ only, GET, POST only to term/search and classSearch/resetDataForm. Web views: navigations
  to any denied fragment are cancelled (`checkBrowser`); the sign-in view's content rules block every denied
  fragment; the export view's rules block registration + existing-plan writes and a document-start page-world fence
  script makes Banner's own fetch / XHR to any denied endpoint fail, while the exporter's guarded fetches run in their
  own content world. Fragments are matched case-insensitively on the raw and percent-decoded URL.
- Old schedule.json / cache keys (source, planSequence, unpinnedPlanCourses, plans) are ignored on load.
- **Screen**: 340 pt sidebar (semester menu, class cards that
  expand to sections with include checkboxes and a pin, "Add a class", filters; a pinned "UNC Charlotte account" footer) | header ("Schedule 3 of 128", credits
  · days · span · gaps, sort menu, ◀ ▶ and ←/→) | week grid (Mon–Fri, weekends when used; 7 AM–10 PM widened as needed,
  30-minute rules; course-coloured meetings, hatched blocks) | CRN strip + Copy CRNs + Export to Banner…. "Block times" (toolbar, ⌘B):
  drag to add a block (15-minute snap), click one to rename / retime / delete. States: loading terms, can't reach
  Banner (Try again), no classes, finding sections, couldn't load sections, "Why
  nothing fits" card over the grid. Course colours: `ScheduleTheme` (accent, pos, neg, accent turned round the wheel,
  accentDeep, signal — theme tokens only).
- **Files**: `rmp-cache.json` (per normalized instructor name: the candidate UNCC profiles; fresh 7 days, "not on
  RMP" 2 days, pruned after 60; stale entries still shown; safe to delete). `schedule.json` (per Banner term code: added / removed classes, excluded CRNs, pins, blocks, filters,
  sort, last schedule index; `lastTermCode`) and `schedule-cache.json` (terms, sections; safe to delete), both next to planner.json (THUBAN_PLANNER_HOME honoured), atomic, 0600.
- **Tests**: `BannerTests` (term codes, real-fixture decoding incl. null times / several meetings / negative seats /
  double spaces, request guard, page helpers, client flow on a fake transport, store round trip + old-file
  tolerance), `TimetableTests` (conflicts, date ranges, blocks, online, filters, pins,
  linked sets, zero-result reasons, cap, determinism, sorting, 6 × 20 performance), `TimetableRatingTests` (credit
  weighting, exclusions, unscored last, combined sorts in both orders, single-list parity, old / new sort decoding),
  `RateMyProfessorsTests` (name parsing, matching: exact / nickname / initial / hyphenated / duplicates / two pages /
  ambiguous / none / other school, weighted average incl. 0 ratings and −1, guard, client flow on a fake transport,
  cache round trip + freshness; fixtures in `Fixtures/rmp/`, one marked synthetic), `BannerPlanTests` (bootstraps
  parser: reconstructed fixture, tolerant variants, HTML fallback), `BannerPlanExportTests` (items / credits /
  times from a timetable incl. a linked set, default name + limits, exact addPlanItem and batch bodies, dry-run plan
  passing one authorization, response parsing incl. errors / HTML, plan-page info + maxPlans, verification) and
  `BannerExportGuardTests` (writes denied without authorization; registration and existing-plan writes never, even
  with one; scope: CRN, term, fields, once per CRN, batch only after all adds, create-only, once; revoked; content
  rule lists and fence). Response fixtures `banner/addPlanItem-success.json` / `submitPlan-success.json` are marked
  SYNTHETIC. Live, public, read-only checks:
  `THUBAN_PLANNER_LIVE_BANNER=1 scripts/test.sh` (term list + one MEGR 2144 search);
  `THUBAN_PLANNER_LIVE_RMP=1 scripts/test.sh` (three PHYS instructors on both UNCC RMP pages, ~10 requests).

### Technical electives — `Views/Electives`, `App/DegreeTools`, core `Catalog/` (Planner toolbar, ⇧⌘T)

The BSME requires four technical electives (12 credits), at least three MEGR. The catalog's list (68) and
DegreeWorks' list (75) differ: the catalog adds MEGR 3221 (counts only when MEGR 3216 fills the design elective);
DegreeWorks adds MEGR 3222, 3243, 3280, 4212, 4213, 4281, 4282, 4313 (six have 2026-27 catalog pages, MEGR 3222 /
3243 have none). The dataset keeps all 76 with `inCatalog` / `inDegreeWorks`.

- **Dataset** (`Resources/uncc-bsme-2025-26.json`, `CatalogDataset.bsme2025`): program (catalog year, rule, core
  codes), electives, and 153 courses — every elective plus, recursively, every prerequisite / corequisite they name
  until the BSME core (core pages read, not recursed) — with title, credits, raw "Prerequisite(s)", "Corequisite(s)",
  "Pre- or Corequisite(s)", "Restriction(s)" text, parsed groups (AND of OR-groups) and notes (grades, standing,
  permission, asides). Generated by `scripts/refresh_catalog.sh` (tools/catalog: catalog.charlotte.edu is behind an
  AWS WAF JavaScript challenge, so pages are loaded with Playwright's cached chrome-headless-shell; program page
  catoid 40 / poid 11501, subject listings navoid 4989, course pages preview_course_nopop; DegreeWorks-only codes
  looked up in 2026-27, catoid 42 / navoid 5390). `CatalogRequirementParser` (Swift) and `reqparse.py` implement the
  same rules; `CatalogDatasetTests` checks they agree on every line.
- **Equivalents** (`CourseCode.equivalents`): PHYS 2101L ↔ PHYS 1101L (DegreeWorks counts it); the curriculum-change
  pairs the catalog itself lists as alternatives — MEGR 3122 ↔ 3123, 2240 ↔ 2242, 3171L ↔ 3174, 2156 ↔ 2157 (so MEGR
  3237's "MEGR 3122" is met by a planned MEGR 3123). Matching is otherwise exact code, case / space-insensitive.
- **Offered** = at least one section in the six Banner terms up to and including the calendar term (two years with
  summers) or in any upcoming term `getTerms` lists. `OfferingsFetcher`: `getTerms` once a day, then ONE
  `BannerClient.subjectSections` search (txt_subject only, 500 a page, resetDataForm first) per elective subject
  (MEGR, PHYS, BIOL, MATH) per term that is missing or stale — finished terms are fetched once and kept, the
  calendar / upcoming terms refetched after 7 days — paced 0.45 s, through `BannerRequestGuard`. Cached in
  `offerings-cache.json` (per term + subject: course number → section count, fetch time; safe to delete). The
  bundled snapshot (`uncc-offerings-snapshot.json`, 28 searches on 2026-10-05) is used until the first fetch and in
  the offline smoke run. Refresh: opening the panel (when needed) or "Refresh" (current + upcoming terms).
- **Chains** (`RequirementChainResolver`): a group is met by any option in the plan (taken or to take — the scheduler
  orders the rest) or already being added; otherwise the user's choice for that group (`"PHYS 4241#p0"`) or the
  option needing the fewest additional classes (ties: offered recently, in the catalog, listed first), resolved
  recursively; additions are deduplicated and ordered prerequisites-first; prerequisite cycles stop with a warning
  (lecture ↔ lab corequisite loops are normal); a code missing from the catalog is added by code with a warning;
  not-offered additions are flagged. Added classes are To take with `prereqs` / `coreqs` = the concrete codes (plan
  spelling), `summerOk` when a summer term in the window ran it, tags "tech-elective" / "prereq:<elective>".
  Verified chain (2025-26): PHYS 4242 Quantum Mechanics II ← PHYS 4241 Quantum Mechanics I ← (PHYS 3220 or MATH
  2241), (PHYS 3121 or MEGR 2144), PHYS 3141 Introduction to Modern Physics, (MATH 2171 or PHYS 3101); PHYS 3141 ←
  (PHYS 2102 or PHYS 1102), MATH 1241, pre/co MATH 1242.
- **Tracker** (`TechElectives.progress`): electives in the plan (tagged or not) whose catalog condition holds;
  "2 of 4 chosen · 2 of 3 MEGR". Toolbar button "Tech electives 2/4".
- **Sheet** (880 × 780): progress card, search, All / MEGR / Other, "Not offered recently (N)" toggle (off by
  default; those rows dimmed), offerings caption + Refresh; rows: code, title, offered terms ("Fall 2026, Spring 2026
  + 2 more · upcoming Spring 2027"), credits, status chip (Ready / Needs PHYS 4241 → PHYS 3141 / Needs 3 classes /
  Chosen · Spring 2029 / In plan / Taken), Add / Remove. Add with everything in the plan → added at once; otherwise
  the confirmation: "Add PHYS 4242 and 2 prerequisites?", OR pickers (with "+N classes" costs), the tree (In plan ·
  Fall 2026 / Add / Added above / not in catalog / cycle), the additions with credits, warnings and catalog notes;
  Add all / Cancel. After adding, a banner says where each class landed (`app.routeTerm`). Remove (only electives
  tagged here, To take) offers the To-take classes tagged only for it that nothing else still needs.
- The Planner table marks tagged electives "TE".

### Import degree requirements — `Views/DegreeImport`, core `DegreeImport/` (Planner "…" menu, Settings ▸ Import, ⇧⌘I)

- **Formats** (`DegreeDocumentText`): PDF (PDFKit text; "CODE / - / Title (3)" breaks rejoined), HTML (blocks →
  lines, entities), MHTML (MIME parts, quoted-printable / base64, the text/html part), .docx (`/usr/bin/unzip -p …
  word/document.xml`), text / Markdown. Drag a file onto the sheet or Choose a file.
- **Parsing** (`DegreeDocumentParser`): DegreeWorks (text has "Still needed:") reads ONLY "Still needed" blocks —
  "1 Class in MEGR 3114" = required (titled by its requirement line), "1 Class in MEGR 3216 / or 3221" or "4 Classes
  in MEGR 3090 or 3092 …" = a choice group, "additionally …" / "MEGR @" = notes. Catalog pages / checksheets: a line
  STARTING with a code is a class ("MATH 2171 - Differential Equations (3)", "ENGR 1300 Exploring … (2)", "PHYS 2101
  (3)", "MEGR 3310   Flight Mechanics   3"); "or CODE" joins the class above into a choose-one group; "Select / Choose
  N of the following", "Two MATH courses: A or B or C", headings with "Elective" (picks = credit hours ÷ 3) and
  "Option N" open choice groups; "Prerequisite(s):" / "Corequisite(s):" / "Pre- or Corequisite(s):" / "Credit
  Hours:" lines attach to the class above; "MATH 3XXX-4XXX …" wildcards become group notes; codes inside prose are
  skipped and listed. Program name from the page `<h1>` / title lines ("Mathematics, Minor", "Bachelor of Science
  in Mechanical Engineering"). Limits: no OCR (scanned PDFs read as empty), multi-column PDFs can interleave text,
  "Option" blocks are offered as choices (take one option), credit-hour buckets of any course ("6 credits of MATH
  3000+") are notes only, DegreeWorks blocks that only say "See … section" are skipped.
- **Merge** (`DegreeImportMerge`): only adds; a class already in the plan (same normalized code or an equivalent) is
  never touched; choice groups are never auto-added (the user ticks options; a plan class counts toward one
  requirement only — required matches first, then groups in order); missing title / credits / requirements come
  from the bundled dataset ("details from the catalog"); OR-groups resolve to the option in the plan / being added;
  added classes are To take, tagged "program:<name>"; importing the same document again adds nothing.
- **Sheet** (860 × 780): choose (drop zone + merge rules) → reading → preview (counts "N required · M already in
  your plan · K to add · G choices", the classes to add as checkboxes with requirements, choice cards with option
  toggles, "Already in your plan", "Lines not read as requirements") → "Add N classes" (snapshot "before degree
  import", then ONE `mutate`) → done ("where they landed" per class, plan status, backup name).
- **Fixtures** (`Fixtures/degree/`): BSME catalog page (HTML + MHTML), Mathematics minor (HTML), Physics minor (PDF
  printed by Chromium), a REDACTED DegreeWorks audit (MHTML; name, ID, advisor, GPA, grades, transfer schools
  removed), a synthetic aerospace checksheet (.txt + .docx).

### Settings (C) — `Views/Settings` (section ⌘4 / ⌘,)

Pane list on the left (Planning, Appearance, Import, Data, About), pane on the right (`app.settingsPane`).

- **Planning**: "Max credits per semester" (numeric field 1–30, "The most credit hours the planner will pack into a
  fall or spring term."), "Max credits in summer" (0–30, "Summers usually carry a lighter cap."), "Route strategy"
  (three selectable rows with Atlas's labels, a one-line explanation each, and a live preview "With this: finishes
  Spring 2028 · 3 more terms" computed with `Scheduler.scheduleDegree` on a copy). Commit on submit / blur.
- **Appearance**: working copy from Gym (mode, eight schemes, text size, preview). Keep.
- **Import**: (also "Degree requirements": Import degree requirements… / Technical electives…) header "Bring your
  plan over from Atlas" / "Read-only: Atlas is never changed."; host + email fields,
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
`11-route`, `12-schedule`, `13-settings`, every registered scene (`30+`), `900-planner-dark`, `901-route-dark`, and every Settings pane
(`950-settings-…`; these sit above the scene range so scene numbers never collide). Register extra states in YOUR area's file — the registry line
`SmokeScenes.all = planner + route + classDetail + settings + schedule` is pre-wired and frozen (the Schedule scenes run offline on `BannerSampleData`):

```swift
extension SmokeScenes {                       // Views/Route/RouteSmokeScenes.swift
    static var route: [SmokeScene] {
        [SmokeScene(name: "route-zoomed") { app in app.section = .route; app.routeZoom = 2 }
                    cleanup: { app in app.routeZoom = 1; app.routeFitRequest += 1 }]
    }
}
```

`window: .main` (default), `.popover` (an open popover's window, e.g. the Schedule sort menu) or `.sheet` (the class detail sheet: `app.presentCourse("c-sample-31")`); `settle:` seconds.
The empty / first-run Planner (with the import offer) — `isFirstRun` is `private(set)` and a smoke run seeds sample
data, so use the smoke-only setter:

```swift
SmokeScene(name: "planner-first-run") { app in
    app.section = .planner
    app.replaceData(.empty); app.smokeSetFirstRun(true); app.preferences.importOffered = false
} cleanup: { app in app.replaceData(SampleData.make(now: app.now, calendar: app.calendar)) }
```

Technical electives / degree import scenes live in `Views/Electives/ElectivesSmokeScenes.swift` (`SmokeScenes.electives`,
appended to the Planner list): panel light / dark, not-offered toggle, the PHYS 4242 chain light / dark, OR pickers,
added banner, remove, Planner with TE marks, import choose / preview (minor, DegreeWorks, dark) / result — offline on
`BSMESampleData`, the bundled dataset and offerings snapshot. Transfer scenes (`planner-transfer`, `-rows`, `-dark`,
`-add`, `route-transfer`, `route-transfer-dark`, `class-detail-transfer`) use `SampleData.makeWithTransferCredit`
(the sample + STAT 3128 / PSYC 1101 / HIST 1110 as `c-sample-t1…t3`, MATH 2164 moved to transfer). The run's
timeout is `SMOKE_TIMEOUT` (default 360 s). Always undo state in `cleanup`. Look at your PNGs (Read tool) before you finish. Sample ids are `c-sample-01 … 43`
(01–29 taken, 30–43 to take; 38 = Senior Design II, the last class).

## Build / test / smoke

- `DERIVED=.build/DerivedData-<you> scripts/build.sh` — ALWAYS a private DerivedData, run from your own worktree
  (see Git). Regenerates the project first.
- `scripts/test.sh` — core tests (`swift test`, 250 tests (three live tests skipped) incl. 400 golden cases and the 3,200-case differential run against Atlas's JS; `TechElectivesTests`, `CatalogDatasetTests`, `DegreeDocumentTests`, `DegreeImportMergeTests`). Add tests for core logic you add. `THUBAN_PLANNER_LIVE_OFFERINGS=<json> scripts/test.sh` refreshes an offerings snapshot (public Banner search).
- `scripts/refresh_catalog.sh` — regenerates the BSME dataset from the catalog (headless Chromium, ~160 paced page loads on a cold cache); `--offerings` refreshes the bundled offerings snapshot.
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
