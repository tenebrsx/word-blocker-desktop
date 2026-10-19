import Foundation

/// GitHub Releases: repo constant, JSON model and version comparison. Foundation-only (tested in SwiftPM).
enum ReleaseSource {
    /// The one place to change which repo the Releases section reads.
    static let owner = "tenebrsx"
    static let repo = "word-blocker-desktop"
    static var apiURL: URL { URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases")! }
    static var pageURL: URL { URL(string: "https://github.com/\(owner)/\(repo)/releases")! }
}

struct GitHubRelease: Codable, Identifiable, Equatable {
    struct Asset: Codable, Identifiable, Equatable {
        let id: Int
        let name: String
        let size: Int
        let downloadCount: Int
        let browserDownloadURL: URL
        enum CodingKeys: String, CodingKey {
            case id, name, size
            case downloadCount = "download_count"
            case browserDownloadURL = "browser_download_url"
        }
    }
    let id: Int
    let tagName: String
    let name: String?
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let publishedAt: Date?
    let htmlURL: URL
    let assets: [Asset]
    enum CodingKeys: String, CodingKey {
        case id, name, body, draft, prerelease, assets
        case tagName = "tag_name"
        case publishedAt = "published_at"
        case htmlURL = "html_url"
    }

    static func decodeList(_ data: Data) throws -> [GitHubRelease] {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode([GitHubRelease].self, from: data).filter { !$0.draft }
    }
}

/// Loose semver: "v1.2.3", "1.2", "2.0.0-beta.1". Pre-releases sort below the release.
struct SemVer: Comparable, Equatable {
    let parts: [Int]
    let pre: String?

    init?(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.first == "v" || s.first == "V" { s.removeFirst() }
        let split = s.split(separator: "-", maxSplits: 1)
        guard let core = split.first else { return nil }
        let nums = core.split(separator: ".").map { Int($0) }
        guard !nums.isEmpty, !nums.contains(where: { $0 == nil }) else { return nil }
        parts = nums.map { $0! }
        pre = split.count > 1 ? String(split[1]) : nil
    }

    static func < (a: SemVer, b: SemVer) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        switch (a.pre, b.pre) {
        case (nil, nil), (nil, _): return false
        case (_, nil): return true
        case let (p?, q?): return p.compare(q, options: .numeric) == .orderedAscending
        }
    }

    static func == (a: SemVer, b: SemVer) -> Bool { !(a < b) && !(b < a) }

    /// Newest non-prerelease release that is newer than `current`, if any.
    static func update(in releases: [GitHubRelease], current: String) -> GitHubRelease? {
        guard let cur = SemVer(current) else { return nil }
        return releases.filter { !$0.prerelease }
            .compactMap { r in SemVer(r.tagName).map { (r, $0) } }
            .filter { $0.1 > cur }
            .max { $0.1 < $1.1 }?.0
    }
}
