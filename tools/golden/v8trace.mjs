// Direct check of the V8 TimSort port (v8sort.js, mirrored by V8Sort.swift) against the ENGINE'S OWN sort, by
// comparator call order: for each seeded array the sequence of (a, b) pairs the comparator sees — and the result —
// must be identical. Under a real V8 (Node, Deno, Electron-as-Node) every case must match; that is the proof the
// golden files could not give on a Mac without V8. Under JavaScriptCore (a merge sort) they are expected to differ,
// so scripts/v8check.sh only trusts this under V8. Comparators include inconsistent (random) ones and ones that
// memoize lazily inside a cycle, like Atlas's depth comparator.
import { v8sort, nativeSort } from './v8sort.js'

const print = globalThis.print ?? console.log
let seed = 0x0ddba11
const rnd = () => { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let t = Math.imul(seed ^ seed >>> 15, 1 | seed); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296 }

function trace(sortFn, items, makeCmp) {
  const calls = []
  const cmp = makeCmp()
  const arr = items.map((x) => ({ ...x }))
  sortFn(arr, (a, b) => { calls.push(a.id + ':' + b.id); return cmp(a, b) })
  return { calls: calls.join(','), result: arr.map((x) => x.id).join(',') }
}

const comparators = {
  consistent: () => (a, b) => a.k - b.k,
  random: () => { let s = 99; return () => { s = (s * 1103515245 + 12345) % 2147483648; return [-1, 0, 1][s % 3] } },
  lazyMemo: () => { const memo = new Map(); let n = 0; const d = (x) => { if (!memo.has(x.id)) memo.set(x.id, (x.k * 7 + n++) % 5); return memo.get(x.id) }; return (a, b) => d(b) - d(a) || a.k - b.k },
}

let total = 0, mismatched = 0
const firstBad = []
for (let t = 0; t < 900; t++) {
  const n = t < 300 ? Math.floor(rnd() * 40) : t < 700 ? Math.floor(rnd() * 200) : Math.floor(rnd() * 3000)
  const keys = Math.max(1, Math.floor(rnd() * n))
  let items = []
  for (let i = 0; i < n; i++) items.push({ id: i, k: Math.floor(rnd() * keys) })
  if (t % 4 === 0) items.sort((a, b) => a.k - b.k)           // presorted runs (galloping paths)
  if (t % 7 === 0) items.reverse()                           // descending runs
  for (const [name, makeCmp] of Object.entries(comparators)) {
    total++
    const port = trace(v8sort, items, makeCmp)
    const engine = trace((a, c) => nativeSort.call(a, c), items, makeCmp)
    if (port.calls !== engine.calls || port.result !== engine.result) {
      mismatched++
      if (firstBad.length < 3) firstBad.push(`case ${t} n=${n} ${name}`)
    }
  }
}
print(`v8trace: ${total} sorts, ${mismatched} differ from this engine's sort${firstBad.length ? ' (first: ' + firstBad.join('; ') + ')' : ''}`)
