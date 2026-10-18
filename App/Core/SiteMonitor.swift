import Cocoa
import ApplicationServices

/// Website blocking without paid entitlements or admin rights: reads the active tab's URL in
/// supported browsers through Accessibility (same technique as the original Word Blocker),
/// closes blocked tabs with Cmd+W and shows your reminder. Social sites get the math pause.
final class SiteMonitor {
    static let shared = SiteMonitor()

    static let browsers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome", "com.google.Chrome.beta",
        "com.google.Chrome.canary", "org.chromium.Chromium", "company.thebrowser.Browser", "company.thebrowser.dia",
        "com.brave.Browser", "com.brave.Browser.beta", "com.microsoft.edgemac", "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition", "app.zen-browser.zen", "com.operasoftware.Opera",
        "com.operasoftware.OperaGX", "com.vivaldi.Vivaldi", "com.kagi.kagimacOS", "com.duckduckgo.macos.browser",
        "ai.perplexity.comet",
    ]

    private var timer: Timer?
    private var axEnabled: Set<pid_t> = []
    private var lastAction: (key: String, at: TimeInterval) = ("", 0)
    /// Social pattern -> monotonic expiry.
    private var socialAllowed: [String: TimeInterval] = [:]
    private(set) var gateOpen = false

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in self?.inspect() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    func inspect() {
        guard Permissions.accessibility, !gateOpen,
              let app = NSWorkspace.shared.frontmostApplication,
              let bid = app.bundleIdentifier, Self.browsers.contains(bid) else { return }
        let pid = app.processIdentifier
        if !axEnabled.contains(pid) {
            axEnabled.insert(pid)
            let ref = AXUIElementCreateApplication(pid)
            AXUIElementSetAttributeValue(ref, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(ref, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
        guard var url = activeURL(pid: pid) else { return }
        if !url.contains("://") { url = "https://" + url }
        let store = Store.shared

        if let hit = store.siteMatcher.match(url) {
            guard debounce("block:" + hit) else { return }
            Synth.closeTab()
            Toast.show(store.state.reminder.isEmpty ? "That site is blocked. You're doing great." : store.state.reminder, seconds: 4)
            store.recordBlock()
            return
        }
        if let social = store.socialMatcher.match(url) {
            socialAllowed = socialAllowed.filter { $0.value > now() }
            if socialAllowed[social] != nil { return }
            guard debounce("social:" + social) else { return }
            gateOpen = true
            SocialGateWindow.present(site: social) { [weak self] allowed in
                guard let self else { return }
                self.gateOpen = false
                NSRunningApplication(processIdentifier: pid)?.activate()
                if allowed {
                    self.socialAllowed[social] = self.now() + TimeInterval(store.state.socialMinutes * 60)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { Synth.closeTab() }
                }
            }
        }
    }

    func timeLeft(for pattern: String) -> TimeInterval? {
        guard let e = socialAllowed[pattern], e > now() else { return nil }
        return e - now()
    }

    private func debounce(_ key: String) -> Bool {
        if lastAction.key == key && now() - lastAction.at < 1.5 { return false }
        lastAction = (key, now())
        return true
    }

    // MARK: URL extraction (from Word Blocker's BrowserMonitor)

    private func activeURL(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var w: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &w) == .success
                || AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &w) == .success,
              let wv = w else { return nil }
        let win = wv as! AXUIElement
        var v: CFTypeRef?
        if AXUIElementCopyAttributeValue(win, kAXDocumentAttribute as CFString, &v) == .success, let s = v as? String, !s.isEmpty { return s }
        if let s = webAreaURL(win, 0) { return s }
        var f: CFTypeRef?
        var focused: AXUIElement?
        if AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &f) == .success, let fv = f { focused = (fv as! AXUIElement) }
        return addressBar(win, 0, skip: focused)
    }

    private func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }

    private func children(_ e: AXUIElement) -> [AXUIElement] { attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] }

    private func webAreaURL(_ e: AXUIElement, _ depth: Int) -> String? {
        if depth > 14 { return nil }
        if (attr(e, kAXRoleAttribute) as? String) == "AXWebArea" {
            let u = attr(e, "AXURL")
            return (u as? URL)?.absoluteString ?? (u as? String)
        }
        for c in children(e) { if let s = webAreaURL(c, depth + 1) { return s } }
        return nil
    }

    private func addressBar(_ e: AXUIElement, _ depth: Int, skip: AXUIElement?) -> String? {
        if depth > 12 { return nil }
        if let skip, CFEqual(skip, e) { return nil }
        let role = attr(e, kAXRoleAttribute) as? String ?? ""
        if role == "AXWebArea" { return nil }
        if (attr(e, "AXIdentifier") as? String) == "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD", let s = attr(e, kAXValueAttribute) as? String, !s.isEmpty { return s }
        if role == "AXTextField" || role == "AXComboBox" {
            let desc = (attr(e, kAXDescriptionAttribute) as? String ?? "").lowercased()
            if desc.contains("address") || desc.contains("url"), let s = attr(e, kAXValueAttribute) as? String,
               !s.contains(" "), s.contains(".") { return s }
        }
        for c in children(e) { if let s = addressBar(c, depth + 1, skip: skip) { return s } }
        return nil
    }
}
