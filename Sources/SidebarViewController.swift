import AppKit

struct RecentItem { let path: String; let name: String; let dir: String }

/// Native source list: Outline (headings of the open file) and Recent, with the Claude skill status pinned at the bottom.
final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private final class Row: NSObject {
        enum Kind { case group(String), heading(Int, OutlineEntry), recent(RecentItem) }
        let kind: Kind
        var children: [Row] = []
        init(_ k: Kind) { kind = k }
    }

    private let outlineView = NSOutlineView()
    private let scroll = NSScrollView()
    private let footer = NSStackView()
    private let skillIcon = NSImageView()
    private let skillLabel = NSTextField(labelWithString: "Claude Code skill installed")
    private let installButton = NSButton(title: "Install Claude Code skill", target: nil, action: nil)

    private var outlineGroup = Row(.group("Outline"))
    private var recentGroup = Row(.group("Recent"))
    private var showOutline = true
    private var suppressSelection = false

    private var currentPath: String?

    var onJump: ((Int) -> Void)?
    var onOpenRecent: ((String) -> Void)?
    var onClearRecent: (() -> Void)?
    var onInstallSkill: (() -> Void)?

    override func loadView() {
        let v = NSView()

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        col.resizingMask = .autoresizingMask
        outlineView.addTableColumn(col)
        outlineView.outlineTableColumn = col
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.floatsGroupRows = false
        outlineView.indentationPerLevel = 0
        outlineView.rowSizeStyle = .default
        outlineView.allowsEmptySelection = true
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.unregisterDraggedTypes()
        outlineView.target = self
        outlineView.action = #selector(rowClicked(_:))

        scroll.documentView = outlineView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(scroll)

        // footer
        let line = NSBox(); line.boxType = .separator; line.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(line)
        skillIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        skillIcon.contentTintColor = .systemGreen
        skillLabel.font = .systemFont(ofSize: 12)
        skillLabel.textColor = .secondaryLabelColor
        installButton.isBordered = false
        installButton.target = self
        installButton.action = #selector(installSkill(_:))
        installButton.attributedTitle = NSAttributedString(string: "Install Claude Code skill", attributes: [.foregroundColor: NSColor.controlAccentColor, .font: NSFont.systemFont(ofSize: 12)])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 6
        footer.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 12, right: 12)
        footer.setViews([skillIcon, skillLabel, installButton], in: .leading)
        footer.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(footer)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: v.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: v.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: line.topAnchor),
            line.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12), line.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
            line.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: v.leadingAnchor), footer.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
        view = v
        reload()
    }

    // MARK: inputs

    func setOutline(_ entries: [OutlineEntry]) {
        let multiH1 = entries.filter { $0.level == 1 }.count > 1
        let base = multiH1 ? 1 : 2
        outlineGroup.children = entries.filter { multiH1 || $0.level != 1 }.enumerated().map { i, e in
            Row(.heading(max(0, e.level - base), e))
        }
        // keep the original index so jumps hit the right heading
        indexMap = entries.enumerated().filter { multiH1 || $0.element.level != 1 }.map { $0.offset }
        showOutline = true
        reload()
    }
    private var indexMap: [Int] = []

    func showHome() { showOutline = false; outlineGroup.children = []; reload() }

    func setRecent(_ items: [RecentItem], current: String?) {
        currentPath = current
        recentGroup.children = items.map { Row(.recent($0)) }
        reload()
    }

    func setSkill(claudeInstalled: Bool, skillInstalled: Bool) {
        footer.isHidden = !claudeInstalled
        skillIcon.isHidden = !skillInstalled
        skillLabel.isHidden = !skillInstalled
        installButton.isHidden = skillInstalled
    }

    func highlight(heading i: Int?) {
        suppressSelection = true
        defer { suppressSelection = false }
        guard let i, let pos = indexMap.firstIndex(of: i), pos < outlineGroup.children.count else {
            outlineView.deselectAll(nil); return
        }
        let row = outlineView.row(forItem: outlineGroup.children[pos])
        guard row >= 0 else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
    }

    private func reload() {
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true)
    }

    // MARK: data source

    private var groups: [Row] { showOutline ? [outlineGroup, recentGroup] : [recentGroup] }

    func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let r = item as? Row else { return groups.count }
        return r.children.count
    }
    func outlineView(_ ov: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let r = item as? Row else { return groups[index] }
        return r.children[index]
    }
    func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let r = item as? Row, case .group = r.kind { return true }
        return false
    }
    func outlineView(_ ov: NSOutlineView, isGroupItem item: Any) -> Bool {
        if let r = item as? Row, case .group = r.kind { return true }
        return false
    }
    func outlineView(_ ov: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        if let r = item as? Row, case .group = r.kind { return false }
        return true
    }
    func outlineView(_ ov: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        if let r = item as? Row, case .recent = r.kind { return 40 }
        return 24
    }

    func outlineView(_ ov: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let r = item as? Row else { return nil }
        switch r.kind {
        case .group(let name):
            let cell = NSTableCellView()
            let tf = NSTextField(labelWithString: name.uppercased())
            tf.font = .systemFont(ofSize: 11, weight: .semibold)
            tf.textColor = .tertiaryLabelColor
            tf.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(tf); cell.textField = tf
            NSLayoutConstraint.activate([tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4), tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
            if r === recentGroup, !recentGroup.children.isEmpty {
                let clear = NSButton(title: "Clear", target: self, action: #selector(clearRecents(_:)))
                clear.isBordered = false
                clear.attributedTitle = NSAttributedString(string: "Clear", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.tertiaryLabelColor])
                clear.toolTip = "Clear recent files"
                clear.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(clear)
                NSLayoutConstraint.activate([clear.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6), clear.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
            }
            return cell
        case .heading(let depth, let e):
            let cell = NSTableCellView()
            let tf = NSTextField(labelWithString: e.title)
            tf.font = .systemFont(ofSize: 13)
            tf.textColor = depth == 0 ? .labelColor : .secondaryLabelColor
            tf.lineBreakMode = .byTruncatingTail
            tf.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(tf); cell.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4 + CGFloat(depth) * 14),
                tf.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
            return cell
        case .recent(let item):
            let cell = NSTableCellView()
            let isCurrent = item.path == currentPath
            let icon = NSImageView(image: NSImage(systemSymbolName: isCurrent ? "doc.text.fill" : "doc.text", accessibilityDescription: nil)!
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))!)
            icon.contentTintColor = isCurrent ? .controlAccentColor : .secondaryLabelColor
            icon.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(icon)
            let name = NSTextField(labelWithString: item.name)
            name.font = .systemFont(ofSize: 13, weight: isCurrent ? .semibold : .regular)
            name.lineBreakMode = .byTruncatingTail
            let dir = NSTextField(labelWithString: item.dir)
            dir.font = .systemFont(ofSize: 11)
            dir.textColor = .tertiaryLabelColor
            dir.lineBreakMode = .byTruncatingMiddle
            let st = NSStackView(views: [name, dir])
            st.orientation = .vertical; st.alignment = .leading; st.spacing = 1
            st.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(st); cell.textField = name
            cell.toolTip = item.path
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 18),
                st.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                st.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
                st.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
            return cell
        }
    }

    // MARK: actions

    @objc private func rowClicked(_ sender: Any?) {
        guard !suppressSelection else { return }
        let row = outlineView.clickedRow
        guard row >= 0, let r = outlineView.item(atRow: row) as? Row else { return }
        switch r.kind {
        case .heading(_, _):
            if let pos = outlineGroup.children.firstIndex(where: { $0 === r }), pos < indexMap.count { onJump?(indexMap[pos]) }
        case .recent(let item):
            onOpenRecent?(item.path)
            outlineView.deselectAll(nil)
        case .group: break
        }
    }

    @objc private func installSkill(_ s: Any?) { onInstallSkill?() }
    @objc private func clearRecents(_ s: Any?) { onClearRecent?() }
}
