import Cocoa
import Combine

/// Cinema: lock yourself into one app until the timer runs out.
/// While a session runs, Cmd-Tab / Cmd-H / Cmd-M / Cmd-Q / Esc are swallowed, switching away bounces you
/// back, and the target app is kept frontmost. Word Blocker itself is the one exception (so the emergency
/// exit is always reachable), and ending early waits out the 60-second lock.
final class Cinema: ObservableObject {
    static let shared = Cinema()

    @Published private(set) var target: NSRunningApplication?
    @Published private(set) var endsAt: TimeInterval = 0
    @Published private(set) var remaining: Int = 0
    private var timer: Timer?

    var isActive: Bool { target != nil }
    private func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    func start(app: NSRunningApplication, minutes: Int) {
        target = app
        endsAt = now() + TimeInterval(minutes * 60)
        app.activate()
        timer?.invalidate()
        let t = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Toast.show("Cinema on. You're locked in for \(minutes) min.", seconds: 3)
    }

    func end(finished: Bool) {
        timer?.invalidate(); timer = nil
        target = nil; remaining = 0
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
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        if front.processIdentifier != target.processIdentifier && front.processIdentifier != getpid() {
            target.activate()
            Toast.show("Stay with it — \(remaining / 60 + 1) min left.")
        }
    }

    /// Called from the keyboard tap. Returns true to swallow the key.
    func shouldSwallow(code: Int64, flags: CGEventFlags) -> Bool {
        guard isActive, NSWorkspace.shared.frontmostApplication?.processIdentifier != getpid() else { return false }
        let cmd = flags.contains(.maskCommand)
        // Tab, H, M, Q, W (with Cmd), plus Esc and Ctrl+Cmd+F (leave full screen)
        if cmd && [0x30, 0x04, 0x2E, 0x0C, 0x0D].contains(code) { return true }
        if code == 0x35 { return true }
        if cmd && flags.contains(.maskControl) && code == 0x03 { return true }
        return false
    }
}
