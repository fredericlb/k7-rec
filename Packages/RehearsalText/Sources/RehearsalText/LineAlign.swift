// LineAlign.swift: order-keeping alignment of two lists of normalised lines by similarity.
// Ported from packages/lyrics/src/lrc.ts; a score is compared for EQUALITY on the way back, so
// the arithmetic order here is the TS's on purpose.

import Foundation

/// A pairing allowing different LINE BREAKS: a run of `ni` sheet lines against `nj` fetched ones.
public struct Span: Equatable, Sendable {
    public var i: Int
    public var ni: Int
    public var j: Int
    public var nj: Int
}

public enum LineAlign {
    // Levenshtein over UTF-16 units, like fastest-levenshtein on a JS string.
    static func distance(_ a: String, _ b: String) -> Int {
        let x = Array(a.utf16)
        let y = Array(b.utf16)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        var cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                let sub = prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1)
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, sub)
            }
            swap(&prev, &cur)
        }
        return prev[y.count]
    }

    /// How alike two normalised lines are, from 0 to 1.
    public static func similarity(_ a: String, _ b: String) -> Double {
        let longest = max(a.utf16Count, b.utf16Count)
        return longest == 0 ? 1 : 1 - Double(distance(a, b)) / Double(longest)
    }

    /// Pairs (i, j) matching `a[i]` with `b[j]`, in order on both sides, scoring the most similarity.
    public static func alignLines(_ a: [String], _ b: [String], threshold: Double) -> [(Int, Int)] {
        let rows = a.count
        let cols = b.count
        var score = [[Double]](repeating: [Double](repeating: 0, count: cols + 1), count: rows + 1)
        var sim = [[Double]](repeating: [Double](repeating: 0, count: cols), count: rows)
        if rows > 0 && cols > 0 {
            for i in 1...rows {
                for j in 1...cols {
                    let s = similarity(a[i - 1], b[j - 1])
                    sim[i - 1][j - 1] = s
                    let pair = s >= threshold ? score[i - 1][j - 1] + s : -1
                    score[i][j] = max(score[i - 1][j], score[i][j - 1], pair)
                }
            }
        }
        var pairs: [(Int, Int)] = []
        var i = rows
        var j = cols
        while i > 0 && j > 0 {
            let s = sim[i - 1][j - 1]
            if s >= threshold && score[i][j] == score[i - 1][j - 1] + s {
                pairs.append((i - 1, j - 1))
                i -= 1
                j -= 1
            } else if score[i][j] == score[i - 1][j] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return pairs.reversed()
    }

    private enum Step {
        case up, left
        case span(Span)
    }

    /// Spans in order on both sides; a two-line span must beat either line alone, see docs/text.md.
    public static func alignSpans(_ a: [String], _ b: [String], threshold: Double, joinable: [Bool] = []) -> [Span] {
        func joined(_ xs: [String], _ ok: (Int) -> Bool) -> [String] {
            xs.indices.map { k in k + 1 < xs.count && ok(k) ? "\(xs[k]) \(xs[k + 1])" : "" }
        }
        let a2 = joined(a) { k in k < joinable.count ? joinable[k] : true }
        let b2 = joined(b) { _ in true }
        let rows = a.count
        let cols = b.count
        var score = [[Double]](repeating: [Double](repeating: 0, count: cols + 1), count: rows + 1)
        var step = [[Step?]](repeating: [Step?](repeating: nil, count: cols + 1), count: rows + 1)
        let shapes = [(1, 1), (1, 2), (2, 1)]
        for i in 0...rows {
            for j in 0...cols {
                if i == 0 && j == 0 { continue }
                var best = -Double.infinity
                var pick: Step?
                if i > 0 && score[i - 1][j] > best {
                    best = score[i - 1][j]
                    pick = .up
                }
                if j > 0 && score[i][j - 1] > best {
                    best = score[i][j - 1]
                    pick = .left
                }
                for (ni, nj) in shapes {
                    if i < ni || j < nj { continue }
                    let left = ni == 1 ? a[i - ni] : a2[i - ni]
                    let right = nj == 1 ? b[j - nj] : b2[j - nj]
                    if left.isEmpty || right.isEmpty { continue }
                    let s = similarity(left, right)
                    if s < threshold { continue }
                    if ni + nj > 2 {
                        let alone =
                            ni == 2
                            ? max(similarity(a[i - 2], b[j - 1]), similarity(a[i - 1], b[j - 1]))
                            : max(similarity(a[i - 1], b[j - 2]), similarity(a[i - 1], b[j - 1]))
                        if s <= alone { continue }
                    }
                    // Weighted by the lines it covers, so a split explaining both halves beats half of it.
                    let v = score[i - ni][j - nj] + (s * Double(ni + nj)) / 2
                    if v > best {
                        best = v
                        pick = .span(Span(i: i - ni, ni: ni, j: j - nj, nj: nj))
                    }
                }
                score[i][j] = best
                step[i][j] = pick
            }
        }
        var spans: [Span] = []
        var i = rows
        var j = cols
        while i > 0 || j > 0 {
            guard let s = step[i][j] else { break }
            switch s {
            case .up: i -= 1
            case .left: j -= 1
            case .span(let sp):
                spans.append(sp)
                i = sp.i
                j = sp.j
            }
        }
        return spans.reversed()
    }
}
