import Foundation

/// Word Block matching engine. Implements docs/WORD_BLOCK_SPEC.md and mirrors
/// Browser/Resources/wordblock-engine.js function-for-function. Both are
/// verified against Tests/wordblock-vectors.json (Tests/run-node.js,
/// Tests/run-swift.sh). Foundation-only so it also builds on Linux for tests.
struct WordBlockEngine {
    struct Entry {
        let word: String
        let substring: Bool
    }

    private struct Run {
        let ch: Unicode.Scalar
        var n: Int
    }

    private struct Pattern {
        let runs: [Run]
        let substring: Bool
        let fuzzy: Bool
    }

    private struct Node {
        let cands: [Unicode.Scalar]
        let raw: Unicode.Scalar
        let start: Int      // UTF-16 offset in the original text
        var end: Int
        let token: Int
        let symbol: Bool
    }

    private struct Analysis {
        var nodes: [Node]
        var tokStart: [Int]
        var tokEnd: [Int]
        var lastVisibleEnd: Int
    }

    private final class Context {
        let an: Analysis
        let text: [UInt16]
        let pat: Pattern
        let start: Int
        let isFinal: Bool
        let allow: Set<String>
        let maxErrs: Int

        init(an: Analysis, text: [UInt16], pat: Pattern, start: Int, isFinal: Bool, allow: Set<String>, maxErrs: Int) {
            self.an = an
            self.text = text
            self.pat = pat
            self.start = start
            self.isFinal = isFinal
            self.allow = allow
            self.maxErrs = maxErrs
        }
    }

    // MARK: Tables (spec §1, §2)

    private static let invisibleRanges: [ClosedRange<UInt32>] = [
        0x00AD...0x00AD, 0x034F...0x034F, 0x061C...0x061C, 0x115F...0x1160,
        0x17B4...0x17B5, 0x180B...0x180F, 0x200B...0x200F, 0x202A...0x202E,
        0x2060...0x206F, 0x3164...0x3164, 0xFE00...0xFE0F, 0xFEFF...0xFEFF,
        0xFFA0...0xFFA0, 0xE0000...0xE007F
    ]

    /// Cyrillic, Greek and Latin look-alikes (same code points as the JS engine).
    private static let confusables: [UInt32: String] = [
        0x0430: "a", 0x0432: "b", 0x0435: "e", 0x043A: "k", 0x043C: "m", 0x043D: "h",
        0x043E: "o", 0x0440: "p", 0x0441: "c", 0x0442: "t", 0x0443: "y", 0x0445: "x",
        0x0455: "s", 0x0456: "i", 0x0458: "j", 0x0501: "d", 0x051B: "q", 0x051D: "w",
        0x04BB: "h", 0x04CF: "l", 0x044C: "b", 0x043F: "n", 0x0433: "r", 0x03B1: "a",
        0x03B2: "b", 0x03B3: "y", 0x03B5: "e", 0x03B6: "z", 0x03B7: "n", 0x03B9: "i",
        0x03BA: "k", 0x03BD: "v", 0x03BF: "o", 0x03C1: "p", 0x03C4: "t", 0x03C5: "u",
        0x03C7: "x", 0x03C9: "w", 0x03C2: "s", 0x0131: "i", 0x0269: "i", 0x0142: "l",
        0x00F8: "o", 0x0111: "d", 0x0261: "g", 0x0251: "a", 0x00DF: "ss", 0x00E6: "ae",
        0x0153: "oe", 0x0280: "r", 0x0274: "n", 0x1D0F: "o", 0x1D18: "p", 0xA731: "s",
        0x1D07: "e"
    ]

    private static let leet: [Unicode.Scalar: String] = [
        "4": "a", "@": "a", "8": "b", "(": "c", "<": "c", "3": "e", "6": "g", "9": "g",
        "1": "il", "!": "i", "|": "il", "0": "o", "5": "s", "$": "s", "7": "t", "+": "t", "2": "z"
    ]

    private static let symbolLeet: Set<Unicode.Scalar> = ["@", "(", "<", "!", "|", "$", "+"]

    private static let maxPasses = 4
    private static let fuzzyMinLength = 5

    private let patterns: [Pattern]
    private let allow: Set<String>

    // MARK: Compile

    init(words: [Entry], allowlist: [String]) {
        var patterns: [Pattern] = []
        for word in words {
            let key = Self.normalizeKey(word.word)
            guard !key.isEmpty else { continue }
            patterns.append(Pattern(runs: Self.toRuns(key),
                                    substring: word.substring,
                                    fuzzy: key.count >= Self.fuzzyMinLength))
        }
        self.patterns = patterns
        var allow = Set<String>()
        for entry in allowlist {
            let key = Self.normalizeKey(entry)
            if !key.isEmpty { allow.insert(Self.string(key)) }
        }
        self.allow = allow
    }

    // MARK: Public

