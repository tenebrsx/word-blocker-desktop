import Cocoa
import Combine

/// Cinema: lock yourself into one app until the timer runs out.
///
/// Exit attempts (Cmd-Tab/H/M/Q/W, Esc, Ctrl-Cmd-F, clicking or switching to another app):
/// - Math Mode ON (default): you're pulled back and a gate asks for N quick problems.
///   Solve them and, depending on the setting, you're free until you come back to the app
///   (then it re-locks) or the session ends. "Stay Focused" returns you to the app.
/// - Math Mode OFF: the key is swallowed / you're bounced back.
/// Word Blocker itself is always reachable, so the emergency exit (60-second wait) is too.
final class Cinema: ObservableObject {
    static let shared = Cinema()

    @Published private(set) var target: NSRunningApplication?
    @Published private(set) var remaining: Int = 0
    @Published private(set) var session: CinemaSession?
    private var endsAt: TimeInterval = 0
    private var timer: Timer?
    private var lastFront: pid_t = 0

    var isActive: Bool { target != nil }
    private func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    func start(app: NSRunningApplication, minutes: Int) {
        target = app
        session = CinemaSession(policy: Store.shared.state.cinema)
        endsAt = now() + TimeInterval(minutes * 60)
        lastFront = app.processIdentifier
        app.activate()
        timer?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Toast.show("Cinema on. Locked in for \(minutes) min.", seconds: 3)
    }

    func end(finished: Bool) {
        timer?.invalidate(); timer = nil
        target = nil; session = nil; remaining = 0
        MathGateWindow.close()
        Toast.show(finished ? "Session done. You finished what you started." : "Cinema ended.", seconds: 3)
    }

    func requestEarlyExit() {
        Cooldown.shared.request("End Cinema early?", detail: "You set this timer for a reason.") { [weak self] in self?.end(finished: false) }
    }

    private func tick() {
        guard let target else { return }
        remaining = max(0, Int((endsAt - now()).rounded(.up)))
        if remaining == 0 { end(finished: true); return }
        if target.isTerminated { end(finished: false); return }
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != lastFront else { return }
        lastFront = front.processIdentifier
        let d = session?.frontChanged(isTarget: front.processIdentifier == target.processIdentifier,
                                      isSelf: front.processIdentifier == getpid()) ?? .none
        apply(d)
    }

    private func apply(_ d: CinemaSession.Decision) {
        guard let target else { return }
        switch d {
        case .none: break
        case .bounce:
            target.activate()
            Toast.show("Stay with it. \(remaining / 60 + 1) min left.")
        case .showGate:
            target.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.presentGate() }
        }
    }

    private func presentGate() {
        guard let s = session else { return }
        MathGateWindow.present(title: "Want out? Earn it.", subtitle: "\(s.policy.problems) quick problems, or stay focused.",
                               problems: s.policy.problems, primary: "Stay Focused") { [weak self] solved in
            guard let self, self.session != nil else { return }
            if solved {
                switch self.session!.gateSolved() {
                case .endSession: self.end(finished: false)
                case .passGranted: Toast.show("You're free to go. Cinema locks again when you come back.", seconds: 3)
                }
            } else {
                self.session!.gateDismissed()
                self.target?.activate()
            }
        }
    }

    /// Called from the keyboard tap. Returns true to swallow the key.
    func shouldSwallow(code: Int64, flags: CGEventFlags) -> Bool {
        guard isActive, let target, NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else { return false }
        let cmd = flags.contains(.maskCommand)
        let isExitKey = (cmd && [0x30, 0x04, 0x2E, 0x0C, 0x0D].contains(code)) || code == 0x35
            || (cmd && flags.contains(.maskControl) && code == 0x03)
        guard isExitKey, var s = session else { return false }
        let d = s.exitAttempt()
        session = s
        if d == .none { return s.passActive ? false : true }
        DispatchQueue.main.async { self.apply(d) }
        return true
    }
}
