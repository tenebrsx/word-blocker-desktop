import SwiftUI

/// Cinematic first run. Full window, one bold line per screen, honest about how strict each feature is.
struct OnboardingView: View {
    @ObservedObject var store = Store.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var why = ""
    @State private var word = ""
    @State private var granted = Permissions.accessibility
    @State private var appear = false
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    enum Screen: CaseIterable { case hook, why, words, sites, social, cinema, streak, permission, firstWord, done }
    private var screens: [Screen] { Screen.allCases }
    private var screen: Screen { screens[step] }

    var body: some View {
        ZStack {
            GrainBackground()
            RadialGradient(colors: [Theme.accent.opacity(appear ? 0.12 : 0.02), .clear], center: .center, startRadius: 0, endRadius: 520)
                .ignoresSafeArea()
                .animation(reduceMotion ? nil : .easeInOut(duration: 3).repeatForever(autoreverses: true), value: appear)
            VStack(spacing: 0) {
                progress.padding(.top, 34)
                Spacer()
                content
                    .id(step)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                                    removal: .move(edge: .leading).combined(with: .opacity)))
                    .frame(maxWidth: 640)
                Spacer()
                controls.padding(.bottom, 40)
            }
            .padding(.horizontal, 60)
        }
        .onAppear { appear = true }
        .onReceive(timer) { _ in
            granted = Permissions.accessibility
            if granted { KeyboardGuard.shared.start() }
        }
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<screens.count, id: \.self) { i in
                Capsule().fill(i <= step ? Theme.accent : Theme.stroke).frame(width: i == step ? 26 : 8, height: 4)
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.4), value: step)
    }

    @ViewBuilder private var content: some View {
        switch screen {
        case .hook:
            FeatureScreen(kicker: "WORD BLOCKER", title: "Your brain deserves\nbetter than this.",
                          body: "Porn and endless scrolling are built to win. This app is built to make them lose — quietly, on every app on your Mac.") {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 64)).foregroundStyle(Theme.accent)
                    .shadow(color: Theme.accent.opacity(0.6), radius: 30)
            }
        case .why:
            FeatureScreen(kicker: "FIRST THINGS FIRST", title: "Why are you here?",
                          body: "One line, for the version of you who's having a hard moment. You'll see it every day.") {
                DarkField(placeholder: "I want to be present for…", text: $why).frame(width: 420)
            }
        case .words:
            FeatureScreen(kicker: "WORD BLOCK", title: "You can't search\nwhat you can't type.",
                          body: "Blocked words vanish the moment you type them — in your browser, in chats, anywhere. p0rn, p.o.r.n and look-alike letters too.",
                          strictness: "Strict: always on. Removing a word takes a 60-second wait.") { TypingDemo() }
        case .sites:
            FeatureScreen(kicker: "BLOCKED SITES", title: "Some doors\nstay shut.",
                          body: "Open a blocked site in Safari, Chrome, Arc or Firefox and the tab closes, with your own reminder in its place.",
                          strictness: "Strictest: no way through. Thousands of adult sites are blocked out of the box.") {
                Text("pornhub.com").font(Theme.mono(22)).strikethrough().foregroundStyle(Theme.dim)
                    .padding(14).background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke))
            }
        case .social:
            FeatureScreen(kicker: "SOCIAL PAUSE", title: "Social media\nhas you fried.",
                          body: "Instagram, TikTok, X and friends get a pause first. Go back — or solve five quick problems to get in for 10 minutes.",
                          strictness: "Gentle: you can always get through. It just makes you choose it.") {
                Text("37 + 14 = ?").font(Theme.mono(40, .bold)).foregroundStyle(Theme.text)
            }
        case .cinema:
            FeatureScreen(kicker: "CINEMA", title: "Finish what\nyou started.",
                          body: "Pick an app and a timer. Cinema locks you in: no Cmd-Tab, no wandering off. Want out? Earn it. 5 quick problems.",
                          strictness: "Strict, not a trap: Math Mode or the 60-second emergency exit.") {
                VStack(spacing: 8) {
                    Image(systemName: "film.stack").font(.system(size: 44)).foregroundStyle(Theme.accent)
                    Text("8 × 7 = ?").font(Theme.mono(26, .bold)).foregroundStyle(Theme.text)
                }
            }
        case .streak:
            FeatureScreen(kicker: "DAYS STRONG", title: "Every day\ncounts.",
                          body: "Your streak grows on its own. Slip up? Start a new count — your best streak is kept. Changing the clock won't fake it.") {
                Text("000").font(Theme.mono(80, .bold)).foregroundStyle(Theme.accent).shadow(color: Theme.accent.opacity(0.4), radius: 20)
            }
        case .permission:
            FeatureScreen(kicker: "ONE PERMISSION", title: "Let it see\nwhat you type.",
                          body: "Accessibility lets Word Blocker erase words and read your browser's address bar. Nothing is saved or sent anywhere. It stays on this Mac.") {
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1  Click Open Settings")
                        Text("2  Turn on Word Blocker under Accessibility")
                        Text("3  Come back. It connects on its own.")
                    }.font(Theme.mono(12)).foregroundStyle(Theme.text)
                    HStack {
                        Button("Open Settings") { Permissions.prompt(); Permissions.openSettings() }.buttonStyle(AccentButton(prominent: !granted))
                        Label(granted ? "Connected" : "Waiting…", systemImage: granted ? "checkmark.circle.fill" : "circle.dotted")
                            .foregroundStyle(granted ? Theme.accent : Theme.dim)
                    }
                }
            }
        case .firstWord:
            FeatureScreen(kicker: "MAKE IT YOURS", title: "What pulls you in?",
                          body: "The usual words are already blocked. Add anything personal — a name, a search, a site.") {
                DarkField(placeholder: "A word or phrase (optional)", text: $word).frame(width: 420)
            }
        case .done:
            FeatureScreen(kicker: "YOU'RE IN", title: "Day 1.",
                          body: why.isEmpty ? "Protection is on. We've got your back." : "“\(why)”") {
                Text("1").font(Theme.mono(110, .bold)).foregroundStyle(Theme.accent).shadow(color: Theme.accent.opacity(0.5), radius: 30)
            }
        }
    }

    private var controls: some View {
        HStack {
            if step > 0 { Button("Back") { go(-1) }.buttonStyle(AccentButton(prominent: false)) }
            Spacer()
            Button(screen == .done ? "Start protecting" : screen == .hook ? "Let's go" : "Continue") { go(1) }
                .buttonStyle(AccentButton()).keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: 640)
    }

    private func go(_ d: Int) {
        if d > 0 && screen == .done { finish(); return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.55, bounce: 0.15)) { step = max(0, step + d) }
    }

    private func finish() {
        let w = word.trimmingCharacters(in: .whitespaces)
        store.update { s in
            s.why = why
            if !w.isEmpty { s.words.insert(BlockedWord(word: w, substring: true), at: 0) }
            s.onboarded = true
            s.seenIntros = NavSection.allCases.map(\.rawValue)
            s.streakStart = Date()
        }
    }
}

