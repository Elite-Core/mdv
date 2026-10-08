import AppKit

/// The reading pane: a native text view with a centered column, plus the empty state and drop overlay.
final class ReaderViewController: NSViewController, NSTextViewDelegate {
    let scroll = NSScrollView()
    let textView: NSTextView
    let dropOverlay = DropOverlayView()
    private let empty = NSStackView()
    private let renderer = MarkdownRenderer()
    private let layout = MarkdownLayoutManager()
    private var headings: [OutlineEntry] = []
    private var lastHeading: Int? = -1

    var onHeadingChange: ((Int?) -> Void)?
    var onOpenFile: (() -> Void)?
    var onOpenRelative: ((String, String?) -> Void)?

    init() {
        let storage = NSTextStorage()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude))
        layout.addTextContainer(container)
        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), textContainer: container)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let v = NSView()
        v.wantsLayer = true

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.linkTextAttributes = [.foregroundColor: NSColor.controlAccentColor, .cursor: NSCursor.pointingHand]
        textView.delegate = self
        textView.unregisterDraggedTypes()              // drops go to the window
        textView.textContainerInset = NSSize(width: 40, height: 36)

        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.automaticallyAdjustsContentInsets = true   // content scrolls under the toolbar, like Notes/Mail
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        v.addSubview(scroll)

        // empty state
        let icon = NSImageView(image: NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 40, weight: .light))!)
        icon.contentTintColor = .tertiaryLabelColor
        let title = NSTextField(labelWithString: "Open a markdown file")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        let button = NSButton(title: "Open File…", target: self, action: #selector(openFile(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.keyEquivalent = "\r"
        let hint = NSTextField(labelWithString: "or drop one here")
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = .tertiaryLabelColor
        empty.orientation = .vertical
        empty.alignment = .centerX
        empty.spacing = 8
        empty.setViews([icon, title, button, hint], in: .center)
        empty.setCustomSpacing(14, after: title)
        empty.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(empty)

        dropOverlay.translatesAutoresizingMaskIntoConstraints = false
        dropOverlay.isHidden = true
        v.addSubview(dropOverlay)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: v.topAnchor), scroll.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: v.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            empty.centerXAnchor.constraint(equalTo: v.centerXAnchor), empty.centerYAnchor.constraint(equalTo: v.safeAreaLayoutGuide.centerYAnchor, constant: -24),
            dropOverlay.topAnchor.constraint(equalTo: v.topAnchor), dropOverlay.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            dropOverlay.leadingAnchor.constraint(equalTo: v.leadingAnchor), dropOverlay.trailingAnchor.constraint(equalTo: v.trailingAnchor),
        ])
        view = v
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let w = scroll.contentSize.width
        let column = min(760 * renderer.zoom, w - 48)
        let side = max(24, (w - column) / 2)
        if abs(textView.textContainerInset.width - side) > 0.5 {
            textView.textContainerInset = NSSize(width: side, height: 36)
        }
    }

    // MARK: content

    private var topInset: CGFloat { scroll.contentInsets.top }

    func showEmpty(_ on: Bool) {
        empty.isHidden = !on
        scroll.isHidden = on
        if on { textView.string = ""; headings = [] }
    }

    @discardableResult
    func render(markdown: String, baseURL: URL, zoom: CGFloat, keepScroll: Bool) -> [OutlineEntry] {
        renderer.zoom = zoom
        renderer.baseURL = baseURL
        layout.zoom = zoom
        let origin = scroll.contentView.bounds.origin
        let (text, outline) = renderer.render(markdown)
        headings = outline
        textView.textStorage?.setAttributedString(text)
        showEmpty(false)
        if let lm = textView.layoutManager, let tc = textView.textContainer { lm.ensureLayout(for: tc) }
        if keepScroll { scroll.contentView.scroll(to: origin) } else { scroll.contentView.scroll(to: NSPoint(x: 0, y: -topInset)) }
        scroll.reflectScrolledClipView(scroll.contentView)
        lastHeading = -1
        scrolled()
        return outline
    }

    private func rect(forCharacterAt loc: Int) -> NSRect {
        guard let lm = textView.layoutManager, let tc = textView.textContainer, loc < (textView.textStorage?.length ?? 0) else { return .zero }
        let g = lm.glyphRange(forCharacterRange: NSRange(location: loc, length: 1), actualCharacterRange: nil)
        var r = lm.boundingRect(forGlyphRange: g, in: tc)
        r.origin.y += textView.textContainerInset.height
        return r
    }

    func jump(toHeading i: Int) {
        guard headings.indices.contains(i) else { return }
        let y = max(-topInset, rect(forCharacterAt: headings[i].location).minY - 14 - topInset)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    func jump(toSlug slug: String) {
        if let i = headings.firstIndex(where: { $0.slug == slug }) { jump(toHeading: i) }
    }

    @objc private func scrolled() {
        guard !headings.isEmpty else { if lastHeading != nil { lastHeading = nil; onHeadingChange?(nil) }; return }
        let top = scroll.contentView.bounds.minY + topInset
        var idx: Int? = nil
        for (i, h) in headings.enumerated() {
            if rect(forCharacterAt: h.location).minY <= top + 20 { idx = i } else { break }
        }
        if idx != lastHeading { lastHeading = idx; onHeadingChange?(idx) }
    }

    @objc func openFile(_ s: Any?) { onOpenFile?() }

    // MARK: links

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let url: URL? = (link as? URL) ?? (link as? String).flatMap { URL(string: $0) }
        guard let url else { return false }
        if url.scheme == nil {
            let path = url.path.removingPercentEncoding ?? url.path
            if path.isEmpty, let f = url.fragment { jump(toSlug: f); return true }
            if ["md", "markdown", "mdown", "mdx", "txt"].contains((path as NSString).pathExtension.lowercased()) {
                let abs = path.hasPrefix("/") ? path : (renderer.baseURL ?? URL(fileURLWithPath: "/")).appendingPathComponent(path).path
                onOpenRelative?(abs, url.fragment); return true
            }
            return false
        }
        NSWorkspace.shared.open(url)
        return true
    }
}

/// Dashed accent frame shown while a markdown file is dragged over the window.
final class DropOverlayView: NSView {
    private let label = NSTextField(labelWithString: "Drop to open")
    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .controlAccentColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: centerXAnchor), label.centerYAnchor.constraint(equalTo: centerYAnchor)])
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
        bounds.fill()
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 12, dy: 12), xRadius: 12, yRadius: 12)
        p.lineWidth = 2
        p.setLineDash([7, 5], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        p.stroke()
    }
}
