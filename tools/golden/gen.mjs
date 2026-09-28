// Golden cases for the Swift scheduler: runs ATLAS'S OWN scheduler (atlas-course.js = atlas-ui/src/page/course.js,
// unmodified) on seeded random plans and records its output. Swift must reproduce every case exactly
// (Tests/ThubanPlannerCoreTests/GoldenScheduleTests.swift).
//
//   TZ=UTC jsc -m tools/golden/gen.mjs > Packages/ThubanPlannerCore/Tests/ThubanPlannerCoreTests/Fixtures/golden-schedule.json
//   (scripts/golden.sh does exactly this with macOS's built-in JavaScriptCore; no Node needed.)
//
// v8sort.js replaces Array.prototype.sort with V8's TimSort so the comparator call order (which decides memoized
// depths inside requirement cycles) is Chrome/Electron's, not JavaScriptCore's. upcomingSummers / planStatus are
// copied verbatim from atlas-ui/src/page/courseui.js (not exported there), with `now` passed in.
import { nativeSort } from './v8sort.js'
import { scheduleDegree, parseTerm, nextTermKey, currentTermKey, termRank, termLabel, termKey } from './atlas-course.js'
// GOLDEN_NATIVE_SORT=1 (scripts/v8check.sh under a real V8: Node / Deno / Electron-as-Node) regenerates with the
// engine's OWN sort, so the output can be diffed against the committed golden file made with the V8 port.
const env = globalThis.process?.env ?? globalThis.Deno?.env?.toObject?.() ?? {}
if (env.GOLDEN_NATIVE_SORT === '1') Array.prototype.sort = nativeSort

function upcomingSummers(s, now) {
  const start = s.terms.length ? s.terms[s.terms.length - 1].key : currentTermKey(now)
  const out = new Set(s.disabledTerms.filter((k) => parseTerm(k).season === 'summer'))
  let cur = start
  for (let i = 0; i < 15; i++) { cur = nextTermKey(cur); if (parseTerm(cur).season === 'summer') out.add(cur) }
  return [...out].sort((a, b) => termRank(a) - termRank(b)).slice(0, 5)
}
function planStatus(s, sched) {
  const remaining = s.courses.filter((c) => !c.term)
  const cr = remaining.reduce((t, c) => t + c.credits, 0)
  if (!remaining.length) return `${s.courses.length} classes · nothing left to schedule`
  const grad = sched.gradTerm && sched.termsToFinish ? ` · finishes ${termLabel(sched.gradTerm)}` : ''
  return `${remaining.length} to take · ${cr} credits · ${sched.termsToFinish} more term${sched.termsToFinish === 1 ? '' : 's'}${grad}`
}

// mulberry32
let seed = 0x5eed2026
const rnd = () => { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let t = Math.imul(seed ^ seed >>> 15, 1 | seed); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296 }
const pick = (a) => a[Math.floor(rnd() * a.length)]
const chance = (p) => rnd() < p
const int = (lo, hi) => lo + Math.floor(rnd() * (hi - lo + 1))

const DEPTS = ['MATH', 'PHYS', 'CS', 'MEGR', 'ENGR', 'CHEM', 'ECON', 'STAT', 'ENGL']
const CREDITS = [0, 1, 1, 1.5, 2, 3, 3, 3, 3, 4, 4, 5, 6, 15]
const SEASONS = ['spring', 'summer', 'fall']

function makeCode(i) {
  const r = rnd()
  const n = int(100, 4999)
  const d = pick(DEPTS)
  if (r < 0.04) return ''                                   // title-only class
  if (r < 0.10) return `${d}-${n}`
  if (r < 0.14) return `${d.toLowerCase()} ${n}`
  if (r < 0.17) return `${d}_${n}`
  if (r < 0.20) return `${d}${n}`
  if (r < 0.23) return `${d} ${n}L`
  if (r < 0.25) return `${d}.${n}`
  return `${d} ${n}`
}