struct FeatureScreen<Visual: View>: View {
    let kicker: String
    let title: String
    let body_: String
    var strictness: String? = nil
    @ViewBuilder var visual: Visual
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    init(kicker: String, title: String, body: String, strictness: String? = nil, @ViewBuilder visual: () -> Visual) {
        self.kicker = kicker; self.title = title; self.body_ = body; self.strictness = strictness; self.visual = visual()
    }

    var body: some View {
        VStack(spacing: 22) {
            visual.frame(minHeight: 110)
                .scaleEffect(shown || reduceMotion ? 1 : 0.85).opacity(shown ? 1 : 0)
            Text(kicker).font(Theme.mono(11, .bold)).tracking(3).foregroundStyle(Theme.accent)
            Text(title).font(.system(size: 46, weight: .heavy)).multilineTextAlignment(.center).foregroundStyle(Theme.text)
                .offset(y: shown || reduceMotion ? 0 : 14).opacity(shown ? 1 : 0)
            Text(body_).font(.system(size: 16)).multilineTextAlignment(.center).foregroundStyle(Theme.dim).frame(maxWidth: 520)
                .opacity(shown ? 1 : 0)
            if let strictness {
                Label(strictness, systemImage: "lock.fill").font(Theme.mono(11)).foregroundStyle(Theme.text.opacity(0.8))
                    .padding(.horizontal, 12).padding(.vertical, 7).background(Capsule().fill(Theme.panelHi)).overlay(Capsule().strokeBorder(Theme.stroke))
                    .opacity(shown ? 1 : 0)
            }
        }
        .onAppear { withAnimation(reduceMotion ? .linear(duration: 0.15) : .easeOut(duration: 0.6).delay(0.1)) { shown = true } }
    }
}

/// Types a blocked word letter by letter, then erases it.
struct TypingDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var text = ""
    @State private var flash = false
    private let prefix = "best free p"
    private let full = "best free p0rn"

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim).padding(.trailing, 10)
            Text(text).font(Theme.mono(20)).foregroundStyle(Theme.text)
            Rectangle().fill(Theme.accent).frame(width: 2, height: 22)
            Spacer()
        }
        .padding(16).frame(width: 420)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(flash ? Theme.accent : Theme.stroke, lineWidth: flash ? 1.5 : 1))
        .task { await loop() }
    }

    private func loop() async {
        if reduceMotion { text = "best free "; return }
        while !Task.isCancelled {
            text = ""
            for ch in full { text.append(ch); try? await Task.sleep(nanoseconds: 140_000_000) }
            try? await Task.sleep(nanoseconds: 250_000_000)
            withAnimation(.easeOut(duration: 0.25)) { text = "best free "; flash = true }
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation { flash = false }
            try? await Task.sleep(nanoseconds: 1_400_000_000)
        }
        _ = prefix
    }
}

/// Short intro shown the first time a dashboard section is opened.
struct FeatureIntroSheet: View {
    let section: NavSection
    let dismiss: () -> Void
    var copy: (String, String, String) {
        switch section {
        case .words: return ("You can't search what you can't type.", "Words here vanish as you type them, anywhere on your Mac.", "Removing one takes a 60-second wait.")
        case .allowlist: return ("Fewer false alarms.", "Words that contain a blocked word but are harmless.", "Adding one waits 60 seconds.")
        case .sites: return ("Some doors stay shut.", "Blocked sites close the moment they open in your browser.", "No way through.")
        case .social: return ("Social media has you fried.", "A pause before every social site: go back, or do the math.", "Loosening waits 60 seconds.")
        case .cinema: return ("Finish what you started.", "Lock yourself into one app until the timer ends. Want out? Earn it. 5 quick problems.", "Math Mode on by default. Emergency exit behind a 60-second wait.")
        case .reminder: return ("Talk to future you.", "The words you see when it's hard.", "Kind, not harsh.")
        default: return ("", "", "")
        }
    }
    var body: some View {
        ZStack {
            GrainBackground()
            VStack(spacing: 18) {
                FeatureScreen(kicker: section.rawValue.uppercased(), title: copy.0, body: copy.1, strictness: copy.2) {
                    Image(systemName: section.icon).font(.system(size: 48)).foregroundStyle(Theme.accent)
                }
                Button("Got it", action: dismiss).buttonStyle(AccentButton()).keyboardShortcut(.defaultAction)
            }.padding(40)
        }
        .frame(width: 620, height: 480)
    }
}
