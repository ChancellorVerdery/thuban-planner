import Foundation

/// `Array.prototype.sort(comparefn)` exactly as V8 (Chrome / Electron, where Atlas runs) performs it: TimSort from
/// `third_party/v8/builtins/array-sort.tq` — `ComputeMinRunLength`, `CountAndMakeRun`, `BinaryInsertionSort`, the
/// run stack with `MergeCollapse` / `MergeForceCollapse`, `MergeAt`, `GallopLeft` / `GallopRight`, `MergeLow` /
/// `MergeHigh` and the adaptive `minGallop` (initially 7).
///
/// Why not `Array.sort`: any stable sort gives the same RESULT for a pure comparator, but Atlas's scheduler sorts
/// with a comparator that lazily memoizes each course's "downstream depth" on first use, and in a requirement cycle
/// (a lecture and its lab listing each other as corequisites) the memoized depth depends on which course was asked
/// first. Reproducing V8's comparator call sequence reproduces those depths, and so the route, bit for bit.
///
/// `compare` returns a JS number; NaN is treated as 0 (V8's `SortCompareUserFn`).
public enum V8Sort {
    public static func sort<T>(_ array: inout [T], by compare: (T, T) -> Double) {
        withoutActuallyEscaping(compare) { compare in
            var state = State(work: array, compare: compare)
            state.timSort()
            array = state.work
        }
    }

    public static func sorted<T>(_ array: [T], by compare: (T, T) -> Double) -> [T] {
        var copy = array
        sort(&copy, by: compare)
        return copy
    }

    private static let minGallopWins = 7

    /// MergeLow / MergeHigh exits: `Succeed`, or `CopyB` / `CopyA` (the other run's leftovers).
    private enum MergeExit { case succeed, copyOther }

    private struct State<T> {
        var work: [T]
        let compareFn: (T, T) -> Double
        var minGallop = V8Sort.minGallopWins
        var runBase: [Int] = []
        var runLength: [Int] = []

        init(work: [T], compare: @escaping (T, T) -> Double) {
            self.work = work
            self.compareFn = compare
        }

        func cmp(_ x: T, _ y: T) -> Double {
            let v = compareFn(x, y)
            return v.isNaN ? 0 : v
        }

        mutating func timSort() {
            let length = work.count
            if length < 2 { return }
            var remaining = length
            var low = 0
            let minRunLength = Self.computeMinRunLength(remaining)
            while remaining != 0 {
                var currentRunLength = countAndMakeRun(low, low + remaining)
                if currentRunLength < minRunLength {
                    let forcedRunLength = Swift.min(minRunLength, remaining)
                    binaryInsertionSort(low, low + currentRunLength, low + forcedRunLength)
                    currentRunLength = forcedRunLength
                }
                runBase.append(low)
                runLength.append(currentRunLength)
                mergeCollapse()
                low += currentRunLength
                remaining -= currentRunLength
            }
            mergeForceCollapse()
        }

        static func computeMinRunLength(_ nArg: Int) -> Int {
            var n = nArg
            var r = 0
            while n >= 64 {
                r |= n & 1
                n >>= 1
            }
            return n + r
        }

        mutating func countAndMakeRun(_ lowArg: Int, _ high: Int) -> Int {
            let low = lowArg + 1
            if low == high { return 1 }
            var runLength = 2
            let elementLow = work[low]
            let elementLowPre = work[low - 1]
            var order = cmp(elementLow, elementLowPre)
            let isDescending = order < 0
            var previous = elementLow
            var idx = low + 1
            while idx < high {
                let current = work[idx]
                order = cmp(current, previous)
                if isDescending {
                    if order >= 0 { break }
                } else {
                    if order < 0 { break }
                }
                previous = current
                runLength += 1
                idx += 1
            }
            if isDescending { work[lowArg ..< lowArg + runLength].reverse() }
            return runLength
        }

