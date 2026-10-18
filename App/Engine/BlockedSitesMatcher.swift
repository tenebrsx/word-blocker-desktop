import Foundation

/// Blocked Sites matching (docs/BLOCKED_SITES_SPEC.md). Mirrors
/// Browser/Resources/blocked-sites-engine.js; both are verified against
/// Tests/blocked-sites-vectors.json. Foundation-only (builds on Linux for tests).
struct BlockedSitesMatcher {
    private static let redirectKeys: Set<String> = [
        "q", "url", "u", "uddg", "target", "dest", "destination", "redirect", "redirect_url", "to", "link", "r"
    ]
    private static let maxDepth = 2

    private let exact: Set<String>
    private let globs: [String]

    init(patterns: [String]) {
        var exact = Set<String>()
        var globs: [String] = []
        for raw in patterns {
            let p = Self.normalizeHost(raw)
            if p.isEmpty || p == "*" { continue }
            if p.contains("*") {
                if !globs.contains(p) { globs.append(p) }
            } else {
                exact.insert(p)
            }
        }
        self.exact = exact
        self.globs = globs
    }

    /// The normalized pattern blocking `url` (checking redirect/search-result
    /// links too), or nil.
    func match(_ url: String) -> String? {
        match(url, depth: 0)
    }

    private func match(_ url: String, depth: Int) -> String? {
        if let hit = matchHost(Self.normalizeHost(url)) { return hit }
        if depth >= Self.maxDepth { return nil }
        for inner in Self.embeddedURLs(url) {
            if let hit = match(inner, depth: depth + 1) { return hit }
        }
        return nil
    }

    func matchHost(_ host: String) -> String? {
        if host.isEmpty { return nil }
        var suffix = Substring(host)
        while true {
            if exact.contains(String(suffix)) { return String(suffix) }
            guard let dot = suffix.firstIndex(of: ".") else { break }
            suffix = suffix[suffix.index(after: dot)...]
        }
        for glob in globs {
            var candidate = Substring(host)
            while true {
                if Self.globMatch(glob, String(candidate)) { return glob }
                guard let dot = candidate.firstIndex(of: ".") else { break }
                candidate = candidate[candidate.index(after: dot)...]
            }
        }
        return nil
    }

    // MARK: Normalization

