import SwiftUI
import Charts

enum NavSection: String, CaseIterable, Identifiable {
    case overview = "Overview", words = "Blocked Words", allowlist = "Allowlist", sites = "Blocked Sites",
         social = "Social Pause", cinema = "Cinema", reminder = "Reminder & Why", releases = "Releases", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .words: return "text.badge.xmark"
        case .allowlist: return "checkmark.seal"
        case .sites: return "globe.badge.chevron.backward"
        case .social: return "hourglass"
        case .cinema: return "film.stack"
        case .reminder: return "heart.text.square"
        case .releases: return "arrow.down.circle"
        case .settings: return "gearshape"
        }
    }
}

struct DashboardView: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var cooldown = Cooldown.shared
    @State private var section: NavSection = .overview
    @State private var intro: NavSection?

    var body: some View {
        ZStack {
            GrainBackground()
            HStack(spacing: 0) {
                sidebar
                Rectangle().fill(Theme.stroke).frame(width: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(section.rawValue).font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.text)
                        content
                    }
                    .padding(28)
                    .frame(maxWidth: 860, alignment: .leading)
                }
            }
            if !store.state.onboarded { OnboardingView().transition(.opacity).zIndex(1) }
        }
        .sheet(item: $cooldown.pending) { _ in CooldownSheet() }
        .sheet(item: $intro) { s in FeatureIntroSheet(section: s) { store.update { $0.seenIntros.append(s.rawValue) }; intro = nil } }
        .preferredColorScheme(.dark)
        .frame(minWidth: 940, minHeight: 620)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled").foregroundStyle(Theme.accent)
                Text("WORD BLOCKER").font(Theme.mono(12, .bold)).tracking(2).foregroundStyle(Theme.text)
            }
            .padding(.bottom, 22).padding(.top, 30)
            ForEach(NavSection.allCases) { s in
                Button {
                    section = s
                    if store.state.onboarded, !store.state.seenIntros.contains(s.rawValue), ![.overview, .settings, .releases].contains(s) { intro = s }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: s.icon).frame(width: 18)
                        Text(s.rawValue).font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .foregroundStyle(section == s ? Theme.text : Theme.dim)
                    .background(RoundedRectangle(cornerRadius: 8).fill(section == s ? Theme.panelHi : .clear))
                    .overlay(alignment: .leading) {
                        if section == s { RoundedRectangle(cornerRadius: 2).fill(Theme.accent).frame(width: 3, height: 16).offset(x: -2) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            StatusPill()
        }
        .padding(.horizontal, 14).padding(.bottom, 16)
        .frame(width: 220)
        .background(Color.black.opacity(0.25))
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .overview: OverviewView()
        case .words: WordsView()
        case .allowlist: AllowlistView()
        case .sites: SitesView()
        case .social: SocialView()
        case .cinema: CinemaView()
        case .reminder: ReminderView()
        case .releases: ReleasesView()
        case .settings: SettingsView()
        }
    }
}

struct StatusPill: View {
    @State private var on = KeyboardGuard.shared.isActive
    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(on ? Theme.accent : Theme.warn).frame(width: 7, height: 7)
                .shadow(color: (on ? Theme.accent : Theme.warn).opacity(0.8), radius: 4)
            Text(on ? "PROTECTION ACTIVE" : "NEEDS ACCESSIBILITY").font(Theme.mono(10, .semibold)).foregroundStyle(Theme.dim)
        }
        .onReceive(timer) { _ in on = KeyboardGuard.shared.isActive }
    }
}

// MARK: Overview

struct OverviewView: View {
    @ObservedObject var store = Store.shared
    @State private var confirmReset = false

