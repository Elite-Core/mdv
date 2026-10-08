import Cocoa
import Security

/// Self-update over a GitHub release feed. Trust comes from Apple code signing: the downloaded
/// app must be signed by this app's Team ID (MDVTeamID in Info.plist) or nothing is touched.
struct ReleaseInfo: Decodable {
    let version: String
    let build: Int
    let url: String
    let notes: String?
}

final class Updater {
    static let shared = Updater()

    private func info(_ k: String) -> String? { Bundle.main.object(forInfoDictionaryKey: k) as? String }
    private var feed: String? { info("MDVUpdateFeed") }
    private var page: String? { info("MDVReleasesPage") }
    private var teamID: String? { info("MDVTeamID") }
    var currentBuild: Int { Int(info("CFBundleVersion") ?? "") ?? 0 }
    var currentVersion: String { info("CFBundleShortVersionString") ?? "?" }
    private var busy = false

    /// Launch-time check: quiet, at most once a day, only speaks up when there is something new.
    func checkInBackground() {
        guard feed != nil, teamID != nil else { return }
        let last = UserDefaults.standard.double(forKey: "updateLastCheck")
        guard Date().timeIntervalSince1970 - last > 20 * 3600 else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "updateLastCheck")
        fetch { [weak self] r in
            guard let self, let r, r.build > self.currentBuild,
                  UserDefaults.standard.integer(forKey: "updateSkipBuild") != r.build else { return }
            self.offer(r, manual: false)
        }
    }

    /// Menu: always reports a result.
    func checkNow() {
        guard feed != nil, teamID != nil else {
            alert("Updates aren't available in this build", "This copy of mdv was built locally without a release feed."); return
        }
        fetch { [weak self] r in
            guard let self else { return }
            guard let r else { self.alert("Couldn't check for updates", "Check your connection and try again."); return }
            if r.build > self.currentBuild { self.offer(r, manual: true) }
            else { self.alert("You're up to date", "mdv \(self.currentVersion) is the latest version.") }
        }
    }

    /// CLI: `mdv --check-update` prints the feed result and exits.
    func checkFromCommandLine() {
        guard let feed else { print("no feed configured"); exit(0) }
        print("feed: \(feed)\ninstalled: \(currentVersion) (build \(currentBuild))")
        let sem = DispatchSemaphore(value: 0)
        fetchRaw { r in
            if let r { print("latest: \(r.version) (build \(r.build)) \(r.build > self.currentBuild ? "→ UPDATE AVAILABLE" : "→ up to date")\nurl: \(r.url)") }
            else { print("latest: no release found (feed unreachable or not published yet)") }
            sem.signal()
        }
        sem.wait(); exit(0)
    }

    // MARK: - feed

    private func fetch(_ done: @escaping (ReleaseInfo?) -> Void) {
        fetchRaw { r in DispatchQueue.main.async { done(r) } }
    }
    private func fetchRaw(_ done: @escaping (ReleaseInfo?) -> Void) {
        guard let feed, let u = URL(string: feed) else { return done(nil) }
        var req = URLRequest(url: u)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            guard let data, (resp as? HTTPURLResponse)?.statusCode == 200 else { return done(nil) }
            done(try? JSONDecoder().decode(ReleaseInfo.self, from: data))
        }.resume()
    }

    // MARK: - prompt + install

    private func offer(_ r: ReleaseInfo, manual: Bool) {
        let a = NSAlert()
        a.messageText = "mdv \(r.version) is available"
        a.informativeText = "You have \(currentVersion)." + (r.notes.map { "\n\n\($0)" } ?? "")
        a.addButton(withTitle: "Update Now")
        a.addButton(withTitle: "Later")
        if !manual { a.addButton(withTitle: "Skip This Version") }
        switch a.runModal() {
        case .alertFirstButtonReturn: install(r)
        case .alertThirdButtonReturn: UserDefaults.standard.set(r.build, forKey: "updateSkipBuild")
        default: break
        }
    }

    private func install(_ r: ReleaseInfo) {
        guard !busy, let u = URL(string: r.url) else { return }
        busy = true
        let progress = ProgressPanel("Updating mdv…")
        progress.show()
        let keep = FileManager.default.temporaryDirectory.appendingPathComponent("mdv-\(r.build).zip")
        URLSession.shared.downloadTask(with: u) { tmp, resp, err in
            var zip: URL?
            if let tmp, (resp as? HTTPURLResponse)?.statusCode == 200 {
                try? FileManager.default.removeItem(at: keep)
                if (try? FileManager.default.moveItem(at: tmp, to: keep)) != nil { zip = keep }
            }
            DispatchQueue.main.async {
                progress.close(); self.busy = false
                guard let zip else { self.fail("Download failed", err?.localizedDescription ?? "The server didn't return the update."); return }
                do { try self.swap(zip: zip, expecting: r) }
                catch { self.fail("Update failed", error.localizedDescription) }
            }
        }.resume()
    }

    private func swap(zip: URL, expecting r: ReleaseInfo) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("mdv-update-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work); try? fm.removeItem(at: zip) }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, work.path]
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError("Couldn't unpack the download.") }

        let newApp = work.appendingPathComponent("mdv.app")
        guard fm.fileExists(atPath: newApp.path) else { throw UpdateError("The download didn't contain mdv.app.") }
        guard verifySignature(newApp) else { throw UpdateError("The downloaded app isn't signed by the mdv developer. Nothing was changed.") }
        let newBuild = Int((Bundle(url: newApp)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "") ?? 0
        guard newBuild >= r.build else { throw UpdateError("The download is older than expected. Nothing was changed.") }

        let current = Bundle.main.bundleURL
        let docs = NSDocumentController.shared.documents.compactMap(\.fileURL)
        var trashed: NSURL?
        try fm.trashItem(at: current, resultingItemURL: &trashed)
        do { try fm.moveItem(at: newApp, to: current) }
        catch {
            if let t = trashed as URL? { try? fm.moveItem(at: t, to: current) }
            throw UpdateError("Couldn't replace the app at \(current.path). \(error.localizedDescription)")
        }

        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        let relaunched: (NSRunningApplication?, Error?) -> Void = { _, _ in DispatchQueue.main.async { NSApp.terminate(nil) } }
        if docs.isEmpty { NSWorkspace.shared.openApplication(at: current, configuration: cfg, completionHandler: relaunched) }
        else { NSWorkspace.shared.open(docs, withApplicationAt: current, configuration: cfg, completionHandler: relaunched) }
    }

    /// Valid Apple-issued signature, same bundle id, same Team ID as this build.
    private func verifySignature(_ app: URL) -> Bool {
        guard let teamID, let bundleID = Bundle.main.bundleIdentifier else { return false }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return false }
        let reqText = "anchor apple generic and identifier \"\(bundleID)\" and certificate leaf[subject.OU] = \"\(teamID)\"" as CFString
        var req: SecRequirement?
        guard SecRequirementCreateWithString(reqText, [], &req) == errSecSuccess, let req else { return false }
        return SecStaticCodeCheckValidityWithErrors(code, [], req, nil) == errSecSuccess
    }

    // MARK: - alerts

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal()
    }
    private func fail(_ title: String, _ text: String) {
        let a = NSAlert(); a.alertStyle = .warning; a.messageText = title; a.informativeText = text
        a.addButton(withTitle: "OK")
        if let page, let u = URL(string: page) {
            a.addButton(withTitle: "Download Manually")
            if a.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(u) }
        } else { a.runModal() }
    }
}

struct UpdateError: LocalizedError {
    let msg: String
    init(_ m: String) { msg = m }
    var errorDescription: String? { msg }
}

final class ProgressPanel {
    private let panel: NSPanel
    init(_ title: String) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 84), styleMask: [.titled], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = ""
        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: 20, y: 46, width: 280, height: 20)
        let bar = NSProgressIndicator(frame: NSRect(x: 20, y: 20, width: 280, height: 16))
        bar.isIndeterminate = true; bar.startAnimation(nil)
        panel.contentView?.addSubview(label); panel.contentView?.addSubview(bar)
        panel.center()
    }
    func show() { panel.makeKeyAndOrderFront(nil) }
    func close() { panel.close() }
}
