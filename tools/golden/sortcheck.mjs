// Self-check of v8sort.js: result must be sorted and stable (run: jsc -m sortcheck.mjs).
import { v8sort } from './v8sort.js'
let seed = 7; const rnd = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 }
let bad = 0, total = 0
for (let t = 0; t < 600; t++) {
  const n = Math.floor(rnd() * (t < 300 ? 80 : 2000))
  const keys = Math.max(1, Math.floor(rnd() * n))
  let a = []; for (let i = 0; i < n; i++) a.push({ k: Math.floor(rnd() * keys) })
  if (t % 3 === 0) { a = v8sort(a, (x, y) => x.k - y.k); for (let i = 0; i < n; i += 50) a[i] = { k: Math.floor(rnd() * keys) } }
  if (t % 5 === 0) a.reverse()
  a.forEach((x, i) => { x.pos = i })
  v8sort(a, (x, y) => x.k - y.k)
  total++
  for (let j = 1; j < n; j++) if (a[j - 1].k > a[j].k || (a[j - 1].k === a[j].k && a[j - 1].pos > a[j].pos)) { bad++; break }
}
print(`v8sort: ${total} arrays, ${bad} not sorted/stable`)