    var body: some View {
        let days = store.lastDays(7)
        VStack(alignment: .leading, spacing: 16) {
            Card(padding: 26) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label2(text: "Days strong")
                        Text("\(store.daysStrong)").font(Theme.mono(84, .bold)).foregroundStyle(Theme.accent)
                            .shadow(color: Theme.accent.opacity(0.35), radius: 18)
                        Text(store.state.why.isEmpty ? "Every day counts." : "“\(store.state.why)”")
                            .font(.system(size: 13)).foregroundStyle(Theme.dim).lineLimit(2)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Label2(text: "Best streak")
                        Text("\(store.bestStreak)d").font(Theme.mono(28, .semibold)).foregroundStyle(Theme.text)
                        Button("Start a new count") { confirmReset = true }
                            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.dim)
                    }
                }
            }
            HStack(spacing: 16) {
                stat("Blocked today", "\(store.blocksToday)")
                stat("This week", "\(days.reduce(0) { $0 + $1.count })")
                stat("All time", "\(store.state.totalBlocks)")
            }
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Label2(text: "Blocks · last 7 days")
                    Chart(days, id: \.date) { d in
                        BarMark(x: .value("Day", d.date, unit: .day), y: .value("Blocks", d.count))
                            .foregroundStyle(Theme.accent.gradient).cornerRadius(4)
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated)).foregroundStyle(Theme.dim) } }
                    .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Theme.stroke); AxisValueLabel().foregroundStyle(Theme.dim) } }
                    .frame(height: 160)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label2(text: "Protection")
                    row("Word Block", "\(store.state.words.count) words · system-wide", KeyboardGuard.shared.isActive)
                    row("Blocked Sites", "\(store.builtInSites.count + store.state.sites.count) sites · in your browsers", Permissions.accessibility)
                    row("Social Pause", "\(store.state.socialSites.count) sites · \(store.state.socialProblems) problems", Permissions.accessibility)
                    row("Self-control lock", "60s wait to remove or loosen anything", true)
                }
            }
        }
        .alert("Start a new count?", isPresented: $confirmReset) {
            Button("Start new count", role: .destructive) { store.startNewCount() }
            Button("Not now", role: .cancel) {}
        } message: { Text("Slips happen. Your best streak (\(store.bestStreak) days) is kept.") }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        Card { VStack(alignment: .leading, spacing: 6) { Label2(text: label); Text(value).font(Theme.mono(30, .semibold)).foregroundStyle(Theme.text) } }
    }

    private func row(_ title: String, _ detail: String, _ ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(ok ? Theme.accent : Theme.warn)
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
            Spacer()
            Text(detail).font(Theme.mono(11)).foregroundStyle(Theme.dim)
        }
    }
}

// MARK: Lists

struct BlurredText: View {
    let text: String
    @State private var reveal = false
    var body: some View {
        Text(text).font(Theme.mono(13)).foregroundStyle(Theme.text)
            .blur(radius: reveal ? 0 : 6)
            .onLongPressGesture(minimumDuration: 60, pressing: { reveal = $0 }, perform: {})
            .help("Press and hold to reveal")
    }
}

struct ListEditor: View {
    let title: String
    let hint: String
    let items: [String]
    var blurred = false
    var badge: (String) -> String? = { _ in nil }
    let add: (String) -> Void
    let remove: (String) -> Void
    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(hint).font(.system(size: 13)).foregroundStyle(Theme.dim)
            HStack {
                DarkField(placeholder: title, text: $input, onSubmit: commit)
                Button("Add", action: commit).buttonStyle(AccentButton())
            }
            Card(padding: 6) {
                if items.isEmpty {
                    Text("Nothing here yet.").font(.system(size: 13)).foregroundStyle(Theme.dim).padding(14)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(items, id: \.self) { item in
                            HStack {
                                if blurred { BlurredText(text: item) } else { Text(item).font(Theme.mono(13)).foregroundStyle(Theme.text) }
                                if let b = badge(item) { Text(b).font(Theme.mono(9, .semibold)).foregroundStyle(Theme.dim).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Theme.panelHi)) }
                                Spacer()
                                Button { remove(item) } label: { Image(systemName: "minus.circle").foregroundStyle(Theme.dim) }.buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            Divider().overlay(Theme.stroke)
                        }
                    }
                }
            }
        }
    }

    private func commit() {
        let v = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        add(v); input = ""
    }
}

struct WordsView: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        ListEditor(title: "Add a word or phrase", hint: "Erased as you type, anywhere on your Mac. Catches tricks like p0rn, p.o.r.n, look-alike letters and stretched letters. Hold a word to reveal it. Removing one waits 60 seconds.",
                   items: store.state.words.map(\.word), blurred: true,
                   badge: { w in store.state.words.first { $0.word == w }?.substring == true ? "ANYWHERE" : "WHOLE WORD" },
                   add: { w in store.update { s in if !s.words.contains(where: { $0.word.lowercased() == w.lowercased() }) { s.words.insert(BlockedWord(word: w, substring: true), at: 0) } } },
                   remove: { w in Cooldown.shared.request("Remove a blocked word?", detail: "This word will stop being erased.") { store.update { $0.words.removeAll { $0.word == w } } } })
    }
}

struct AllowlistView: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        ListEditor(title: "Add an allowed word", hint: "Words that contain a blocked word but are fine (for example “scunthorpe”). Adding one loosens protection, so it waits 60 seconds; removing is instant.",
                   items: store.state.allowlist,
                   add: { w in Cooldown.shared.request("Allow “\(w)”?", detail: "Allowed words are never erased.") { store.update { if !$0.allowlist.contains(w) { $0.allowlist.insert(w, at: 0) } } } },
                   remove: { w in store.update { $0.allowlist.removeAll { $0 == w } } })
    }
}

