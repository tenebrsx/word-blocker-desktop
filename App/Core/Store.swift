import Foundation
import Combine

struct BlockedWord: Codable, Hashable, Identifiable {
    var word: String
    var substring: Bool
    var id: String { word.lowercased() }
}

struct AppState: Codable {
    var words: [BlockedWord] = []
    var allowlist: [String] = []
    var sites: [String] = []
    var socialSites: [String] = SocialDefaults.sites
    var socialMessage: String = SocialDefaults.message
    var socialMinutes: Int = 10
    var socialProblems: Int = 5
    var reminder: String = "You're stronger than this moment. Close it and breathe."
    var why: String = ""
    var streakStart: Date = Date()
    var bestStreakDays: Int = 0
    var dailyBlocks: [String: Int] = [:]
    var totalBlocks: Int = 0
    var onboarded: Bool = false
    var soundOn: Bool = false
    var toastOn: Bool = true
    var seenIntros: [String] = []
    var cinemaMinutes: Int = 45
    var cinema: CinemaPolicy = CinemaPolicy()
    var clock: ClockGuard = ClockGuard(lastTrusted: Date())
}

/// Single source of truth. Persisted to ~/Library/Application Support/WordBlockerDesktop/state.json,
/// which is outside the .app, so deleting and reinstalling the app keeps everything.
final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var state: AppState
    @Published private(set) var engine: WordBlockEngine
    @Published private(set) var siteMatcher: BlockedSitesMatcher
    @Published private(set) var socialMatcher: SocialSiteMatcher
    let builtInSites: [String]

    private let url: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WordBlockerDesktop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("state.json")
        builtInSites = Store.loadBuiltInSites()
        var s: AppState
        if let data = try? Data(contentsOf: url), let decoded = Store.decodeTolerant(data) {
            s = decoded
        } else {
            s = AppState()
            let d = Store.loadWordDefaults()
            s.words = d.words
            s.allowlist = d.allowlist
        }
        state = s
        engine = Store.makeEngine(s)
        siteMatcher = BlockedSitesMatcher(patterns: builtInSites + s.sites)
        socialMatcher = SocialSiteMatcher(patterns: s.socialSites)
    }

    /// Fills keys missing from older saves with defaults, so new settings never wipe your data.
    static func decodeTolerant(_ data: Data) -> AppState? {
        if let s = try? JSONDecoder.iso.decode(AppState.self, from: data) { return s }
        guard let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let baseData = try? JSONEncoder.iso.encode(AppState()),
              var base = (try? JSONSerialization.jsonObject(with: baseData)) as? [String: Any] else { return nil }
        base.merge(saved) { _, new in new }
        guard let merged = try? JSONSerialization.data(withJSONObject: base) else { return nil }
        return try? JSONDecoder.iso.decode(AppState.self, from: merged)
    }

    // MARK: Mutation

    func update(_ change: (inout AppState) -> Void) {
        var s = state
        change(&s)
        state = s
        engine = Store.makeEngine(s)
        siteMatcher = BlockedSitesMatcher(patterns: builtInSites + s.sites)
        socialMatcher = SocialSiteMatcher(patterns: s.socialSites)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder.iso.encode(state) { try? data.write(to: url, options: .atomic) }
    }

    // MARK: Streak (tamper resistant via ClockGuard)

    func trustedNow() -> Date {
        var s = state
        let now = s.clock.trustedNow(system: Date())
        if s.clock != state.clock { state = s; save() }
        return now
    }

    var daysStrong: Int {
        Streak.daysStrong(start: state.streakStart, now: trustedNow())
    }

    var bestStreak: Int { max(state.bestStreakDays, daysStrong) }

    func startNewCount() {
        let days = daysStrong
        update { s in
            s.bestStreakDays = Streak.bestAfterReset(best: s.bestStreakDays, current: days)
            s.streakStart = s.clock.trustedNow(system: Date())
        }
    }

    /// Reads an HTTPS Date header so a forward-moved clock can't inflate the streak.
    func verifyClock() {
        var req = URLRequest(url: URL(string: "https://www.apple.com")!)
        req.httpMethod = "HEAD"
        URLSession.shared.dataTask(with: req) { [weak self] _, resp, _ in
            guard let http = resp as? HTTPURLResponse,
                  let header = http.value(forHTTPHeaderField: "Date"),
                  let server = ClockGuard.parseHTTPDate(header) else { return }
            DispatchQueue.main.async { self?.update { $0.clock.applyServerTime(server, system: Date()) } }
        }.resume()
    }

    // MARK: Stats

    static func dayKey(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }

    func recordBlock() {
        let key = Store.dayKey(Date())
        update { s in
            s.dailyBlocks[key, default: 0] += 1
            s.totalBlocks += 1
        }
    }

    var blocksToday: Int { state.dailyBlocks[Store.dayKey(Date())] ?? 0 }

    func lastDays(_ n: Int) -> [(date: Date, count: Int)] {
        let cal = Calendar.current
        return (0..<n).reversed().compactMap { i in
            guard let d = cal.date(byAdding: .day, value: -i, to: cal.startOfDay(for: Date())) else { return nil }
            return (d, state.dailyBlocks[Store.dayKey(d)] ?? 0)
        }
    }

    // MARK: Defaults

    private static func makeEngine(_ s: AppState) -> WordBlockEngine {
        WordBlockEngine(words: s.words.map { .init(word: $0.word, substring: $0.substring) }, allowlist: s.allowlist)
    }

    static func loadWordDefaults() -> (words: [BlockedWord], allowlist: [String]) {
        struct F: Decodable { struct W: Decodable { let word: String; let substring: Bool? }; let words: [W]; let allowlist: [String] }
        guard let u = Bundle.main.url(forResource: "wordblock-defaults", withExtension: "json"),
              let d = try? Data(contentsOf: u), let f = try? JSONDecoder().decode(F.self, from: d) else { return ([], []) }
        return (f.words.map { BlockedWord(word: $0.word, substring: $0.substring ?? false) }, f.allowlist)
    }

    static func loadBuiltInSites() -> [String] {
        struct F: Decodable { let sites: [String] }
        guard let u = Bundle.main.url(forResource: "blocked-sites-defaults", withExtension: "json"),
              let d = try? Data(contentsOf: u), let f = try? JSONDecoder().decode(F.self, from: d) else { return [] }
        return f.sites
    }
}

extension JSONDecoder { static let iso: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }() }
extension JSONEncoder { static let iso: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = .prettyPrinted; return e }() }
