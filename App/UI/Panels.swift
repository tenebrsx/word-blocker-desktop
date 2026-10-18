import SwiftUI
import AppKit

/// Small floating HUD at the top of the screen.
enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ message: String, seconds: Double = 2.2) {
        DispatchQueue.main.async {
            let host = NSHostingView(rootView:
                HStack(spacing: 10) {
                    Image(systemName: "shield.lefthalf.filled").foregroundStyle(Theme.accent)
                    Text(message).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text).lineLimit(2)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(Capsule().fill(Theme.panel.opacity(0.96)))
                .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.25)))
                .fixedSize()
            )
            let size = host.fittingSize
            let p = panel ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.level = .statusBar; p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.contentView = host
            if let screen = NSScreen.main {
                let f = screen.visibleFrame
                p.setFrame(NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height - 14, width: size.width, height: size.height), display: true)
            }
            p.alphaValue = 0
            p.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.18; p.animator().alphaValue = 1 }
            panel = p
            hideWork?.cancel()
            let work = DispatchWorkItem { NSAnimationContext.runAnimationGroup({ $0.duration = 0.35; p.animator().alphaValue = 0 }) { p.orderOut(nil) } }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
    }
}

/// Floating window for the social pause: your message, Go Back, or 5 math problems to continue.
enum SocialGateWindow {
    private static var window: NSWindow?

    static func present(site: String, done: @escaping (Bool) -> Void) {
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 420), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.appearance = NSAppearance(named: .darkAqua)
        let finish: (Bool) -> Void = { ok in
            w.orderOut(nil); window = nil; done(ok)
        }
        w.contentView = NSHostingView(rootView: SocialGateView(site: site, finish: finish))
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

struct SocialGateView: View {
    let site: String
    let finish: (Bool) -> Void
    @ObservedObject private var store = Store.shared
    @State private var challenge: MathChallenge<SystemRandomNumberGenerator>?
    @State private var answer = ""
    @State private var shake = false

    var body: some View {
        ZStack {
            GrainBackground()
            VStack(spacing: 18) {
                Label2(text: "Pause · \(site)")
                if let c = challenge {
                    Text("Problem \(c.solved + 1) of \(c.required)").font(Theme.mono(12)).foregroundStyle(Theme.dim)
                    Text(c.current.text + " = ?").font(Theme.mono(40, .bold)).foregroundStyle(Theme.text)
                        .offset(x: shake ? 6 : 0)
                    DarkField(placeholder: "Answer", text: $answer, onSubmit: submit).frame(width: 160)
                    ProgressView(value: Double(c.solved), total: Double(c.required)).tint(Theme.accent).frame(width: 220)
                    HStack {
                        Button("Go Back", action: { finish(false) }).buttonStyle(AccentButton())
                        Button("Check", action: submit).buttonStyle(AccentButton(prominent: false))
                    }
                } else {
                    Image(systemName: "hand.raised.fill").font(.system(size: 34)).foregroundStyle(Theme.accent)
                    Text(store.state.socialMessage).font(.system(size: 17, weight: .medium)).multilineTextAlignment(.center)
                        .foregroundStyle(Theme.text).padding(.horizontal, 30)
                    Button { finish(false) } label: { Text("Go Back").frame(width: 220) }.buttonStyle(AccentButton())
                    Button("Continue (\(store.state.socialProblems) quick problems)") {
                        challenge = MathChallenge(required: store.state.socialProblems, rng: SystemRandomNumberGenerator())
                    }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.dim)
                    Text("Opens for \(store.state.socialMinutes) minutes").font(Theme.mono(10)).foregroundStyle(Theme.dim.opacity(0.7))
                }
            }
            .padding(30)
        }
        .frame(width: 460, height: 420)
    }

    private func submit() {
        guard var c = challenge else { return }
        let outcome = c.submit(answer)
        answer = ""
        challenge = c
        switch outcome {
        case .complete: finish(true)
        case .wrong:
            withAnimation(.default.repeatCount(3, autoreverses: true).speed(4)) { shake.toggle() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { shake = false }
        case .correct: break
        }
    }
}

/// Floating math gate (Cinema Math Mode). Big primary button = stay; solving all problems = out.
enum MathGateWindow {
    private static var window: NSWindow?

    static func present(title: String, subtitle: String, problems: Int, primary: String, done: @escaping (Bool) -> Void) {
        close()
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 440), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.appearance = NSAppearance(named: .darkAqua)
        let finish: (Bool) -> Void = { ok in close(); done(ok) }
        w.contentView = NSHostingView(rootView: MathGateView(title: title, subtitle: subtitle, problems: problems, primary: primary, finish: finish))
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    static func close() { window?.orderOut(nil); window = nil }
}

struct MathGateView: View {
    let title: String
    let subtitle: String
    let problems: Int
    let primary: String
    let finish: (Bool) -> Void
    @State private var challenge: MathChallenge<SystemRandomNumberGenerator>
    @State private var answer = ""
    @State private var wrong = false
    @FocusState private var focused: Bool

    init(title: String, subtitle: String, problems: Int, primary: String, finish: @escaping (Bool) -> Void) {
        self.title = title; self.subtitle = subtitle; self.problems = problems; self.primary = primary; self.finish = finish
        _challenge = State(initialValue: MathChallenge(required: problems, rng: SystemRandomNumberGenerator()))
    }

    var body: some View {
        ZStack {
            GrainBackground()
            VStack(spacing: 16) {
                Label2(text: "Cinema · Math Mode")
                Text(title).font(.system(size: 28, weight: .heavy)).foregroundStyle(Theme.text)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.dim)
                Text(challenge.current.text + " = ?").font(Theme.mono(40, .bold)).foregroundStyle(wrong ? Theme.warn : Theme.text)
                TextField("Answer", text: $answer)
                    .textFieldStyle(.plain).font(Theme.mono(20)).multilineTextAlignment(.center)
                    .padding(10).frame(width: 160)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.4)))
                    .focused($focused)
                    .onChange(of: answer) { _, v in answer = String(v.filter { $0.isNumber }.prefix(4)) }
                    .onSubmit(submit)
                Text("\(challenge.solved) of \(challenge.required) solved").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                ProgressView(value: Double(challenge.solved), total: Double(challenge.required)).tint(Theme.accent).frame(width: 240)
                Button { finish(false) } label: { Text(primary).frame(width: 260) }.buttonStyle(AccentButton()).keyboardShortcut(.cancelAction)
            }
            .padding(30)
        }
        .frame(width: 480, height: 440)
        .onAppear { focused = true }
    }

    private func submit() {
        let outcome = challenge.submit(answer)
        answer = ""
        wrong = outcome == .wrong
        if outcome == .complete { finish(true) }
    }
}