struct SitesView: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ListEditor(title: "Add a site, e.g. example.com", hint: "When a blocked site opens in Safari, Chrome, Arc, Brave, Edge, Firefox and others, its tab closes and your reminder appears. There's no way through. Removing a site waits 60 seconds.",
                       items: store.state.sites, blurred: true,
                       add: { s in let h = BlockedSitesMatcher.normalizeHost(s); guard !h.isEmpty else { return }; store.update { if !$0.sites.contains(h) { $0.sites.insert(h, at: 0) } } },
                       remove: { h in Cooldown.shared.request("Unblock this site?") { store.update { $0.sites.removeAll { $0 == h } } } })
            Card { HStack { Image(systemName: "lock.fill").foregroundStyle(Theme.accent); Text("Plus \(store.builtInSites.count) built-in adult sites, always on.").font(.system(size: 12)).foregroundStyle(Theme.dim) } }
        }
    }
}

struct SocialView: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Label2(text: "Your pause message")
                    TextEditor(text: Binding(get: { store.state.socialMessage }, set: { v in store.update { $0.socialMessage = v } }))
                        .font(.system(size: 13)).scrollContentBackground(.hidden).frame(height: 60)
                    HStack(spacing: 24) {
                        Stepper("Session: \(store.state.socialMinutes) min", value: Binding(get: { store.state.socialMinutes }, set: { v in setMinutes(v) }), in: 1...60)
                        Stepper("Problems: \(store.state.socialProblems)", value: Binding(get: { store.state.socialProblems }, set: { v in setProblems(v) }), in: 1...30)
                    }
                    .font(Theme.mono(12)).foregroundStyle(Theme.text)
                }
            }
            ListEditor(title: "Add a social site (e.g. youtube.com/shorts)", hint: "Opening one shows a pause: Go Back, or solve quick math problems to continue for a while. Adding is instant; removing or loosening waits 60 seconds.",
                       items: store.state.socialSites,
                       add: { s in let p = SocialSiteMatcher.normalizePattern(s); guard !p.isEmpty else { return }; store.update { if !$0.socialSites.contains(p) { $0.socialSites.insert(p, at: 0) } } },
                       remove: { p in Cooldown.shared.request("Remove \(p) from Social Pause?") { store.update { $0.socialSites.removeAll { $0 == p } } } })
        }
    }

    private func setMinutes(_ v: Int) {
        if SocialSessionPolicy.isLooser(minutes: v, than: store.state.socialMinutes) {
            Cooldown.shared.request("Longer sessions (\(v) min)?") { store.update { $0.socialMinutes = v } }
        } else { store.update { $0.socialMinutes = v } }
    }
    private func setProblems(_ v: Int) {
        if SocialSessionPolicy.isLooser(problems: v, than: store.state.socialProblems) {
            Cooldown.shared.request("Fewer problems (\(v))?") { store.update { $0.socialProblems = v } }
        } else { store.update { $0.socialProblems = v } }
    }
}

struct ReminderView: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            editor("Why I started", "Shown on your Overview. Write it for the you who's struggling.", \.why)
            editor("Reminder when a site is blocked", "A kind word, not a scolding.", \.reminder)
        }
    }
    private func editor(_ title: String, _ hint: String, _ kp: WritableKeyPath<AppState, String>) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label2(text: title)
                Text(hint).font(.system(size: 12)).foregroundStyle(Theme.dim)
                TextEditor(text: Binding(get: { store.state[keyPath: kp] }, set: { v in store.update { $0[keyPath: kp] = v } }))
                    .font(.system(size: 14)).scrollContentBackground(.hidden).frame(height: 80)
                    .padding(8).background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.35)))
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Label2(text: "Feedback")
                    Toggle("Show a small note when a word is removed", isOn: Binding(get: { store.state.toastOn }, set: { v in store.update { $0.toastOn = v } }))
                    Toggle("Check for updates on launch", isOn: Binding(get: { store.state.checkUpdatesOnLaunch }, set: { v in store.update { $0.checkUpdatesOnLaunch = v } }))
                    Toggle("Play a soft sound", isOn: Binding(get: { store.state.soundOn }, set: { v in store.update { $0.soundOn = v } }))
                }
                .toggleStyle(.switch).tint(Theme.accent).font(.system(size: 13))
            }
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Label2(text: "Permissions")
                    HStack {
                        Text(Permissions.accessibility ? "Accessibility is on." : "Accessibility is off — Word Block and site blocking can't run.")
                            .font(.system(size: 13)).foregroundStyle(Permissions.accessibility ? Theme.text : Theme.warn)
                        Spacer()
                        Button("Open Settings") { Permissions.prompt(); Permissions.openSettings() }.buttonStyle(AccentButton(prominent: false))
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Label2(text: "Always on")
                    Text("Protections have no off switch. Removing or loosening anything waits 60 seconds; leaving the app restarts the wait and changing the clock doesn't skip it. Your data lives in ~/Library/Application Support/WordBlockerDesktop, so it survives reinstalling.")
                        .font(.system(size: 12)).foregroundStyle(Theme.dim)
                }
            }
        }
    }
}

