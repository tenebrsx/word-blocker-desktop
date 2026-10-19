import Foundation
import AppKit
import Combine

/// Fetches GitHub releases (no token), caches the last result, downloads assets to ~/Downloads.
final class ReleaseChecker: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = ReleaseChecker()

    enum Phase: Equatable { case idle, loading, loaded, failed(String) }

    @Published private(set) var releases: [GitHubRelease] = []
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastChecked: Date?
    @Published private(set) var progress: [Int: Double] = [:]     // asset id -> 0...1
    @Published private(set) var finished: [Int: URL] = [:]

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    var update: GitHubRelease? { SemVer.update(in: releases, current: currentVersion) }

    private let cacheURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("WordBlockerDesktop/releases-cache.json")
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    private var taskAsset: [Int: GitHubRelease.Asset] = [:]

    private override init() {
        super.init()
        if let data = try? Data(contentsOf: cacheURL), let list = try? GitHubRelease.decodeList(data) {
            releases = list
            lastChecked = (try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            phase = .loaded
        }
    }

    func check(announce: Bool = false) {
        phase = .loading
        var req = URLRequest(url: ReleaseSource.apiURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("WordBlockerDesktop/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            DispatchQueue.main.async { self?.handle(data, resp as? HTTPURLResponse, err, announce: announce) }
        }.resume()
    }

    private func handle(_ data: Data?, _ resp: HTTPURLResponse?, _ err: Error?, announce: Bool) {
        if let err { fail("Couldn't reach GitHub. Check your connection. (\(err.localizedDescription))"); return }
        guard let resp, let data else { fail("No response from GitHub."); return }
        switch resp.statusCode {
        case 200:
            do {
                releases = try GitHubRelease.decodeList(data)
                try? data.write(to: cacheURL, options: .atomic)
                lastChecked = Date()
                phase = .loaded
                if announce {
                    if let u = update { Toast.show("Update available: \(u.tagName)", seconds: 4) }
                    else { Toast.show("You're up to date (\(currentVersion)).") }
                }
            } catch { fail("GitHub sent something unexpected.") }
        case 404: fail("Releases aren't public yet. The repo \(ReleaseSource.owner)/\(ReleaseSource.repo) is private or doesn't exist.")
        case 403, 429: fail("GitHub's rate limit was hit. Try again in a bit.")
        default: fail("GitHub returned an error (\(resp.statusCode)).")
        }
    }

    private func fail(_ msg: String) {
        // Keep showing the cache if we have one.
        phase = releases.isEmpty ? .failed(msg) : .loaded
        if !releases.isEmpty { Toast.show(msg, seconds: 3) }
    }

    // MARK: Download

    func download(_ asset: GitHubRelease.Asset) {
        let task = session.downloadTask(with: asset.browserDownloadURL)
        taskAsset[task.taskIdentifier] = asset
        progress[asset.id] = 0
        task.resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let a = taskAsset[downloadTask.taskIdentifier] else { return }
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : Int64(max(a.size, 1))
        progress[a.id] = min(1, Double(totalBytesWritten) / Double(total))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let a = taskAsset[downloadTask.taskIdentifier] else { return }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var dest = downloads.appendingPathComponent(a.name)
        var n = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            let base = (a.name as NSString).deletingPathExtension, ext = (a.name as NSString).pathExtension
            dest = downloads.appendingPathComponent("\(base) (\(n))" + (ext.isEmpty ? "" : ".\(ext)")); n += 1
        }
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            finished[a.id] = dest
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } catch { Toast.show("Couldn't save \(a.name).") }
        progress[a.id] = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let a = taskAsset[task.taskIdentifier] else { return }
        progress[a.id] = nil
        Toast.show("Download failed: \(error.localizedDescription)")
    }
}
