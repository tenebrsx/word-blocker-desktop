import SwiftUI

struct ReleasesView: View {
    @ObservedObject var checker = ReleaseChecker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label2(text: "This Mac")
                        HStack(spacing: 10) {
                            Text("v\(checker.currentVersion)").font(Theme.mono(26, .semibold)).foregroundStyle(Theme.text)
                            if let u = checker.update {
                                Text("UPDATE AVAILABLE · \(u.tagName)").font(Theme.mono(10, .bold)).foregroundStyle(.black)
                                    .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Theme.accent))
                            } else if checker.phase == .loaded {
                                Text("UP TO DATE").font(Theme.mono(10, .bold)).foregroundStyle(Theme.dim)
                                    .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Theme.panelHi))
                            }
                        }
                        if let d = checker.lastChecked {
                            Text("Last checked \(d.formatted(.relative(presentation: .named)))").font(Theme.mono(10)).foregroundStyle(Theme.dim)
                        }
                    }
                    Spacer()
                    Link(destination: ReleaseSource.pageURL) { Label("View on GitHub", systemImage: "arrow.up.right.square") }
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.dim)
                    Button(checker.phase == .loading ? "Checking…" : "Check now") { checker.check() }
                        .buttonStyle(AccentButton(prominent: false)).disabled(checker.phase == .loading)
                }
            }
            switch checker.phase {
            case .idle, .loading where checker.releases.isEmpty:
                HStack { ProgressView().controlSize(.small); Text("Looking for releases…").foregroundStyle(Theme.dim) }.padding(.top, 10)
            case .failed(let msg):
                Card { VStack(alignment: .leading, spacing: 8) {
                    Label("Couldn't load releases", systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warn)
                    Text(msg).font(.system(size: 13)).foregroundStyle(Theme.dim)
                } }
            default:
                if checker.releases.isEmpty {
                    Card { Text("No releases yet. New versions will show up here.").font(.system(size: 13)).foregroundStyle(Theme.dim) }
                } else {
                    ForEach(checker.releases) { ReleaseCard(release: $0, isUpdate: $0.id == checker.update?.id) }
                }
            }
        }
        .onAppear { if checker.phase != .loading { checker.check() } }
    }
}

struct ReleaseCard: View {
    let release: GitHubRelease
    let isUpdate: Bool
    @ObservedObject var checker = ReleaseChecker.shared

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(release.tagName).font(Theme.mono(14, .bold)).foregroundStyle(Theme.accent)
                    Text(release.name ?? "").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    if release.prerelease { tag("PRE-RELEASE") }
                    if isUpdate { tag("NEW") }
                    Spacer()
                    if let d = release.publishedAt { Text(d.formatted(date: .abbreviated, time: .omitted)).font(Theme.mono(11)).foregroundStyle(Theme.dim) }
                }
                if let body = release.body, !body.isEmpty {
                    Text(markdown(body)).font(.system(size: 13)).foregroundStyle(Theme.text.opacity(0.85)).textSelection(.enabled)
                }
                ForEach(release.assets) { a in
                    HStack(spacing: 10) {
                        Image(systemName: "shippingbox").foregroundStyle(Theme.dim)
                        Text(a.name).font(Theme.mono(12)).foregroundStyle(Theme.text)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(a.size), countStyle: .file)).font(Theme.mono(11)).foregroundStyle(Theme.dim)
                        Text("↓ \(a.downloadCount)").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                        Spacer()
                        if let p = checker.progress[a.id] {
                            ProgressView(value: p).tint(Theme.accent).frame(width: 120)
                        } else if let url = checker.finished[a.id] {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(AccentButton(prominent: false))
                        } else {
                            Button("Download") { checker.download(a) }.buttonStyle(AccentButton(prominent: isUpdate))
                        }
                    }
                    .padding(10).background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.3)))
                }
                Link("Open release page", destination: release.htmlURL).font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
        }
    }

    private func tag(_ t: String) -> some View {
        Text(t).font(Theme.mono(9, .bold)).foregroundStyle(Theme.dim).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Theme.panelHi))
    }

    private func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