        mutating func binaryInsertionSort(_ low: Int, _ startArg: Int, _ high: Int) {
            var start = low == startArg ? startArg + 1 : startArg
            while start < high {
                var left = low
                var right = start
                let pivot = work[start]
                while left < right {
                    let mid = left + ((right - left) >> 1)
                    let order = cmp(pivot, work[mid])
                    if order < 0 { right = mid } else { left = mid + 1 }
                }
                var p = start
                while p > left {
                    work[p] = work[p - 1]
                    p -= 1
                }
                work[left] = pivot
                start += 1
            }
        }

        func runInvariantEstablished(_ n: Int) -> Bool {
            if n < 2 { return true }
            return runLength[n - 2] > runLength[n - 1] + runLength[n]
        }

        mutating func mergeCollapse() {
            while runLength.count > 1 {
                var n = runLength.count - 2
                if !runInvariantEstablished(n + 1) || !runInvariantEstablished(n) {
                    if runLength[n - 1] < runLength[n + 1] { n -= 1 }
                    mergeAt(n)
                } else if runLength[n] <= runLength[n + 1] {
                    mergeAt(n)
                } else {
                    break
                }
            }
        }

        mutating func mergeForceCollapse() {
            while runLength.count > 1 {
                var n = runLength.count - 2
                if n > 0 && runLength[n - 1] < runLength[n + 1] { n -= 1 }
                mergeAt(n)
            }
        }

        mutating func mergeAt(_ i: Int) {
            var baseA = runBase[i]
            var lengthA = runLength[i]
            let baseB = runBase[i + 1]
            var lengthB = runLength[i + 1]
            runLength[i] = lengthA + lengthB
            // Drop run i + 1 (the old i + 2, if any, slides down).
            runBase.remove(at: i + 1)
            runLength.remove(at: i + 1)

            let keyRight = work[baseB]
            let k = gallopRight(work, keyRight, baseA, lengthA, 0)
            baseA += k
            lengthA -= k
            if lengthA == 0 { return }
            let keyLeft = work[baseA + lengthA - 1]
            lengthB = gallopLeft(work, keyLeft, baseB, lengthB, lengthB - 1)
            if lengthB == 0 { return }
            if lengthA <= lengthB {
                mergeLow(baseA, lengthA, baseB, lengthB)
            } else {
                mergeHigh(baseA, lengthA, baseB, lengthB)
            }
        }

        func gallopLeft(_ array: [T], _ key: T, _ base: Int, _ length: Int, _ hint: Int) -> Int {
            var lastOfs = 0
            var offset = 1
            var order = cmp(array[base + hint], key)
            if order < 0 {
                let maxOfs = length - hint
                while offset < maxOfs {
                    order = cmp(array[base + hint + offset], key)
                    if order >= 0 { break }
                    lastOfs = offset
                    offset = (offset << 1) + 1
                    if offset <= 0 { offset = maxOfs }
                }
                if offset > maxOfs { offset = maxOfs }
                lastOfs += hint
                offset += hint
            } else {
                let maxOfs = hint + 1
                while offset < maxOfs {
                    order = cmp(array[base + hint - offset], key)
                    if order < 0 { break }
                    lastOfs = offset
                    offset = (offset << 1) + 1
                    if offset <= 0 { offset = maxOfs }
                }
                if offset > maxOfs { offset = maxOfs }
                let tmp = lastOfs
                lastOfs = hint - offset
                offset = hint - tmp
            }
            lastOfs += 1
            while lastOfs < offset {
                let m = lastOfs + ((offset - lastOfs) >> 1)
                order = cmp(array[base + m], key)
                if order < 0 { lastOfs = m + 1 } else { offset = m }
            }
            return offset
        }

