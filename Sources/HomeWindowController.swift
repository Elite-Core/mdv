import Cocoa
import WebKit

/// WKWebView that accepts markdown file drops natively and (optionally) lets the window be dragged by its background.
final class DropWebView: WKWebView {
    var movesWindow = false
    var onDrop: (([URL]) -> Void)?
    var onDragState: ((Bool) -> Void)?
    static let exts: Set<String> = ["md", "markdown", "mdown", "mdx", "txt"]

    override var mouseDownCanMoveWindow: Bool { movesWindow }

    func enableDrops() { registerForDraggedTypes([.fileURL]) }

    private func fileURLs(_ info: NSDraggingInfo) -> [URL] {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let all = (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL]) ?? []
        return all.filter { Self.exts.contains($0.pathExtension.lowercased()) }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !fileURLs(sender).isEmpty { onDragState?(true); return .copy }
        return super.draggingEntered(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(sender).isEmpty ? super.draggingUpdated(sender) : .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { onDragState?(false); super.draggingExited(sender) }
    override func draggingEnded(_ sender: NSDraggingInfo) { onDragState?(false); super.draggingEnded(sender) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !fileURLs(sender).isEmpty || super.prepareForDragOperation(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender)
        if urls.isEmpty { return super.performDragOperation(sender) }
        onDragState?(false); onDrop?(urls)
        return true
    }
}

/// The front door: shown when the app launches with nothing to open, and when the last document closes.
final class HomeWindowController: NSWindowController, WKNavigationDelegate, WKScriptMessageHandler {
    static let shared = HomeWindowController()
    private var web: DropWebView!
    private var loaded = false

    private init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 470),
                         styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        super.init(window: w)
        w.title = "mdv"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.tabbingMode = .disallowed
        w.standardWindowButton(.zoomButton)?.isHidden = true
        w.center()
        w.setFrameAutosaveName("mdv.home")

        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(WeakScriptHandler(self), name: "home")
        web = DropWebView(frame: w.contentView!.bounds, configuration: cfg)
        web.autoresizingMask = [.width, .height]
        web.movesWindow = true
        web.enableDrops()
        web.navigationDelegate = self
        web.underPageBackgroundColor = .windowBackgroundColor
        web.onDrop = { HomeWindowController.open($0) }
        web.onDragState = { [weak self] on in self?.web.evaluateJavaScript("home.drag(\(on))", completionHandler: nil) }
        w.contentView?.addSubview(web)
        if let html = Bundle.main.url(forResource: "home", withExtension: "html") {
            web.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        }
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func hide() { window?.orderOut(nil) }

    func refresh() {
        guard loaded else { return }
        let fm = FileManager.default
        let recent = NSDocumentController.shared.recentDocumentURLs.prefix(8).map {
            ["path": $0.path, "name": $0.lastPathComponent, "dir": prettyPath($0.deletingLastPathComponent().path)]
        }
        let payload: [String: Any] = [
            "recent": Array(recent),
            "claude": fm.fileExists(atPath: AppDelegate.claudeDir.path),
            "skill": fm.fileExists(atPath: AppDelegate.skillDest.path),
            "version": Updater.shared.currentVersion,
        ]
        guard let d = try? JSONSerialization.data(withJSONObject: payload), let j = String(data: d, encoding: .utf8) else { return }
        web.evaluateJavaScript("home.set(\(j))", completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true; refresh() }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated, let u = navigationAction.request.url {
            NSWorkspace.shared.open(u); decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let b = message.body as? [String: Any], let t = b["type"] as? String else { return }
        switch t {
        case "open": NSDocumentController.shared.openDocument(nil)
        case "recent": if let p = b["path"] as? String { HomeWindowController.open([URL(fileURLWithPath: p)]) }
        case "skill": (NSApp.delegate as? AppDelegate)?.installSkillMenu(nil); refresh()
        case "updates": Updater.shared.checkNow()
        default: break
        }
    }

    static func open(_ urls: [URL]) {
        for u in urls {
            NSDocumentController.shared.openDocument(withContentsOf: u, display: true) { _, _, e in
                if let e { NSApp.presentError(e) }
            }
        }
    }
}