struct CooldownSheet: View {
    @ObservedObject var cooldown = Cooldown.shared
    var body: some View {
        VStack(spacing: 16) {
            Text(cooldown.pending?.title ?? "").font(.system(size: 17, weight: .semibold))
            if let d = cooldown.pending?.detail, !d.isEmpty { Text(d).font(.system(size: 12)).foregroundStyle(Theme.dim) }
            Text(cooldown.isReady ? "Ready" : "\(cooldown.remaining)s").font(Theme.mono(44, .bold)).foregroundStyle(Theme.accent)
            Text("Take a breath. If you still want this in a minute, it's yours. Leaving the app restarts the wait.")
                .font(.system(size: 12)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            HStack {
                Button("Confirm") { cooldown.confirm() }.buttonStyle(AccentButton(prominent: false)).disabled(!cooldown.isReady).opacity(cooldown.isReady ? 1 : 0.4)
                Button("Never Mind") { cooldown.cancel() }.buttonStyle(AccentButton()).keyboardShortcut(.defaultAction)
            }
        }
        .padding(30).frame(width: 380)
        .background(Theme.panel)
    }
}

struct CinemaView: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var cinema = Cinema.shared
    @State private var appID: pid_t = 0
    private var apps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pick an app and a timer. Until it ends, trying to leave (Cmd-Tab, Cmd-H/M/Q/W, Esc, leaving full screen, clicking another app) pulls you back. With Math Mode on, you can earn your way out with quick problems. Word Blocker stays reachable for the emergency exit, which waits 60 seconds. Settings apply to new sessions.")
                .font(.system(size: 13)).foregroundStyle(Theme.dim)
            if cinema.isActive {
                Card(padding: 26) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label2(text: "Locked in · \(cinema.target?.localizedName ?? "")")
                        Text(String(format: "%02d:%02d", cinema.remaining / 60, cinema.remaining % 60)).font(Theme.mono(64, .bold)).foregroundStyle(Theme.accent)
                        Button("Emergency exit") { cinema.requestEarlyExit() }.buttonStyle(AccentButton(prominent: false))
                    }
                }
            } else {
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Label2(text: "New session")
                        Picker("App", selection: $appID) {
                            Text("Choose an app").tag(pid_t(0))
                            ForEach(apps, id: \.processIdentifier) { a in Text(a.localizedName ?? "App").tag(a.processIdentifier) }
                        }
                        Stepper("Length: \(store.state.cinemaMinutes) min", value: Binding(get: { store.state.cinemaMinutes }, set: { v in store.update { $0.cinemaMinutes = v } }), in: 5...240, step: 5)
                            .font(Theme.mono(12))
                        Divider().overlay(Theme.stroke)
                        Toggle("Math Mode: want out? Earn it with quick problems", isOn: Binding(get: { store.state.cinema.mathMode }, set: { v in setPolicy { $0.mathMode = v } }))
                            .toggleStyle(.switch).tint(Theme.accent).font(.system(size: 13))
                        if store.state.cinema.mathMode {
                            Stepper("Problems to get out: \(store.state.cinema.problems)", value: Binding(get: { store.state.cinema.problems }, set: { v in setPolicy { $0.problems = CinemaPolicy.clampProblems(v) } }), in: 1...30)
                                .font(Theme.mono(12))
                            Picker("After solving", selection: Binding(get: { store.state.cinema.exitBehavior }, set: { v in setPolicy { $0.exitBehavior = v } })) {
                                Text("Let me out, lock again when I come back").tag(CinemaPolicy.ExitBehavior.relockOnReturn)
                                Text("End the session").tag(CinemaPolicy.ExitBehavior.endSession)
                            }
                        }
                        Button("Lock me in") {
                            if let a = apps.first(where: { $0.processIdentifier == appID }) { cinema.start(app: a, minutes: store.state.cinemaMinutes) }
                        }
                        .buttonStyle(AccentButton()).disabled(appID == 0 || !Permissions.accessibility)
                        if !Permissions.accessibility { Text("Needs Accessibility permission.").font(.system(size: 11)).foregroundStyle(Theme.warn) }
                    }
                }
            }
        }
    }

    private func setPolicy(_ change: (inout CinemaPolicy) -> Void) {
        var p = store.state.cinema
        change(&p)
        if p.isLooser(than: store.state.cinema) {
            Cooldown.shared.request("Loosen Cinema?", detail: "Math Mode keeps you honest.") { store.update { $0.cinema = p } }
        } else {
            store.update { $0.cinema = p }
        }
    }
}