        func gallopRight(_ array: [T], _ key: T, _ base: Int, _ length: Int, _ hint: Int) -> Int {
            var lastOfs = 0
            var offset = 1
            var order = cmp(key, array[base + hint])
            if order < 0 {
                let maxOfs = hint + 1
                while offset < maxOfs {
                    order = cmp(key, array[base + hint - offset])
                    if order >= 0 { break }
                    lastOfs = offset
                    offset = (offset << 1) + 1
                    if offset <= 0 { offset = maxOfs }
                }
                if offset > maxOfs { offset = maxOfs }
                let tmp = lastOfs
                lastOfs = hint - offset
                offset = hint - tmp
            } else {
                let maxOfs = length - hint
                while offset < maxOfs {
                    order = cmp(key, array[base + hint + offset])
                    if order < 0 { break }
                    lastOfs = offset
                    offset = (offset << 1) + 1
                    if offset <= 0 { offset = maxOfs }
                }
                if offset > maxOfs { offset = maxOfs }
                lastOfs += hint
                offset += hint
            }
            lastOfs += 1
            while lastOfs < offset {
                let m = lastOfs + ((offset - lastOfs) >> 1)
                order = cmp(key, array[base + m])
                if order < 0 { offset = m } else { lastOfs = m + 1 }
            }
            return offset
        }

        mutating func mergeLow(_ baseA: Int, _ lengthAArg: Int, _ baseB: Int, _ lengthBArg: Int) {
            var lengthA = lengthAArg
            var lengthB = lengthBArg
            let temp = Array(work[baseA ..< baseA + lengthA])
            var dest = baseA
            var cursorTemp = 0
            var cursorB = baseB

            func finish(_ exit: MergeExit, _ work: inout [T]) {
                switch exit {
                case .succeed:
                    if lengthA > 0 {
                        for j in 0 ..< lengthA { work[dest + j] = temp[cursorTemp + j] }
                    }
                case .copyOther:
                    for j in 0 ..< lengthB { work[dest + j] = work[cursorB + j] }
                    work[dest + lengthB] = temp[cursorTemp]
                }
            }

            work[dest] = work[cursorB]; dest += 1; cursorB += 1
            lengthB -= 1
            if lengthB == 0 { finish(.succeed, &work); return }
            if lengthA == 1 { finish(.copyOther, &work); return }

            var minGallop = self.minGallop
            while true {
                var winsA = 0
                var winsB = 0
                while true {
                    let order = cmp(work[cursorB], temp[cursorTemp])
                    if order < 0 {
                        work[dest] = work[cursorB]; dest += 1; cursorB += 1
                        winsB += 1; lengthB -= 1; winsA = 0
                        if lengthB == 0 { self.minGallop = minGallop; finish(.succeed, &work); return }
                        if winsB >= minGallop { break }
                    } else {
                        work[dest] = temp[cursorTemp]; dest += 1; cursorTemp += 1
                        winsA += 1; lengthA -= 1; winsB = 0
                        if lengthA == 1 { self.minGallop = minGallop; finish(.copyOther, &work); return }
                        if winsA >= minGallop { break }
                    }
                }
                minGallop += 1
                var first = true
                while winsA >= V8Sort.minGallopWins || winsB >= V8Sort.minGallopWins || first {
                    first = false
                    minGallop = Swift.max(1, minGallop - 1)
                    self.minGallop = minGallop
                    winsA = gallopRight(temp, work[cursorB], cursorTemp, lengthA, 0)
                    if winsA > 0 {
                        for j in 0 ..< winsA { work[dest + j] = temp[cursorTemp + j] }
                        dest += winsA; cursorTemp += winsA; lengthA -= winsA
                        if lengthA == 1 { finish(.copyOther, &work); return }
                        if lengthA == 0 { finish(.succeed, &work); return }
                    }
                    work[dest] = work[cursorB]; dest += 1; cursorB += 1
                    lengthB -= 1
                    if lengthB == 0 { finish(.succeed, &work); return }
                    winsB = gallopLeft(work, temp[cursorTemp], cursorB, lengthB, 0)
                    if winsB > 0 {
                        for j in 0 ..< winsB { work[dest + j] = work[cursorB + j] }
                        dest += winsB; cursorB += winsB; lengthB -= winsB
                        if lengthB == 0 { finish(.succeed, &work); return }
                    }
                    work[dest] = temp[cursorTemp]; dest += 1; cursorTemp += 1
                    lengthA -= 1
                    if lengthA == 1 { finish(.copyOther, &work); return }
                }
                minGallop += 1
                self.minGallop = minGallop
            }
        }

