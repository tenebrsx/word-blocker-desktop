import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if !KeyboardGuard.shared.start() { Permissions.prompt() }
        SiteMonitor.shared.start()
        Store.shared.verifyClock()
        // Pick up Accessibility as soon as it's granted.
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            if Permissions.accessibility { KeyboardGuard.shared.start() }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct WordBlockerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ObservedObject private var store = Store.shared

    var body: some Scene {
        Window("Word Blocker", id: "dashboard") {
            DashboardView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 720)

        MenuBarExtra {
            MenuContent()
        } label: {
            Image(systemName: "shield.lefthalf.filled")
        }
    }
}

struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var store = Store.shared
    var body: some View {
        Text("\(store.daysStrong) days strong · best \(store.bestStreak)")
        Text("\(store.blocksToday) blocked today")
        Divider()
        Button("Open Dashboard") { NSApp.activate(ignoringOtherApps: true); openWindow(id: "dashboard") }
        Text(KeyboardGuard.shared.isActive ? "Protection active" : "Needs Accessibility permission")
    }
}
