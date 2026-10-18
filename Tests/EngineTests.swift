import XCTest

/// Runs the shared iOS-browser test vectors against the same engine the Mac app uses.
final class EngineTests: XCTestCase {
    private func json(_ name: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func entries(_ any: Any?) -> [WordBlockEngine.Entry] {
        ((any as? [[String: Any]]) ?? []).map { .init(word: $0["word"] as! String, substring: ($0["substring"] as? Bool) ?? false) }
    }

    func testWordBlockVectors() throws {
        let defaults = try json("wordblock-defaults")
        let vectors = try json("wordblock-vectors")
        let engine = WordBlockEngine(words: entries(defaults["words"]) + entries(vectors["extraWords"]),
                                     allowlist: ((defaults["allowlist"] as? [String]) ?? []) + ((vectors["extraAllowlist"] as? [String]) ?? []))
        let cases = vectors["cases"] as! [[String: String]]
        var failures: [String] = []
        for c in cases {
            let out = engine.sanitize(c["text"]!, isFinal: c["mode"] == "final")
            if out != c["expect"]! { failures.append("\(c["text"]!.debugDescription) → \(out.debugDescription)") }
        }
        XCTAssert(failures.isEmpty, "\(failures.count)/\(cases.count) failed:\n" + failures.joined(separator: "\n"))
    }

    func testBlockedSitesVectors() throws {
        let defaults = try json("blocked-sites-defaults")
        let vectors = try json("blocked-sites-vectors")
        let matcher = BlockedSitesMatcher(patterns: (defaults["sites"] as! [String]) + (vectors["extraPatterns"] as! [String]))
        for c in vectors["cases"] as! [[String: Any]] {
            XCTAssertEqual(matcher.match(c["url"] as! String), c["expect"] as? String, c["url"] as! String)
        }
    }

    func testMathChallengeNeedsFiveCorrect() {
        var c = MathChallenge(required: 5, rng: SystemRandomNumberGenerator())
        XCTAssertEqual(c.submit("-1"), .wrong)
        for _ in 0..<4 { XCTAssertEqual(c.submit(String(c.current.answer)), .correct) }
        XCTAssertEqual(c.submit(String(c.current.answer)), .complete)
    }

    func testSocialShortsOnly() {
        let m = SocialSiteMatcher(patterns: SocialDefaults.sites)
        XCTAssertEqual(m.match("https://www.youtube.com/shorts/abc"), "youtube.com/shorts")
        XCTAssertNil(m.match("https://www.youtube.com/watch?v=1"))
    }
}
