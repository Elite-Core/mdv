import Cocoa

final class DocWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSToolbarItemValidation, NSDraggingDestination {
    /// The home window: a viewer with no document. Shown on launch with nothing to open and when the last document closes.
    static let home = DocWindowController(home: true)
    private(set) var isHome = false

    private enum ID {
        static let status = NSToolbarItem.Identifier("mdv.status")
        static let open = NSToolbarItem.Identifier("mdv.open")
        static let copy = NSToolbarItem.Identifier("mdv.copy")
        static let appearance = NSToolbarItem.Identifier("mdv.appearance")
    }

    let sidebar = SidebarViewController()
    let reader = ReaderViewController()
    private let split = NSSplitViewController()
    private let statusLabel = NSTextField(labelWithString: "")
    private var statusTimer: Timer?
    private var pendingHash: String?
    private var rendered = false
    private var zoom: CGFloat = 1
    private var doc: MarkdownDocument? { document as? MarkdownDocument }

    convenience init(home: Bool) {
        // Open big: ~72% of the screen's width and ~85% of its height, like a generous Notes window.
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: min(1400, (screen.width * 0.72).rounded()), height: min(1000, (screen.height * 0.85).rounded()))
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        self.init(window: w)
        isHome = home
        NSLog("[mdv] DocWindowController init home=%d", home ? 1 : 0)
        w.delegate = self
        w.minSize = NSSize(width: 560, height: 380)
        w.toolbarStyle = .unified
        w.tabbingMode = home ? .disallowed : .preferred
        w.isRestorable = false          // launch always lands on Home, never on last session's windows
        if home { w.title = "mdv"; w.isReleasedWhenClosed = false }
        w.center()
        shouldCascadeWindows = true
        windowFrameAutosaveName = "mdv.document"

        let side = NSSplitViewItem(sidebarWithViewController: sidebar)
        side.minimumThickness = 200
        side.maximumThickness = 340
        side.canCollapse = true
        let main = NSSplitViewItem(viewController: reader)
        main.minimumThickness = 380
        split.addSplitViewItem(side)
        split.addSplitViewItem(main)
        side.isCollapsed = false
        split.splitView.autosaveName = "mdv.sidebar"
        w.contentViewController = split
        if sidebar.view.frame.width < 200 { split.splitView.setPosition(240, ofDividerAt: 0) }

        w.registerForDraggedTypes([.fileURL])

