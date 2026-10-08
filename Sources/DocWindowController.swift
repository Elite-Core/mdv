import Cocoa
import WebKit
import UniformTypeIdentifiers

/// Serves local files (images referenced by the markdown) to the web view as mdv:///abs/path.
final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let fileURL = URL(fileURLWithPath: url.path)
        guard let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)); return
        }
        let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
        task.didReceive(data)
        task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ u: WKUserContentController, didReceive m: WKScriptMessage) { target?.userContentController(u, didReceive: m) }
}

final class DocWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    private enum ID {
        static let sidebar = NSToolbarItem.Identifier("mdv.sidebar")
        static let status = NSToolbarItem.Identifier("mdv.status")
        static let appearance = NSToolbarItem.Identifier("mdv.appearance")
    }

    private var web: DropWebView!
    private var loaded = false
    private var pendingHash: String?
    private let statusLabel = NSTextField(labelWithString: "")
    private var statusTimer: Timer?
    private var doc: MarkdownDocument? { document as? MarkdownDocument }

    convenience init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 800),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        self.init(window: w)
        w.delegate = self
        w.minSize = NSSize(width: 520, height: 360)
        w.toolbarStyle = .unified
        w.tabbingMode = .preferred
        w.center()
        shouldCascadeWindows = true
        windowFrameAutosaveName = "mdv.document"

        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(LocalFileSchemeHandler(), forURLScheme: "mdv")
        cfg.userContentController.add(WeakScriptHandler(self), name: "mdv")
        cfg.preferences.setValue(true, forKey: "developerExtrasEnabled")
        web = DropWebView(frame: w.contentView!.bounds, configuration: cfg)
        web.autoresizingMask = [.width, .height]
        web.enableDrops()
        web.onDrop = { HomeWindowController.open($0) }
        web.navigationDelegate = self
        web.allowsMagnification = true
        web.underPageBackgroundColor = .windowBackgroundColor
        w.contentView?.addSubview(web)

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        let tb = NSToolbar(identifier: "mdv.toolbar")
        tb.delegate = self
        tb.displayMode = .iconOnly
        tb.allowsUserCustomization = false
        w.toolbar = tb

        statusTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.updateStatus() }

        if let html = Bundle.main.url(forResource: "viewer", withExtension: "html") {
            web.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        }
    }

    override func synchronizeWindowTitleWithDocumentName() {
        super.synchronizeWindowTitleWithDocumentName()
        if let u = doc?.fileURL { window?.subtitle = prettyPath(u.deletingLastPathComponent().path) }
    }

    func windowWillClose(_ n: Notification) { statusTimer?.invalidate(); statusTimer = nil }

    // MARK: - Rendering

    func render(changed: Bool = false) {
        guard loaded, let d = doc, let u = d.fileURL else { return }
        var payload: [String: Any] = [
            "name": u.lastPathComponent,
            "dir": u.deletingLastPathComponent().path,
            "content": d.text,
            "mtime": d.mtime.timeIntervalSince1970 * 1000,
            "changed": changed,
        ]
        if let s = UserDefaults.standard.object(forKey: "sidebar") as? Bool { payload["sidebar"] = s }
        if let h = pendingHash { payload["hash"] = h; pendingHash = nil }
        call("mdv.set", payload)
        pushRecent()
        updateStatus()
    }

    private func call(_ fn: String, _ arg: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: arg, options: [.fragmentsAllowed]),
              let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("\(fn)(\(json))", completionHandler: nil)
    }

    private func pushRecent() {
        let list = NSDocumentController.shared.recentDocumentURLs.map {
            ["path": $0.path, "name": $0.lastPathComponent, "dir": prettyPath($0.deletingLastPathComponent().path)]
        }
        call("mdv.setRecent", list)
    }

    private func updateStatus() {
        guard let d = doc else { return }
        let s = NSMutableAttributedString(string: "● ", attributes: [
            .foregroundColor: NSColor.systemGreen, .font: NSFont.systemFont(ofSize: 8), .baselineOffset: 1.5])
        s.append(NSAttributedString(string: "updated \(ago(d.mtime))", attributes: [
            .foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 11)]))
        statusLabel.attributedStringValue = s
        statusLabel.toolTip = "Watching \(d.fileURL?.path ?? "") for changes"
    }

    private func ago(_ t: Date) -> String {
        let s = Int(Date().timeIntervalSince(t))
        if s < 45 { return "just now" }
        let m = s / 60; if m < 60 { return "\(m)m ago" }
        let h = m / 60; if h < 24 { return "\(h)h ago" }
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: t)
    }

    func scroll(to hash: String) {
        if loaded { call("mdv.jump", hash) } else { pendingHash = hash }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true; render() }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated, let u = navigationAction.request.url {
            NSWorkspace.shared.open(u)
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }

    // MARK: - Messages from the page

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let b = message.body as? [String: Any], let t = b["type"] as? String else { return }
        switch t {
        case "open":
            guard let p = b["path"] as? String else { return }
            let u = URL(fileURLWithPath: p).standardizedFileURL
            let hash = b["hash"] as? String
            NSDocumentController.shared.openDocument(withContentsOf: u, display: true) { d, _, err in
                if let err = err { NSApp.presentError(err); return }
                if let hash = hash, !hash.isEmpty { (d?.windowControllers.first as? DocWindowController)?.scroll(to: hash) }
            }
        case "sidebar":
            if let v = b["visible"] as? Bool { UserDefaults.standard.set(v, forKey: "sidebar") }
        case "find":
            guard let q = b["q"] as? String, !q.isEmpty else { return }
            let c = WKFindConfiguration()
            c.caseSensitive = false; c.wraps = true
            c.backwards = (b["backwards"] as? Bool) ?? false
            web.find(q, configuration: c) { [weak self] r in self?.call("mdv.findResult", r.matchFound) }
        default: break
        }
    }

    // MARK: - Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, ID.status, .space, ID.sidebar, ID.appearance]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case ID.sidebar: return symbolItem(id, "sidebar.left", "Toggle Sidebar", #selector(toggleOutline(_:)))
        case ID.appearance: return symbolItem(id, "circle.lefthalf.filled", "Light / Dark", #selector(toggleAppearance(_:)))
        case ID.status:
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = statusLabel
            item.label = "Status"
            return item
        default: return nil
        }
    }

    private func symbolItem(_ id: NSToolbarItem.Identifier, _ symbol: String, _ label: String, _ action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.label = label; item.toolTip = label
        item.target = self; item.action = action
        item.isBordered = true
        return item
    }

    // MARK: - Actions

    @objc func toggleOutline(_ s: Any?) { web.evaluateJavaScript("mdv.toggleSidebar()", completionHandler: nil) }

    @objc func toggleAppearance(_ s: Any?) {
        let dark = window?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        AppDelegate.applyAppearance(dark ? "light" : "dark")
    }

    @objc func reload(_ s: Any?) { doc?.reloadFromDisk(); render() }

    @objc func revealInFinder(_ s: Any?) {
        if let u = doc?.fileURL { NSWorkspace.shared.activateFileViewerSelecting([u]) }
    }

    @objc func printDoc(_ s: Any?) {
        let info = NSPrintInfo.shared
        info.topMargin = 40; info.bottomMargin = 40; info.leftMargin = 40; info.rightMargin = 40
        let op = web.printOperation(with: info)
        op.view?.frame = NSRect(origin: .zero, size: info.paperSize)
        op.showsPrintPanel = true; op.showsProgressPanel = true
        if let w = window { op.runModal(for: w, delegate: nil, didRun: nil, contextInfo: nil) }
    }

    @objc func focusFind(_ s: Any?) {
        window?.makeFirstResponder(web)
        web.evaluateJavaScript("mdv.find()", completionHandler: nil)
    }

    @objc func zoomIn(_ s: Any?) { web.pageZoom = min(web.pageZoom + 0.1, 3) }
    @objc func zoomOut(_ s: Any?) { web.pageZoom = max(web.pageZoom - 0.1, 0.5) }
    @objc func actualSize(_ s: Any?) { web.pageZoom = 1 }
}