    /// URL, host or pattern → normalized host (or pattern, keeping "*").
    static func normalizeHost(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let scheme = s.range(of: "://") { s = String(s[scheme.upperBound...]) }
        while s.hasPrefix("/") { s.removeFirst() }
        if let cut = s.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) { s = String(s[..<cut]) }
        if let at = s.lastIndex(of: "@") { s = String(s[s.index(after: at)...]) }
        if let colon = s.lastIndex(of: ":"),
           s[s.index(after: colon)...].allSatisfy({ $0.isASCII && $0.isNumber }) {
            s = String(s[..<colon])
        }
        if let decoded = s.removingPercentEncoding { s = decoded }
        s = s.replacingOccurrences(of: "\u{3002}", with: ".")
            .replacingOccurrences(of: "\u{FF0E}", with: ".")
            .replacingOccurrences(of: "\u{FF61}", with: ".")
        let labels = s.components(separatedBy: ".").map { label -> String in
            if label.lowercased().hasPrefix("xn--"), let decoded = punycodeDecode(String(label.dropFirst(4))) {
                return decoded
            }
            return label
        }
        s = WordBlockEngine.foldText(labels.joined(separator: "."))
        while s.hasPrefix(".") { s.removeFirst() }
        while s.hasSuffix(".") { s.removeLast() }
        if s.hasPrefix("www") {
            let rest = s.dropFirst(3)
            let digits = rest.prefix { $0.isASCII && $0.isNumber }
            let afterDigits = rest.dropFirst(digits.count)
            if afterDigits.hasPrefix(".") { s = String(afterDigits.dropFirst()) }
        }
        return s
    }

    // MARK: Punycode (RFC 3492) decoding

    private static func adapt(_ delta: Int, _ numPoints: Int, _ first: Bool) -> Int {
        var delta = first ? delta / 700 : delta / 2
        delta += delta / numPoints
        var k = 0
        while delta > 455 {
            delta /= 35
            k += 36
        }
        return k + (36 * delta) / (delta + 38)
    }

    private static func digitValue(_ c: UInt8) -> Int {
        if c >= 48 && c <= 57 { return Int(c) - 22 }
        if c >= 65 && c <= 90 { return Int(c) - 65 }
        if c >= 97 && c <= 122 { return Int(c) - 97 }
        return 36
    }

    /// Decoded label, or nil if invalid.
    static func punycodeDecode(_ input: String) -> String? {
        let bytes = Array(input.utf8)
        guard bytes.count == input.unicodeScalars.count else { return nil } // must be ASCII
        var output: [UInt32] = []
        var pos = 0
        if let b = bytes.lastIndex(of: UInt8(ascii: "-")) {
            for j in 0..<b { output.append(UInt32(bytes[j])) }
            pos = b + 1
        }
        var n = 128
        var i = 0
        var bias = 72
        while pos < bytes.count {
            let oldi = i
            var w = 1
            var k = 36
            while true {
                if pos >= bytes.count { return nil }
                let digit = digitValue(bytes[pos])
                pos += 1
                if digit >= 36 { return nil }
                i += digit * w
                if i > 0x10FFFF * 64 { return nil }
                let t = k <= bias ? 1 : (k >= bias + 26 ? 26 : k - bias)
                if digit < t { break }
                w *= 36 - t
                k += 36
            }
            let len = output.count + 1
            bias = adapt(i - oldi, len, oldi == 0)
            n += i / len
            i %= len
            if n > 0x10FFFF { return nil }
            output.insert(UInt32(n), at: i)
            i += 1
        }
        var view = String.UnicodeScalarView()
        for value in output {
            guard let scalar = Unicode.Scalar(value) else { return nil }
            view.append(scalar)
        }
        return String(view)
    }

    // MARK: Glob & redirects

    static func globMatch(_ pattern: String, _ text: String) -> Bool {
        let p = Array(pattern.unicodeScalars)
        let s = Array(text.unicodeScalars)
        var pi = 0, si = 0, star = -1, mark = 0
        while si < s.count {
            if pi < p.count && p[pi] != "*" && p[pi] == s[si] {
                pi += 1
                si += 1
            } else if pi < p.count && p[pi] == "*" {
                star = pi
                pi += 1
                mark = si
            } else if star != -1 {
                pi = star + 1
                mark += 1
                si = mark
            } else {
                return false
            }
        }
        while pi < p.count && p[pi] == "*" { pi += 1 }
        return pi == p.count
    }

    /// URLs embedded in redirector / search-result links.
    static func embeddedURLs(_ url: String) -> [String] {
        guard let q = url.firstIndex(of: "?") else { return [] }
        var query = url[url.index(after: q)...]
        if let hash = query.firstIndex(of: "#") { query = query[..<hash] }
        var found: [String] = []
        for pair in query.split(separator: "&", omittingEmptySubsequences: false) {
            guard let eq = pair.firstIndex(of: "="), eq > pair.startIndex else { continue }
            let key = pair[..<eq].lowercased()
            guard redirectKeys.contains(key) else { continue }
            var value = String(pair[pair.index(after: eq)...])
            if let decoded = value.removingPercentEncoding { value = decoded }
            if key == "u" && value.hasPrefix("a1"), let decoded = base64URLDecode(String(value.dropFirst(2))) {
                value = decoded
            }
            let lower = value.lowercased()
            if lower.hasPrefix("http://") || lower.hasPrefix("https://") { found.append(value) }
        }
        return found
    }

    private static func base64URLDecode(_ str: String) -> String? {
        var b = str.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard let data = Data(base64Encoded: b) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