        mutating func mergeHigh(_ baseA: Int, _ lengthAArg: Int, _ baseB: Int, _ lengthBArg: Int) {
            var lengthA = lengthAArg
            var lengthB = lengthBArg
            let temp = Array(work[baseB ..< baseB + lengthB])
            var dest = baseB + lengthB - 1
            var cursorTemp = lengthB - 1
            var cursorA = baseA + lengthA - 1

            func finish(_ exit: MergeExit, _ work: inout [T]) {
                switch exit {
                case .succeed:
                    if lengthB > 0 {
                        let start = dest - (lengthB - 1)
                        for j in 0 ..< lengthB { work[start + j] = temp[j] }
                    }
                case .copyOther:
                    dest -= lengthA
                    cursorA -= lengthA
                    // Copy(workArray, cursorA + 1, workArray, dest + 1, lengthA) — overlapping, copy backwards.
                    var j = lengthA - 1
                    while j >= 0 {
                        work[dest + 1 + j] = work[cursorA + 1 + j]
                        j -= 1
                    }
                    work[dest] = temp[cursorTemp]
                }
            }

            work[dest] = work[cursorA]; dest -= 1; cursorA -= 1
            lengthA -= 1
            if lengthA == 0 { finish(.succeed, &work); return }
            if lengthB == 1 { finish(.copyOther, &work); return }

            var minGallop = self.minGallop
            while true {
                var winsA = 0
                var winsB = 0
                while true {
                    let order = cmp(temp[cursorTemp], work[cursorA])
                    if order < 0 {
                        work[dest] = work[cursorA]; dest -= 1; cursorA -= 1
                        winsA += 1; lengthA -= 1; winsB = 0
                        if lengthA == 0 { self.minGallop = minGallop; finish(.succeed, &work); return }
                        if winsA >= minGallop { break }
                    } else {
                        work[dest] = temp[cursorTemp]; dest -= 1; cursorTemp -= 1
                        winsB += 1; lengthB -= 1; winsA = 0
                        if lengthB == 1 { self.minGallop = minGallop; finish(.copyOther, &work); return }
                        if winsB >= minGallop { break }
                    }
                }
                minGallop += 1
                var first = true
                while winsA >= V8Sort.minGallopWins || winsB >= V8Sort.minGallopWins || first {
                    first = false
                    minGallop = Swift.max(1, minGallop - 1)
                    self.minGallop = minGallop
                    var k = gallopRight(work, temp[cursorTemp], baseA, lengthA, lengthA - 1)
                    winsA = lengthA - k
                    if winsA > 0 {
                        dest -= winsA
                        cursorA -= winsA
                        var j = winsA - 1
                        while j >= 0 {
                            work[dest + 1 + j] = work[cursorA + 1 + j]
                            j -= 1
                        }
                        lengthA -= winsA
                        if lengthA == 0 { finish(.succeed, &work); return }
                    }
                    work[dest] = temp[cursorTemp]; dest -= 1; cursorTemp -= 1
                    lengthB -= 1
                    if lengthB == 1 { finish(.copyOther, &work); return }
                    k = gallopLeft(temp, work[cursorA], 0, lengthB, lengthB - 1)
                    winsB = lengthB - k
                    if winsB > 0 {
                        dest -= winsB
                        cursorTemp -= winsB
                        for j in 0 ..< winsB { work[dest + 1 + j] = temp[cursorTemp + 1 + j] }
                        lengthB -= winsB
                        if lengthB == 1 { finish(.copyOther, &work); return }
                        if lengthB == 0 { finish(.succeed, &work); return }
                    }
                    work[dest] = work[cursorA]; dest -= 1; cursorA -= 1
                    lengthA -= 1
                    if lengthA == 0 { finish(.succeed, &work); return }
                }
                minGallop += 1
                self.minGallop = minGallop
            }
        }
    }
}