function makeCase(k) {
  const size = k % 25 === 0 ? int(64, 110) : (k % 7 === 0 ? int(0, 4) : int(3, 45))
  const courses = []
  for (let i = 0; i < size; i++) {
    let code = makeCode(i)
    if (i > 0 && chance(0.05)) code = courses[int(0, i - 1)].code                 // duplicate code
    if (i > 0 && chance(0.04)) code = courses[int(0, i - 1)].code.toLowerCase()   // case variant
    const id = i > 0 && chance(0.02) ? courses[int(0, i - 1)].id : `c-${k}-${i}` // duplicate id
    courses.push({ id, code, title: code ? `Title ${i}` : (chance(0.5) ? `Untitled ${i}` : ''), credits: pick(CREDITS),
      prereqs: [], coreqs: [], summerOk: chance(0.4), term: null })
  }
  const refOf = (j) => { const c = courses[j].code; return chance(0.15) ? `  ${c.toLowerCase()} ` : c }
  const acyclic = chance(0.6)
  courses.forEach((c, i) => {
    const np = chance(0.45) ? int(1, 3) : 0
    for (let p = 0; p < np && courses.length > 1; p++) {
      const j = acyclic ? (i > 0 ? int(0, i - 1) : -1) : int(0, courses.length - 1)
      if (j >= 0 && j !== i && courses[j].code) c.prereqs.push(refOf(j))
    }
    if (chance(0.06)) c.prereqs.push(`XYZ ${int(100, 999)}`)                    // unknown ref
    if (chance(0.2) && courses.length > 1) {
      const j = acyclic ? (i > 0 ? int(0, i - 1) : -1) : int(0, courses.length - 1)
      if (j >= 0 && j !== i && courses[j].code) {
        c.coreqs.push(refOf(j))
        if (chance(0.5)) courses[j].coreqs.push(c.code || 'none')               // lecture ↔ lab mutual coreqs
      }
    }
  })
  // recorded terms
  const nTerms = k % 11 === 0 ? 0 : int(0, 5)
  let key = termKey(pick(SEASONS), int(2022, 2026))
  const terms = []
  for (let t = 0; t < nTerms; t++) {
    const p = parseTerm(key)
    if (!(p.season === 'summer' && chance(0.6))) terms.push({ key, season: p.season, year: p.year, current: false })
    key = nextTermKey(key)
  }
  if (terms.length && chance(0.8)) terms[terms.length - 1].current = true
  for (const c of courses) {
    if (terms.length && chance(0.3)) c.term = pick(terms).key
    else if (chance(0.02)) c.term = 'fall-2010'                                  // taken in an unrecorded term
  }
  const disabledTerms = []
  const last = terms.length ? terms[terms.length - 1].key : termKey('fall', 2026)
  let cur = last
  for (let t = 0; t < 8; t++) { cur = nextTermKey(cur); if (chance(parseTerm(cur).season === 'summer' ? 0.4 : 0.08)) disabledTerms.push(cur) }
  const maxCredits = pick([15, 15, 12, 18, 16, 9, 6, 3, 1])
  const settings = { maxCredits, summerMax: pick([9, 6, 0, 3, 12, Math.min(9, maxCredits)]), strategy: pick(['soonest-summer', 'soonest-optional-summer', 'even']) }
  const now = Date.UTC(int(2022, 2028), int(0, 11), int(1, 28), 12)
  return { name: `random-${k}`, now, input: { courses, terms, disabledTerms, settings } }
}

const cases = []
for (let k = 0; k < 400; k++) cases.push(makeCase(k))
const out = cases.map((c) => {
  const s = JSON.parse(JSON.stringify(c.input))
  const schedule = scheduleDegree(s, new Date(c.now))
  return { ...c, expected: { schedule, summers: upcomingSummers(s, new Date(c.now)), status: planStatus(s, schedule) } }
})
const print = globalThis.print ?? console.log
print(JSON.stringify({ generator: 'tools/golden/gen.mjs', source: 'atlas-ui/src/page/course.js', cases: out }))
