import Foundation
import AppKit
import Combine

/// 60-second self-control lock for anything that removes or loosens protection.
/// Measured with the monotonic clock (system uptime), so changing the date/time does nothing,
/// and the countdown starts over whenever you leave the app.
final class Cooldown: ObservableObject {
    static let shared = Cooldown()
    static let seconds: TimeInterval = 60

    struct Request: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let action: () -> Void
    }

    @Published var pending: Request?
    @Published private(set) var remaining: Int = Int(Cooldown.seconds)
    private var startedAt: TimeInterval = 0
    private var timer: Timer?

    private init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.restart()
        }
    }

    func request(_ title: String, detail: String = "", action: @escaping () -> Void) {
        pending = Request(title: title, detail: detail, action: action)
        restart()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func restart() {
        startedAt = ProcessInfo.processInfo.systemUptime
        remaining = Int(Cooldown.seconds)
    }

    private func tick() {
        let left = Cooldown.seconds - (ProcessInfo.processInfo.systemUptime - startedAt)
        remaining = max(0, Int(left.rounded(.up)))
    }

    var isReady: Bool { remaining == 0 }

    func confirm() {
        guard isReady, let p = pending else { return }
        p.action()
        cancel()
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        pending = nil
    }
}
