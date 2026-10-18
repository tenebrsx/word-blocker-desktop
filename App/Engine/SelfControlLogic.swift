import Foundation

/// Pure, platform-free logic behind the Mac app (cooldown, streak, Cinema Math Mode),
/// kept here so it runs in the SwiftPM test suite on any machine.

/// 60-second lock measured on a monotonic clock. Leaving the app calls `restart`.
struct CooldownTimer: Equatable {
    var duration: TimeInterval = 60
    private(set) var startedAt: TimeInterval

    init(now: TimeInterval, duration: TimeInterval = 60) { startedAt = now; self.duration = duration }
    mutating func restart(now: TimeInterval) { startedAt = now }
    func remaining(now: TimeInterval) -> Int { max(0, Int((duration - (now - startedAt)).rounded(.up))) }
    func isReady(now: TimeInterval) -> Bool { remaining(now: now) == 0 }
}

enum Streak {
    static func daysStrong(start: Date, now: Date, calendar: Calendar = .current) -> Int {
        max(0, calendar.dateComponents([.day], from: start, to: now).day ?? 0)
    }
    /// Best streak after starting a new count: never goes down.
    static func bestAfterReset(best: Int, current: Int) -> Int { max(best, current) }
}

/// Cinema settings + decisions.
struct CinemaPolicy: Codable, Equatable {
    enum ExitBehavior: String, Codable, CaseIterable {
        /// Solving the gate lets you out; Cinema locks again as soon as you come back to the app.
        case relockOnReturn
        /// Solving the gate ends the session.
        case endSession
    }

    var mathMode = true
    var problems = 5
    var exitBehavior: ExitBehavior = .relockOnReturn

    /// A change that needs the 60-second wait.
    func isLooser(than old: CinemaPolicy) -> Bool {
        (old.mathMode && !mathMode) || problems < old.problems ||
            (old.exitBehavior == .relockOnReturn && exitBehavior == .endSession)
    }

    static func clampProblems(_ p: Int) -> Int { min(max(p, 1), 30) }
}

/// Runtime state of one session.
struct CinemaSession: Equatable {
    enum Decision: Equatable { case none, bounce, showGate }
    enum GateResult: Equatable { case passGranted, endSession }

    let policy: CinemaPolicy
    private(set) var passActive = false
    private(set) var gateOpen = false

    init(policy: CinemaPolicy) { self.policy = policy }

    /// An exit attempt (switching app, blocked shortcut, leaving full screen).
    mutating func exitAttempt() -> Decision {
        if passActive { return .none }
        if !policy.mathMode { return .bounce }
        if gateOpen { return .none }
        gateOpen = true
        return .showGate
    }

    /// Front app changed. `isTarget`/`isSelf` describe the new frontmost app.
    mutating func frontChanged(isTarget: Bool, isSelf: Bool) -> Decision {
        if isTarget { passActive = false; return .none }   // back in the app: re-lock
        if isSelf { return .none }                          // Word Blocker stays reachable
        return exitAttempt()
    }

    mutating func gateSolved() -> GateResult {
        gateOpen = false
        if policy.exitBehavior == .endSession { return .endSession }
        passActive = true
        return .passGranted
    }

    /// "Stay Focused".
    mutating func gateDismissed() { gateOpen = false }
}
