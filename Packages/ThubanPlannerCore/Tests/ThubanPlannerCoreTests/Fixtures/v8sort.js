// V8's Array.prototype.sort (TimSort, third_party/v8/builtins/array-sort.tq) in plain JS, installed over the
// engine's own sort so the golden cases are generated with Chrome/Electron's comparator call order even when this
// runs under JavaScriptCore (whose sort is a merge sort). Mirrors Packages/ThubanPlannerCore/.../V8Sort.swift.
const MIN_GALLOP = 7

function v8sort(arr, comparefn) {
  const cmp = (x, y) => { const v = Number(comparefn(x, y)); return Number.isNaN(v) ? 0 : v }
  const work = arr.slice()
  const st = { minGallop: MIN_GALLOP, base: [], len: [] }
  const n = work.length
  if (n >= 2) {
    let remaining = n, low = 0
    const minRun = (() => { let m = remaining, r = 0; while (m >= 64) { r |= m & 1; m >>= 1 } return m + r })()
    while (remaining !== 0) {
      let cur = countAndMakeRun(low, low + remaining)
      if (cur < minRun) {
        const forced = Math.min(minRun, remaining)
        binaryInsertionSort(low, low + cur, low + forced)
        cur = forced
      }
      st.base.push(low); st.len.push(cur)
      mergeCollapse()
      low += cur; remaining -= cur
    }
    mergeForceCollapse()
  }
  for (let i = 0; i < n; i++) arr[i] = work[i]
  return arr

  function countAndMakeRun(lowArg, high) {
    const lo = lowArg + 1
    if (lo === high) return 1
    let runLength = 2
    const elementLow = work[lo], elementLowPre = work[lo - 1]
    let order = cmp(elementLow, elementLowPre)
    const desc = order < 0
    let prev = elementLow
    for (let idx = lo + 1; idx < high; ++idx) {
      const cur = work[idx]
      order = cmp(cur, prev)
      if (desc) { if (order >= 0) break } else { if (order < 0) break }
      prev = cur; ++runLength
    }
    if (desc) { let a = lowArg, b = lowArg + runLength - 1; while (a < b) { const t = work[a]; work[a] = work[b]; work[b] = t; a++; b-- } }
    return runLength
  }
  function binaryInsertionSort(lo, startArg, high) {
    let start = lo === startArg ? startArg + 1 : startArg
    for (; start < high; ++start) {
      let left = lo, right = start
      const pivot = work[start]
      while (left < right) {
        const mid = left + ((right - left) >> 1)
        const order = cmp(pivot, work[mid])
        if (order < 0) right = mid; else left = mid + 1
      }
      for (let p = start; p > left; --p) work[p] = work[p - 1]
      work[left] = pivot
    }
  }
  function inv(k) { if (k < 2) return true; return st.len[k - 2] > st.len[k - 1] + st.len[k] }
  function mergeCollapse() {
    while (st.len.length > 1) {
      let k = st.len.length - 2
      if (!inv(k + 1) || !inv(k)) { if (st.len[k - 1] < st.len[k + 1]) --k; mergeAt(k) }
      else if (st.len[k] <= st.len[k + 1]) mergeAt(k)
      else break
    }
  }
  function mergeForceCollapse() {
    while (st.len.length > 1) {
      let k = st.len.length - 2
      if (k > 0 && st.len[k - 1] < st.len[k + 1]) --k
      mergeAt(k)
    }
  }
  function mergeAt(i) {
    let baseA = st.base[i], lengthA = st.len[i]
    const baseB = st.base[i + 1]
    let lengthB = st.len[i + 1]
    st.len[i] = lengthA + lengthB
    st.base.splice(i + 1, 1); st.len.splice(i + 1, 1)
    const k = gallopRight(work, work[baseB], baseA, lengthA, 0)
    baseA += k; lengthA -= k
    if (lengthA === 0) return
    lengthB = gallopLeft(work, work[baseA + lengthA - 1], baseB, lengthB, lengthB - 1)
    if (lengthB === 0) return
    if (lengthA <= lengthB) mergeLow(baseA, lengthA, baseB, lengthB)
    else mergeHigh(baseA, lengthA, baseB, lengthB)
  }
  function gallopLeft(array, key, base, length, hint) {
    let lastOfs = 0, offset = 1
    let order = cmp(array[base + hint], key)
    if (order < 0) {
      const maxOfs = length - hint
      while (offset < maxOfs) {
        order = cmp(array[base + hint + offset], key)
        if (order >= 0) break
        lastOfs = offset; offset = (offset << 1) + 1
        if (offset <= 0) offset = maxOfs
      }
      if (offset > maxOfs) offset = maxOfs
      lastOfs += hint; offset += hint
    } else {
      const maxOfs = hint + 1
      while (offset < maxOfs) {
        order = cmp(array[base + hint - offset], key)
        if (order < 0) break
        lastOfs = offset; offset = (offset << 1) + 1
        if (offset <= 0) offset = maxOfs
      }
      if (offset > maxOfs) offset = maxOfs
      const tmp = lastOfs; lastOfs = hint - offset; offset = hint - tmp
    }
    lastOfs++
    while (lastOfs < offset) {
      const m = lastOfs + ((offset - lastOfs) >> 1)
      order = cmp(array[base + m], key)
      if (order < 0) lastOfs = m + 1; else offset = m
    }
    return offset
  }
  function gallopRight(array, key, base, length, hint) {
    let lastOfs = 0, offset = 1
    let order = cmp(key, array[base + hint])
    if (order < 0) {
      const maxOfs = hint + 1
      while (offset < maxOfs) {
        order = cmp(key, array[base + hint - offset])
        if (order >= 0) break
        lastOfs = offset; offset = (offset << 1) + 1
        if (offset <= 0) offset = maxOfs
      }
      if (offset > maxOfs) offset = maxOfs
      const tmp = lastOfs; lastOfs = hint - offset; offset = hint - tmp
    } else {
      const maxOfs = length - hint
      while (offset < maxOfs) {
        order = cmp(key, array[base + hint + offset])
        if (order < 0) break
        lastOfs = offset; offset = (offset << 1) + 1
        if (offset <= 0) offset = maxOfs
      }
      if (offset > maxOfs) offset = maxOfs
      lastOfs += hint; offset += hint
    }
    lastOfs++
    while (lastOfs < offset) {
      const m = lastOfs + ((offset - lastOfs) >> 1)
      order = cmp(key, array[base + m])
      if (order < 0) offset = m; else lastOfs = m + 1
    }
    return offset
  }
  function mergeLow(baseA, lengthAArg, baseB, lengthBArg) {
    let lengthA = lengthAArg, lengthB = lengthBArg
    const temp = work.slice(baseA, baseA + lengthA)
    let dest = baseA, cursorTemp = 0, cursorB = baseB
    const succeed = () => { for (let j = 0; j < lengthA; j++) work[dest + j] = temp[cursorTemp + j] }
    const copyB = () => { for (let j = 0; j < lengthB; j++) work[dest + j] = work[cursorB + j]; work[dest + lengthB] = temp[cursorTemp] }
    work[dest++] = work[cursorB++]
    if (--lengthB === 0) return succeed()
    if (lengthA === 1) return copyB()
    let minGallop = st.minGallop
    for (;;) {
      let winsA = 0, winsB = 0
      for (;;) {
        const order = cmp(work[cursorB], temp[cursorTemp])
        if (order < 0) {
          work[dest++] = work[cursorB++]; ++winsB; --lengthB; winsA = 0
          if (lengthB === 0) return succeed()
          if (winsB >= minGallop) break
        } else {
          work[dest++] = temp[cursorTemp++]; ++winsA; --lengthA; winsB = 0
          if (lengthA === 1) return copyB()
          if (winsA >= minGallop) break
        }
      }
      ++minGallop
      let first = true
      while (winsA >= MIN_GALLOP || winsB >= MIN_GALLOP || first) {
        first = false
        minGallop = Math.max(1, minGallop - 1); st.minGallop = minGallop
        winsA = gallopRight(temp, work[cursorB], cursorTemp, lengthA, 0)
        if (winsA > 0) {
          for (let j = 0; j < winsA; j++) work[dest + j] = temp[cursorTemp + j]
          dest += winsA; cursorTemp += winsA; lengthA -= winsA
          if (lengthA === 1) return copyB()
          if (lengthA === 0) return succeed()
        }
        work[dest++] = work[cursorB++]
        if (--lengthB === 0) return succeed()
        winsB = gallopLeft(work, temp[cursorTemp], cursorB, lengthB, 0)
        if (winsB > 0) {
          for (let j = 0; j < winsB; j++) work[dest + j] = work[cursorB + j]
          dest += winsB; cursorB += winsB; lengthB -= winsB
          if (lengthB === 0) return succeed()
        }
        work[dest++] = temp[cursorTemp++]
        if (--lengthA === 1) return copyB()
      }
      ++minGallop; st.minGallop = minGallop
    }
  }
  function mergeHigh(baseA, lengthAArg, baseB, lengthBArg) {
    let lengthA = lengthAArg, lengthB = lengthBArg
    const temp = work.slice(baseB, baseB + lengthB)
    let dest = baseB + lengthB - 1, cursorTemp = lengthB - 1, cursorA = baseA + lengthA - 1
    const succeed = () => { if (lengthB > 0) { const s = dest - (lengthB - 1); for (let j = 0; j < lengthB; j++) work[s + j] = temp[j] } }
    const copyA = () => {
      dest -= lengthA; cursorA -= lengthA
      for (let j = lengthA - 1; j >= 0; j--) work[dest + 1 + j] = work[cursorA + 1 + j]
      work[dest] = temp[cursorTemp]
    }
    work[dest--] = work[cursorA--]
    if (--lengthA === 0) return succeed()
    if (lengthB === 1) return copyA()
    let minGallop = st.minGallop
    for (;;) {
      let winsA = 0, winsB = 0
      for (;;) {
        const order = cmp(temp[cursorTemp], work[cursorA])
        if (order < 0) {
          work[dest--] = work[cursorA--]; ++winsA; --lengthA; winsB = 0
          if (lengthA === 0) return succeed()
          if (winsA >= minGallop) break
        } else {
          work[dest--] = temp[cursorTemp--]; ++winsB; --lengthB; winsA = 0
          if (lengthB === 1) return copyA()
          if (winsB >= minGallop) break
        }
      }
      ++minGallop
      let first = true
      while (winsA >= MIN_GALLOP || winsB >= MIN_GALLOP || first) {
        first = false
        minGallop = Math.max(1, minGallop - 1); st.minGallop = minGallop
        let k = gallopRight(work, temp[cursorTemp], baseA, lengthA, lengthA - 1)
        winsA = lengthA - k
        if (winsA > 0) {
          dest -= winsA; cursorA -= winsA
          for (let j = winsA - 1; j >= 0; j--) work[dest + 1 + j] = work[cursorA + 1 + j]
          lengthA -= winsA
          if (lengthA === 0) return succeed()
        }
        work[dest--] = temp[cursorTemp--]
        if (--lengthB === 1) return copyA()
        k = gallopLeft(temp, work[cursorA], 0, lengthB, lengthB - 1)
        winsB = lengthB - k
        if (winsB > 0) {
          dest -= winsB; cursorTemp -= winsB
          for (let j = 0; j < winsB; j++) work[dest + 1 + j] = temp[cursorTemp + 1 + j]
          lengthB -= winsB
          if (lengthB === 1) return copyA()
          if (lengthB === 0) return succeed()
        }
        work[dest--] = work[cursorA--]
        if (--lengthA === 0) return succeed()
      }
      ++minGallop; st.minGallop = minGallop
    }
  }
}

const nativeSort = Array.prototype.sort
Array.prototype.sort = function (comparefn) {
  if (typeof comparefn !== 'function') return nativeSort.call(this, comparefn)
  return v8sort(this, comparefn)
}
export { v8sort }
