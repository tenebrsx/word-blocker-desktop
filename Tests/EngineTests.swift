import XCTest
#if canImport(Engine)
@testable import Engine
#endif

/// Runs the shared iOS-browser test vectors against the same engine the Mac app uses.
final class EngineTests: XCTestCase {
    private func json(_ name: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let candidates = [Bundle(for: Self.self).url(forResource: name, withExtension: "json"),
                          root.appendingPathComponent("Tests/Vectors/\(name).json"),
                          root.appendingPathComponent("App/Resources/\(name).json")].compactMap { $0 }
        let url = try XCTUnwrap(candidates.first { FileManager.default.fileExists(atPath: $0.path) })
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

    // MARK: Cooldown

    func testCooldownCountsDownAndRestarts() {
        var t = CooldownTimer(now: 100)
        XCTAssertEqual(t.remaining(now: 100), 60)
        XCTAssertEqual(t.remaining(now: 130), 30)
        t.restart(now: 130)                       // left the app
        XCTAssertEqual(t.remaining(now: 159), 31)
        XCTAssertFalse(t.isReady(now: 189))
        XCTAssertTrue(t.isReady(now: 190))
    }

    // MARK: Streak

    func testStreakDaysAndBest() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(Streak.daysStrong(start: start, now: start.addingTimeInterval(86_400 * 3 + 5), calendar: cal), 3)
        XCTAssertEqual(Streak.daysStrong(start: start, now: start.addingTimeInterval(-86_400), calendar: cal), 0)
        XCTAssertEqual(Streak.bestAfterReset(best: 10, current: 4), 10)
        XCTAssertEqual(Streak.bestAfterReset(best: 2, current: 4), 4)
    }

    func testClockRollbackDoesNotDropStreak() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var g = ClockGuard(lastTrusted: t0)
        XCTAssertEqual(g.trustedNow(system: t0.addingTimeInterval(-86_400 * 5)), t0)
        XCTAssertTrue(g.rollbackDetected)
    }

    // MARK: Cinema Math Mode

    func testMathModeShowsGateThenRelocksOnReturn() {
        var s = CinemaSession(policy: CinemaPolicy())
        XCTAssertEqual(s.frontChanged(isTarget: false, isSelf: false), .showGate)
        XCTAssertEqual(s.exitAttempt(), .none)             // gate already open
        XCTAssertEqual(s.gateSolved(), .passGranted)
        XCTAssertEqual(s.frontChanged(isTarget: false, isSelf: false), .none)  // free to roam
        XCTAssertEqual(s.frontChanged(isTarget: true, isSelf: false), .none)   // back: re-lock
        XCTAssertEqual(s.exitAttempt(), .showGate)
    }

    func testStayFocusedKeepsLock() {
        var s = CinemaSession(policy: CinemaPolicy())
        XCTAssertEqual(s.exitAttempt(), .showGate)
        s.gateDismissed()
        XCTAssertEqual(s.exitAttempt(), .showGate)
    }

    func testEndSessionBehaviour() {
        var p = CinemaPolicy(); p.exitBehavior = .endSession
        var s = CinemaSession(policy: p)
        _ = s.exitAttempt()
        XCTAssertEqual(s.gateSolved(), .endSession)
    }

    func testMathModeOffJustBounces() {
        var p = CinemaPolicy(); p.mathMode = false
        var s = CinemaSession(policy: p)
        XCTAssertEqual(s.exitAttempt(), .bounce)
        XCTAssertEqual(s.frontChanged(isTarget: false, isSelf: true), .none)  // Word Blocker reachable
    }

    func testLooseningNeedsCooldown() {
        let base = CinemaPolicy()
        var off = base; off.mathMode = false
        var fewer = base; fewer.problems = 3
        var more = base; more.problems = 8
        var end = base; end.exitBehavior = .endSession
        XCTAssertTrue(off.isLooser(than: base))
        XCTAssertTrue(fewer.isLooser(than: base))
        XCTAssertTrue(end.isLooser(than: base))
        XCTAssertFalse(more.isLooser(than: base))
        XCTAssertFalse(base.isLooser(than: off))   // turning on is instant
    }

    func testMathProblemsAreSimpleAndPositive() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<2000 {
            let p = MathProblem.random(using: &rng)
            XCTAssertGreaterThan(p.answer, 0)
            XCTAssertLessThan(p.answer, 200)
            XCTAssertTrue(p.isCorrect(" \(p.answer) "))
        }
    }

    // MARK: Typing buffer (what the keyboard hook feeds)

    func testTypingBufferErasesAsYouType() {
        let engine = WordBlockEngine(words: [.init(word: "porn", substring: true)], allowlist: [])
        let b = TypingBuffer()
        var erased: Int?
        for ch in "hello p0rn" { if let n = b.type(String(ch), engine: engine) { erased = n } }
        XCTAssertEqual(erased, 4)
        XCTAssertEqual(b.text, "hello ")
    }

    func testTypingBufferWholeWordWaitsForEnter() {
        let engine = WordBlockEngine(words: [.init(word: "xxx", substring: false)], allowlist: [])
        let b = TypingBuffer()
        for ch in "find xxx" { XCTAssertNil(b.type(String(ch), engine: engine)) }
        XCTAssertEqual(b.check(engine: engine, isFinal: true), 3)
    }

    func testTypingBufferBackspace() {
        let engine = WordBlockEngine(words: [.init(word: "porn", substring: true)], allowlist: [])
        let b = TypingBuffer()
        for ch in "por" { _ = b.type(String(ch), engine: engine) }
        b.backspace(); b.backspace()
        XCTAssertNil(b.type("x", engine: engine))
        XCTAssertEqual(b.text, "px")
    }
}
