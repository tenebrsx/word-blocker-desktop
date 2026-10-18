import Foundation

/// The Social Media gate's "Continue" challenge: quick arithmetic.
/// Foundation-only (builds on Linux for tests).
///
/// Rules: single- and double-digit numbers; + − ×; answers are never
/// negative (and never zero, so there's no "free" answer). A wrong answer
/// replaces the problem with a new one without advancing; progress already
/// made is kept. That's the gentler option, and it still means every correct
/// answer has to be worked out.
enum MathOperation: String, CaseIterable, Equatable {
    case add = "+"
    case subtract = "−"
    case multiply = "×"

    var spoken: String {
        switch self {
        case .add: return "plus"
        case .subtract: return "minus"
        case .multiply: return "times"
        }
    }
}

struct MathProblem: Equatable {
    let a: Int
    let b: Int
    let operation: MathOperation

    var answer: Int {
        switch operation {
        case .add: return a + b
        case .subtract: return a - b
        case .multiply: return a * b
        }
    }

    var text: String { "\(a) \(operation.rawValue) \(b)" }
    var spokenText: String { "\(a) \(operation.spoken) \(b)" }

    func isCorrect(_ input: String) -> Bool {
        Int(input.trimmingCharacters(in: .whitespaces)) == answer
    }

    /// Makes a random problem. Never repeats `avoiding`.
    static func random<R: RandomNumberGenerator>(using rng: inout R, avoiding previous: MathProblem? = nil) -> MathProblem {
        while true {
            let op = MathOperation.allCases.randomElement(using: &rng)!
            let problem: MathProblem
            switch op {
            case .add:
                // A double-digit number plus a single- or small double-digit one.
                problem = MathProblem(a: Int.random(in: 10...79, using: &rng), b: Int.random(in: 2...19, using: &rng), operation: .add)
            case .subtract:
                let a = Int.random(in: 12...99, using: &rng)
                let b = Int.random(in: 2...min(49, a - 1), using: &rng)
                problem = MathProblem(a: a, b: b, operation: .subtract)
            case .multiply:
                problem = MathProblem(a: Int.random(in: 2...12, using: &rng), b: Int.random(in: 2...9, using: &rng), operation: .multiply)
            }
            if problem != previous { return problem }
        }
    }
}

/// Progress through one challenge. Wrong answers swap the problem, never advance.
struct MathChallenge<R: RandomNumberGenerator> {
    let required: Int
    private(set) var solved = 0
    private(set) var wrong = 0
    private(set) var current: MathProblem
    private var rng: R

    init(required: Int, rng: R) {
        self.required = max(1, required)
        var r = rng
        current = MathProblem.random(using: &r)
        self.rng = r
    }

    var isComplete: Bool { solved >= required }

    enum Outcome: Equatable { case correct, wrong, complete }

    /// Checks an answer and moves on: next problem when right, a fresh
    /// problem (same step) when wrong.
    @discardableResult
    mutating func submit(_ input: String) -> Outcome {
        guard !isComplete else { return .complete }
        if current.isCorrect(input) {
            solved += 1
            if isComplete { return .complete }
            current = MathProblem.random(using: &rng, avoiding: current)
            return .correct
        }
        wrong += 1
        current = MathProblem.random(using: &rng, avoiding: current)
        return .wrong
    }
}

/// Session length and problem count. Stricter changes are instant; looser
/// ones go through the Self-Control Lock cooldown in the UI.
enum SocialSessionPolicy {
    static let minuteOptions = [5, 10, 15, 20, 30]
    static let defaultMinutes = 10
    static let problemOptions = [5, 7, 10, 15]
    static let defaultProblems = 5

    /// Longer sessions are looser.
    static func isLooser(minutes new: Int, than old: Int) -> Bool { new > old }
    /// Fewer problems are looser.
    static func isLooser(problems new: Int, than old: Int) -> Bool { new < old }

    static func clampMinutes(_ m: Int) -> Int { min(max(m, 1), 60) }
    static func clampProblems(_ p: Int) -> Int { min(max(p, 1), 30) }
}

/// Which social sites are open for a limited session, per tab. Times are
/// monotonic seconds (see MonotonicClock), so changing the device clock
/// can't stretch a session. Closing the tab ends its sessions.
struct SocialAllowances {
    private struct Key: Hashable {
        let tab: UUID
        let pattern: String
    }
    private var expiries: [Key: TimeInterval] = [:]

    mutating func allow(tab: UUID, pattern: String, now: TimeInterval, duration: TimeInterval) {
        expiries[Key(tab: tab, pattern: pattern)] = now + duration
    }

    func isAllowed(tab: UUID, pattern: String, now: TimeInterval) -> Bool {
        guard let end = expiries[Key(tab: tab, pattern: pattern)] else { return false }
        return now < end
    }

    func expiry(tab: UUID, pattern: String) -> TimeInterval? {
        expiries[Key(tab: tab, pattern: pattern)]
    }

    mutating func endSessions(tab: UUID) {
        expiries = expiries.filter { $0.key.tab != tab }
    }

    mutating func endSessions(pattern: String) {
        expiries = expiries.filter { $0.key.pattern != pattern }
    }

    mutating func prune(now: TimeInterval) {
        expiries = expiries.filter { $0.value > now }
    }
}

/// Monotonic seconds that keep counting while the phone sleeps and can't be
/// changed by the user (ContinuousClock), unlike Date().
enum MonotonicClock {
    private static let origin = ContinuousClock.now

    static func now() -> TimeInterval {
        let d = ContinuousClock.now - origin
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }
}
