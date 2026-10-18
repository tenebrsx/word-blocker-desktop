# Word Blocker Desktop

The Mac companion to the iOS self-control browser. Rebuilt from [word-blocker](https://github.com/tenebrsx/word-blocker) with a dark dashboard and the iOS app's stronger engine.

- **Word Block**: erases blocked words system-wide as you type (CGEventTap + synthetic backspaces). Uses the exact `WordBlockEngine` from ios-browser (leet, separators, repeated letters, homoglyphs, zero-width chars, fuzzy only on evasion signs) and its shared test vectors. Enter is held back if the line ends in a blocked word.
- **Allowlist**, **Blocked Sites** (built-in adult list + yours, no way through), **Social Pause** (Go Back or N math problems for M minutes).
- **Always on**: no off switches. Removing/loosening waits 60s (monotonic clock; leaving the app restarts it).
- **Days strong** + best streak, protected by ClockGuard (rollback guard + HTTPS Date header).
- Dashboard window + menu bar extra. Data in `~/Library/Application Support/WordBlockerDesktop/state.json` (survives reinstall).

## Site blocking limits
Reads the active tab URL in supported browsers via Accessibility, then closes the tab (Cmd+W). No admin or paid entitlements needed. Limits: only known browsers, only while the app runs, a page can show for ~0.6s before closing, and quitting the app stops it. A future option is a privileged helper writing `/etc/hosts` or a Network Extension (paid account).

## Build
```
xcodegen generate
xcodebuild -project WordBlockerDesktop.xcodeproj -scheme WordBlockerDesktop -configuration Debug -derivedDataPath build build
```
Grant Accessibility to Word Blocker on first launch.

## Tests
`swift test` runs the engine, site matching, math, cooldown, streak, typing buffer and Cinema Math Mode logic anywhere (Linux too). `xcodebuild -project WordBlockerDesktop.xcodeproj -scheme WordBlockerDesktop test` runs the same suite on the Mac.

## Cinema Math Mode
Trying to leave a Cinema session shows a gate: 5 quick problems to get out, or a big Stay Focused button. Setting: after solving, either you are free until you return to the app (then it re-locks, default) or the session ends. Turning Math Mode off, fewer problems, or switching to "end session" waits 60s.