        let tb = NSToolbar(identifier: "mdv.toolbar")
        tb.delegate = self
        tb.displayMode = .iconOnly
        tb.allowsUserCustomization = false
        w.toolbar = tb

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.updateStatus() }

        sidebar.onJump = { [weak self] i in self?.reader.jump(toHeading: i) }
        sidebar.onOpenRecent = { DocWindowController.open([URL(fileURLWithPath: $0)]) }
        sidebar.onInstallSkill = { [weak self] in
            (NSApp.delegate as? AppDelegate)?.installSkillMenu(nil)
            self?.refreshSkill()
        }
        reader.onHeadingChange = { [weak self] i in self?.sidebar.highlight(heading: i) }
        reader.onOpenFile = { NSDocumentController.shared.openDocument(nil) }
        reader.onOpenRelative = { [weak self] path, hash in self?.openRelative(path, hash: hash) }

        if home { reader.showEmpty(true); sidebar.showHome() }
        refreshSkill()
        pushRecent()
    }

    override func synchronizeWindowTitleWithDocumentName() {
        super.synchronizeWindowTitleWithDocumentName()
        if let u = doc?.fileURL { window?.subtitle = prettyPath(u.deletingLastPathComponent().path) }
    }

    override func showWindow(_ sender: Any?) {
        if doc != nil && !rendered { render() }
        super.showWindow(sender)
        if doc != nil { NSLog("[mdv] render loaded=1 doc=1 winVisible=%d", (window?.isVisible ?? false) ? 1 : 0) }
    }

    func windowWillClose(_ n: Notification) { if !isHome { statusTimer?.invalidate(); statusTimer = nil } }

    // MARK: - Home

    func show() {
        reader.showEmpty(true)
        sidebar.showHome()
        refreshSkill()
        pushRecent()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func hide() { window?.orderOut(nil) }

    static func open(_ urls: [URL]) {
        for u in urls {
            NSDocumentController.shared.openDocument(withContentsOf: u, display: true) { _, _, e in
                if let e { NSApp.presentError(e) }
            }
        }
    }

    private func openRelative(_ path: String, hash: String?) {
        let u = URL(fileURLWithPath: path).standardizedFileURL
        NSDocumentController.shared.openDocument(withContentsOf: u, display: true) { d, _, err in
            if let err { NSApp.presentError(err); return }
            if let hash, !hash.isEmpty { (d?.windowControllers.first as? DocWindowController)?.scroll(to: hash) }
        }
    }

    // MARK: - Rendering

    func render(changed: Bool = false) {
        guard let d = doc, let u = d.fileURL else { return }
        let outline = reader.render(markdown: d.text, baseURL: u.deletingLastPathComponent(), zoom: zoom, keepScroll: changed || rendered)
        sidebar.setOutline(outline)
        rendered = true
        if let h = pendingHash { pendingHash = nil; reader.jump(toSlug: h) }
        pushRecent()
        updateStatus()
        if changed { NSLog("[mdv] render loaded=1 doc=1 winVisible=%d", (window?.isVisible ?? false) ? 1 : 0) }
    }

    private func pushRecent() {
        sidebar.setRecent(NSDocumentController.shared.recentDocumentURLs.prefix(12).map {
            RecentItem(path: $0.path, name: $0.lastPathComponent, dir: prettyPath($0.deletingLastPathComponent().path))
        })
    }

    private func refreshSkill() {
        let fm = FileManager.default
        sidebar.setSkill(claudeInstalled: fm.fileExists(atPath: AppDelegate.claudeDir.path),
                         skillInstalled: fm.fileExists(atPath: AppDelegate.skillDest.path))
    }

    private func updateStatus() {
        guard let d = doc else { statusLabel.stringValue = ""; return }
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
        if rendered { reader.jump(toSlug: hash) } else { pendingHash = hash }
    }

    // MARK: - Drops (the window forwards these from anywhere in its content)

    private func markdownURLs(_ info: NSDraggingInfo) -> [URL] {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let all = (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL]) ?? []
        return all.filter { ["md", "markdown", "mdown", "mdx", "txt"].contains($0.pathExtension.lowercased()) }
    }
    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let ok = !markdownURLs(sender).isEmpty
        reader.dropOverlay.isHidden = !ok
        return ok ? .copy : []
    }
    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { markdownURLs(sender).isEmpty ? [] : .copy }
    func draggingExited(_ sender: NSDraggingInfo?) { reader.dropOverlay.isHidden = true }
    func draggingEnded(_ sender: NSDraggingInfo) { reader.dropOverlay.isHidden = true }
    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        reader.dropOverlay.isHidden = true
        let urls = markdownURLs(sender)
        guard !urls.isEmpty else { return false }
        DocWindowController.open(urls)
        return true
    }

    // MARK: - Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, ID.status, .space, ID.open, ID.copy, .space, ID.appearance]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case ID.open: return symbolItem(id, "folder", "Open File", #selector(openFile(_:)))
        case ID.copy: return symbolItem(id, "doc.on.doc", "Copy Markdown", #selector(copyMarkdown(_:)))
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

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        item.itemIdentifier == ID.copy ? doc != nil : true
    }

    // MARK: - Actions

    @objc func openFile(_ s: Any?) { NSDocumentController.shared.openDocument(nil) }

    @objc func copyMarkdown(_ s: Any?) {
        guard let d = doc else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(d.text, forType: .string)
        statusLabel.stringValue = "Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in self?.updateStatus() }
    }

    @objc func toggleAppearance(_ s: Any?) {
        let dark = window?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        AppDelegate.applyAppearance(dark ? "light" : "dark")
    }

    @objc func reload(_ s: Any?) { doc?.reloadFromDisk(); render(changed: true) }

    @objc func revealInFinder(_ s: Any?) {
        if let u = doc?.fileURL { NSWorkspace.shared.activateFileViewerSelecting([u]) }
    }

    @objc func printDoc(_ s: Any?) {
        guard let w = window, doc != nil else { return }
        let info = NSPrintInfo.shared
        info.topMargin = 48; info.bottomMargin = 48; info.leftMargin = 54; info.rightMargin = 54
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        let op = NSPrintOperation(view: reader.textView, printInfo: info)
        op.showsPrintPanel = true; op.showsProgressPanel = true
        op.runModal(for: w, delegate: nil, didRun: nil, contextInfo: nil)
    }

    @objc func zoomIn(_ s: Any?) { zoom = min(zoom + 0.1, 2.2); render(changed: true) }
    @objc func zoomOut(_ s: Any?) { zoom = max(zoom - 0.1, 0.7); render(changed: true) }
    @objc func actualSize(_ s: Any?) { zoom = 1; render(changed: true) }
}
