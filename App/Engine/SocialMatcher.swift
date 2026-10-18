import Foundation

/// Social Media gate: built-in default list, pattern normalization and URL
/// matching. Foundation-only (builds on Linux for tests).
///
/// A pattern is a host ("instagram.com", subdomains included) optionally
/// followed by a path prefix ("youtube.com/shorts" matches /shorts and
/// /shorts/…, but not the rest of YouTube).
enum SocialDefaults {
    /// Shipped list. Editable by the user (adding is instant; removing waits
    /// out the Self-Control Lock). Redirect/short-link domains (t.co, redd.it,
    /// discord.gg, pin.it) are left out on purpose: they forward to a listed
    /// site, which is gated when it loads, and gating them would also catch
    /// links to unrelated sites.
    static let sites: [String] = [
        "instagram.com",
        "tiktok.com",
        "facebook.com", "fb.com", "fb.watch", "messenger.com",
        "x.com", "twitter.com",
        "snapchat.com",
        "reddit.com",
        "threads.net", "threads.com",
        "youtube.com/shorts",
        "pinterest.com",
        "tumblr.com",
        "linkedin.com",
        "discord.com",
        "bere.al", "bereal.com",
        "twitch.tv",
        "bsky.app",
    ]

    static let message = "Is this how you want to spend the next few minutes? Going back is always okay."
}

struct SocialSiteMatcher {
    private struct Rule {
        let pattern: String
        let host: String
        let path: String?
    }

    private let rules: [Rule]

    init(patterns: [String]) {
        var seen = Set<String>()
        var rules: [Rule] = []
        for raw in patterns {
            let p = Self.normalizePattern(raw)
            guard !p.isEmpty, seen.insert(p).inserted else { continue }
            let (host, path) = Self.split(p)
            guard !host.isEmpty, host.contains(".") else { continue }
            rules.append(Rule(pattern: p, host: host, path: path))
        }
        // Path rules first, so "youtube.com/shorts" wins over a user's "youtube.com".
        self.rules = rules.filter { $0.path != nil } + rules.filter { $0.path == nil }
    }

    /// The normalized pattern gating `url`, or nil. Only http(s).
    func match(_ url: URL) -> String? {
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else { return nil }
        let host = BlockedSitesMatcher.normalizeHost(url.absoluteString)
        guard !host.isEmpty else { return nil }
        let path = url.path.lowercased()
        for rule in rules {
            guard host == rule.host || host.hasSuffix("." + rule.host) else { continue }
            if let prefix = rule.path {
                guard path == prefix || path.hasPrefix(prefix + "/") else { continue }
            }
            return rule.pattern
        }
        return nil
    }

    func match(_ string: String) -> String? {
        guard let url = URL(string: string) else { return nil }
        return match(url)
    }

    // MARK: Normalization

    /// URL, host or pattern → "host" or "host/path" (lowercased, no scheme,
    /// no www, no query/fragment, no trailing slash). Empty if invalid.
    static func normalizePattern(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty || s.contains(" ") { return "" }
        if let scheme = s.range(of: "://") { s = String(s[scheme.upperBound...]) }
        while s.hasPrefix("/") { s.removeFirst() }
        if let cut = s.firstIndex(where: { $0 == "?" || $0 == "#" }) { s = String(s[..<cut]) }
        var path = ""
        if let slash = s.firstIndex(of: "/") {
            path = String(s[slash...]).lowercased()
            s = String(s[..<slash])
        }
        let host = BlockedSitesMatcher.normalizeHost(s)
        guard !host.isEmpty, !host.contains("*") else { return "" }
        while path.hasSuffix("/") { path.removeLast() }
        if let decoded = path.removingPercentEncoding { path = decoded }
        return host + path
    }

    private static func split(_ pattern: String) -> (String, String?) {
        guard let slash = pattern.firstIndex(of: "/") else { return (pattern, nil) }
        return (String(pattern[..<slash]), String(pattern[slash...]))
    }
}