    /// Removes blocked words. `isFinal` = the text is complete (submit/blur);
    /// otherwise whole-word, multi-word and fuzzy matches wait for a following character.
    func sanitize(_ text: String, isFinal: Bool) -> String {
        guard !patterns.isEmpty, !text.isEmpty else { return text }
        var out = text
        for _ in 0..<Self.maxPasses {
            let spans = findSpans(out, isFinal: isFinal)
            if spans.isEmpty { break }
            var units = Array(out.utf16)
            for span in spans.reversed() {
                units.removeSubrange(span.0..<span.1)
            }
            out = String(decoding: units, as: UTF16.self)
        }
        return out
    }

    /// Folds a whole string (invisible chars removed, NFKD, marks stripped,
    /// lowercased, confusables mapped). Used by Blocked Sites for domains.
    static func foldText(_ str: String) -> String {
        var out: [Unicode.Scalar] = []
        for scalar in str.unicodeScalars where !isInvisible(scalar.value) {
            out.append(contentsOf: fold(scalar))
        }
        return string(out)
    }

    // MARK: Normalization

    private static func isInvisible(_ value: UInt32) -> Bool {
        invisibleRanges.contains { $0.contains(value) }
    }

    private static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }

    private static func isLetterOrNumber(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    private static func isAsciiLetter(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 0x61 && scalar.value <= 0x7A
    }

    /// One original scalar → folded scalars (possibly none or several).
    private static func fold(_ scalar: Unicode.Scalar) -> [Unicode.Scalar] {
        let decomposed = String(scalar).decomposedStringWithCompatibilityMapping
        var stripped = String.UnicodeScalarView()
        for s in decomposed.unicodeScalars where !isMark(s) {
            stripped.append(s)
        }
        let lower = String(stripped).lowercased()
        var out: [Unicode.Scalar] = []
        for s in lower.unicodeScalars {
            if let mapped = confusables[s.value] {
                out.append(contentsOf: mapped.unicodeScalars)
            } else {
                out.append(s)
            }
        }
        return out
    }

    private static func classify(_ c: Unicode.Scalar) -> (cands: [Unicode.Scalar], symbol: Bool)? {
        if let letters = leet[c] {
            return (Array(letters.unicodeScalars) + [c], symbolLeet.contains(c))
        }
        if isLetterOrNumber(c) { return ([c], false) }
        return nil
    }

    private static func analyze(_ text: String) -> Analysis {
        var nodes: [Node] = []
        var token = -1
        var inToken = false
        var idx = 0
        var lastVisibleEnd = 0
        for scalar in text.unicodeScalars {
            let start = idx
            idx += scalar.utf16.count
            let folded = isInvisible(scalar.value) ? [] : fold(scalar)
            if folded.isEmpty {
                // Invisible char or lone combining mark: attach to the preceding node.
                if inToken && !nodes.isEmpty { nodes[nodes.count - 1].end = idx }
                continue
            }
            lastVisibleEnd = idx
            for c in folded {
                guard let k = classify(c) else {
                    inToken = false
                    continue
                }
                if !inToken {
                    token += 1
                    inToken = true
                }
                nodes.append(Node(cands: k.cands, raw: c, start: start, end: idx, token: token, symbol: k.symbol))
            }
        }
        var tokStart = [Int](repeating: -1, count: token + 1)
        var tokEnd = [Int](repeating: 0, count: token + 1)
        for (i, node) in nodes.enumerated() {
            if tokStart[node.token] == -1 { tokStart[node.token] = i }
            tokEnd[node.token] = i + 1
        }
        return Analysis(nodes: nodes, tokStart: tokStart, tokEnd: tokEnd, lastVisibleEnd: lastVisibleEnd)
    }

    private static func normalizeKey(_ str: String) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        for scalar in str.unicodeScalars {
            if isInvisible(scalar.value) { continue }
            for c in fold(scalar) where classify(c) != nil {
                out.append(c)
            }
        }
        return out
    }

    private static func toRuns(_ key: [Unicode.Scalar]) -> [Run] {
        var runs: [Run] = []
        for c in key {
            if let last = runs.last, last.ch == c {
                runs[runs.count - 1].n += 1
            } else {
                runs.append(Run(ch: c, n: 1))
            }
        }
        return runs
    }

    private static func string(_ scalars: [Unicode.Scalar]) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    // MARK: Matching

    private static func unit(_ nodes: [Node], _ i: Int, _ letter: Unicode.Scalar) -> Int {
        if i < nodes.count && nodes[i].cands.contains(letter) { return i + 1 }
        if letter == "f" && i + 1 < nodes.count &&
            nodes[i].cands.contains("p") && nodes[i + 1].cands.contains("h") { return i + 2 }
        return -1
    }

    private static func allSymbols(_ nodes: [Node], _ from: Int, _ to: Int) -> Bool {
        var i = from
        while i < to {
            if !nodes[i].symbol { return false }
            i += 1
        }
        return true
    }

    private static func tokenKey(_ an: Analysis, _ t: Int) -> String {
        var from = an.tokStart[t]
        var to = an.tokEnd[t]
        while from < to && an.nodes[from].symbol { from += 1 }
        while to > from && an.nodes[to - 1].symbol { to -= 1 }
        return string(an.nodes[from..<to].map(\.raw))
    }

    private static func acceptMatch(_ ctx: Context, _ s: Int, _ e: Int, _ fuzzyUsed: Bool) -> Bool {
        let an = ctx.an
        let nodes = an.nodes
        if e <= s { return false }
        let st = nodes[s].token
        let et = nodes[e - 1].token
        let multi = st != et
        let leftBounded = allSymbols(nodes, an.tokStart[st], s)
        let rightBounded = allSymbols(nodes, e, an.tokEnd[et])
        if !ctx.pat.substring && !(leftBounded && rightBounded) { return false }
        if ctx.pat.substring && multi && !leftBounded { return false }
        if !ctx.isFinal && (!ctx.pat.substring || multi || fuzzyUsed) && !(nodes[e - 1].end < an.lastVisibleEnd) {
            return false
        }
        if fuzzyUsed {
            // Fuzzy needs evidence of obfuscation: something besides ASCII letters.
            let span = ctx.text[nodes[s].start..<nodes[e - 1].end]
            let plain = span.allSatisfy { ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) }
            if plain { return false }
        }
        var t = st
        while t <= et {
            if ctx.allow.contains(tokenKey(an, t)) { return false }
            t += 1
        }
        return true
    }

    private static func rec(_ ctx: Context, _ ri: Int, _ ni: Int, _ errs: Int) -> Int {
        let nodes = ctx.an.nodes
        let runs = ctx.pat.runs
        if ri == runs.count {
            if acceptMatch(ctx, ctx.start, ni, errs < ctx.maxErrs) { return ni }
            // Insertion at the end (e.g. a plural "s").
            if errs > 0 && ni < nodes.count { return rec(ctx, ri, ni + 1, errs - 1) }
            return -1
        }
        let run = runs[ri]
        var ends: [Int] = []
        var pos = ni
        while ends.count < 64 {
            let next = unit(nodes, pos, run.ch)
            if next < 0 { break }
            ends.append(next)
            pos = next
        }
        // Prefer repeats inside the current word, then across separators.
        var sameToken = 0
        while sameToken < ends.count && nodes[ends[sameToken] - 1].token == nodes[ni].token {
            sameToken += 1
        }
        var r: Int
        var j = sameToken
        while j >= run.n {
            r = rec(ctx, ri + 1, ends[j - 1], errs)
            if r >= 0 { return r }
            j -= 1
        }
        var k = max(sameToken + 1, run.n)
        while k <= ends.count {
            r = rec(ctx, ri + 1, ends[k - 1], errs)
            if r >= 0 { return r }
            k += 1
        }
        if errs > 0 && ri > 0 {
            // Substitution by a non-letter (leet/symbol/other script) node.
            if run.n == 1 && ni < nodes.count && !isAsciiLetter(nodes[ni].raw) {
                r = rec(ctx, ri + 1, ni + 1, errs - 1)
                if r >= 0 { return r }
            }
            // Transposition of two single-letter runs.
            if run.n == 1 && ri + 1 < runs.count && runs[ri + 1].n == 1 {
                let a = unit(nodes, ni, runs[ri + 1].ch)
                let b = a >= 0 ? unit(nodes, a, run.ch) : -1
                if b >= 0 {
                    r = rec(ctx, ri + 2, b, errs - 1)
                    if r >= 0 { return r }
                }
            }
            // Deletion: this run is missing from the text.
            r = rec(ctx, ri + 1, ni, errs - 1)
            if r >= 0 { return r }
            // Insertion: one extra node in the text.
            if ni < nodes.count {
                r = rec(ctx, ri, ni + 1, errs - 1)
                if r >= 0 { return r }
            }
        }
        return -1
    }

    private func findSpans(_ text: String, isFinal: Bool) -> [(Int, Int)] {
        let an = Self.analyze(text)
        let nodes = an.nodes
        let utf16 = Array(text.utf16)
        var spans: [(Int, Int)] = []
        var s = 0
        while s < nodes.count {
            var best = -1
            for pat in patterns {
                if Self.unit(nodes, s, pat.runs[0].ch) < 0 { continue }
                let maxErrs = pat.fuzzy ? 1 : 0
                for errs in 0...maxErrs {
                    let ctx = Context(an: an, text: utf16, pat: pat, start: s, isFinal: isFinal, allow: allow, maxErrs: errs)
                    let e = Self.rec(ctx, 0, s, errs)
                    if e >= 0 {
                        if e > best { best = e }
                        break
                    }
                }
            }
            if best > s {
                spans.append((nodes[s].start, nodes[best - 1].end))
                s = best
            } else {
                s += 1
            }
        }
        return spans
    }
}
