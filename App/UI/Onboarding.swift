import SwiftUI

struct OnboardingView: View {
    @ObservedObject var store = Store.shared
    @State private var step = 0
    @State private var why = ""
    @State private var word = ""
    @State private var granted = Permissions.accessibility
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            Card(padding: 34) {
                VStack(alignment: .leading, spacing: 18) {
                    Label2(text: "Step \(step + 1) of 3")
                    switch step {
                    case 0:
                        Text("Why are you here?").font(.system(size: 26, weight: .bold))
                        Text("Write one line for the version of you who's having a hard moment. You'll see it every time you open Word Blocker.").foregroundStyle(Theme.dim)
                        DarkField(placeholder: "I want to be present for…", text: $why)
                    case 1:
                        Text("Let it see what you type").font(.system(size: 26, weight: .bold))
                        Text("Word Blocker needs Accessibility to erase blocked words and read your browser's address bar. Nothing you type is stored or sent anywhere — it stays on this Mac.").foregroundStyle(Theme.dim)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("1. Click Open Settings").font(Theme.mono(12))
                            Text("2. Turn on “Word Blocker” under Accessibility").font(Theme.mono(12))
                            Text("3. Come back here — it connects automatically").font(Theme.mono(12))
                        }.foregroundStyle(Theme.text)
                        HStack {
                            Button("Open Settings") { Permissions.prompt(); Permissions.openSettings() }.buttonStyle(AccentButton(prominent: !granted))
                            Label(granted ? "Connected" : "Waiting…", systemImage: granted ? "checkmark.circle.fill" : "circle.dotted")
                                .foregroundStyle(granted ? Theme.accent : Theme.dim).font(.system(size: 13))
                        }
                    default:
                        Text("Add your first word").font(.system(size: 26, weight: .bold))
                        Text("Common adult terms are already blocked. Add anything personal that leads you somewhere you don't want to go.").foregroundStyle(Theme.dim)
                        DarkField(placeholder: "A word or phrase (optional)", text: $word)
                    }
                    HStack {
                        if step > 0 { Button("Back") { step -= 1 }.buttonStyle(AccentButton(prominent: false)) }
                        Spacer()
                        Button(step == 2 ? "Start protecting" : "Continue") { next() }.buttonStyle(AccentButton())
                    }
                }
                .foregroundStyle(Theme.text)
            }
            .frame(width: 520)
        }
        .onReceive(timer) { _ in
            granted = Permissions.accessibility
            if granted { KeyboardGuard.shared.start() }
        }
    }

    private func next() {
        if step < 2 { step += 1; return }
        let w = word.trimmingCharacters(in: .whitespaces)
        store.update { s in
            s.why = why
            if !w.isEmpty { s.words.insert(BlockedWord(word: w, substring: true), at: 0) }
            s.onboarded = true
            s.streakStart = Date()
        }
    }
}
