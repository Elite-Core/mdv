import Cocoa

func prettyPath(_ p: String) -> String {
    let home = NSHomeDirectory()
    if p == home { return "~" }
    if p.hasPrefix(home + "/") { return "~" + p.dropFirst(home.count) }
    return p
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    static let appearanceKey = "appearance"
    static var appearanceMode: String { UserDefaults.standard.string(forKey: appearanceKey) ?? "system" }

    static func applyAppearance(_ mode: String) {
        UserDefaults.standard.set(mode, forKey: appearanceKey)
        switch mode {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    func applicationWillFinishLaunching(_ n: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        AppDelegate.applyAppearance(AppDelegate.appearanceMode)
        NSApp.mainMenu = buildMenu()
    }
    func applicationDidFinishLaunching(_ n: Notification) {
        NSLog("[mdv] didFinishLaunching docs=%d", NSDocumentController.shared.documents.count)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.offerSkillIfNeeded() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { Updater.shared.checkInBackground() }
    }

    // MARK: - Claude Code skill (shipped inside the app)

    static var skillSource: URL { Bundle.main.resourceURL!.appendingPathComponent("skill/mdv", isDirectory: true) }
    static var claudeDir: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true) }
    static var skillDest: URL { claudeDir.appendingPathComponent("skills/mdv", isDirectory: true) }

    @discardableResult
    static func installSkill() throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: skillDest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: skillDest.path) { try fm.removeItem(at: skillDest) }
        try fm.copyItem(at: skillSource, to: skillDest)
        return skillDest
    }

    static func skillIsCurrent() -> Bool {
        let a = try? Data(contentsOf: skillSource.appendingPathComponent("SKILL.md"))
        let b = try? Data(contentsOf: skillDest.appendingPathComponent("SKILL.md"))
        return a != nil && a == b
    }

    @objc func installSkillMenu(_ sender: Any?) { runInstall(confirm: true) }
    @objc func checkForUpdates(_ sender: Any?) { Updater.shared.checkNow() }

    @discardableResult
    private func runInstall(confirm: Bool) -> Bool {
        let alert = NSAlert()
        do {
            let dst = try AppDelegate.installSkill()
            guard confirm else { return true }
            alert.messageText = "Claude Code skill installed"
            alert.informativeText = "From its next session, Claude Code will open markdown it writes for you in mdv.\n\n\(prettyPath(dst.path))"
        } catch {
            alert.alertStyle = .warning
            alert.messageText = "Couldn't install the skill"
            alert.informativeText = error.localizedDescription
        }
        alert.runModal()
        return alert.alertStyle != .warning
    }

    /// First launch on a Mac that has Claude Code: offer the skill once. Later launches keep it current.
    private func offerSkillIfNeeded() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: AppDelegate.claudeDir.path) else { return }
        if fm.fileExists(atPath: AppDelegate.skillDest.path) {
            if !AppDelegate.skillIsCurrent() { _ = try? AppDelegate.installSkill() }
            return
        }
        guard !UserDefaults.standard.bool(forKey: "skillOffered") else { return }
        UserDefaults.standard.set(true, forKey: "skillOffered")
        let alert = NSAlert()
        alert.messageText = "Let Claude Code open files in mdv?"
        alert.informativeText = "Installs one small skill file at ~/.claude/skills/mdv so Claude knows to open markdown it writes for you in this app. Nothing else changes. You can do this later from the mdv menu."
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn { runInstall(confirm: false) }
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        NSLog("[mdv] openUntitledFile")
        DocWindowController.home.show()
        return true
    }
    static var quitting = false
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppDelegate.quitting = true
        return .terminateNow
    }
    @objc func showHome(_ sender: Any?) { DocWindowController.home.show() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc func setAppearanceMenu(_ sender: NSMenuItem) {
        AppDelegate.applyAppearance(sender.representedObject as? String ?? "system")
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(setAppearanceMenu(_:)) {
            item.state = (item.representedObject as? String) == AppDelegate.appearanceMode ? .on : .off
        }
        return true
    }

    private func buildMenu() -> NSMenu {
        let main = NSMenu()
        func add(_ title: String, _ build: (NSMenu) -> Void) -> NSMenu {
            let item = NSMenuItem(); main.addItem(item)
            let menu = NSMenu(title: title); item.submenu = menu; build(menu); return menu
        }
        @discardableResult
        func mi(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            menu.addItem(i); return i
        }
        _ = add("mdv") { m in
            mi(m, "About mdv", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
            m.addItem(.separator())
            let up = mi(m, "Check for Updates…", #selector(checkForUpdates(_:)), "", []); up.target = self
            let sk = mi(m, "Install Claude Code Skill…", #selector(installSkillMenu(_:)), "", []); sk.target = self
            m.addItem(.separator())
            mi(m, "Hide mdv", #selector(NSApplication.hide(_:)), "h")
            mi(m, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
            mi(m, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
            m.addItem(.separator())
            mi(m, "Quit mdv", #selector(NSApplication.terminate(_:)), "q")
        }
        _ = add("File") { m in
            mi(m, "Open…", #selector(NSDocumentController.openDocument(_:)), "o")
            let recentItem = mi(m, "Open Recent", nil)
            let recent = NSMenu(title: "Open Recent")
            _ = recent.perform(NSSelectorFromString("_setMenuName:"), with: "NSRecentDocumentsMenu")
            mi(recent, "Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:)))
            recentItem.submenu = recent
            m.addItem(.separator())
            mi(m, "Close", #selector(NSWindow.performClose(_:)), "w")
            mi(m, "Reveal in Finder", #selector(DocWindowController.revealInFinder(_:)), "r", [.command, .shift])
            m.addItem(.separator())
            mi(m, "Print…", #selector(DocWindowController.printDoc(_:)), "p")
        }
        _ = add("Edit") { m in
            mi(m, "Copy", #selector(NSText.copy(_:)), "c")
            mi(m, "Copy Markdown", #selector(DocWindowController.copyMarkdown(_:)), "c", [.command, .shift])
            mi(m, "Select All", #selector(NSText.selectAll(_:)), "a")
            m.addItem(.separator())
            mi(m, "Find…", #selector(NSResponder.performTextFinderAction(_:)), "f").tag = NSTextFinder.Action.showFindInterface.rawValue
            mi(m, "Find Next", #selector(NSResponder.performTextFinderAction(_:)), "g").tag = NSTextFinder.Action.nextMatch.rawValue
            mi(m, "Find Previous", #selector(NSResponder.performTextFinderAction(_:)), "g", [.command, .shift]).tag = NSTextFinder.Action.previousMatch.rawValue
            mi(m, "Use Selection for Find", #selector(NSResponder.performTextFinderAction(_:)), "e").tag = NSTextFinder.Action.setSearchString.rawValue
        }
        _ = add("View") { m in
            mi(m, "Toggle Sidebar", #selector(NSSplitViewController.toggleSidebar(_:)), "s", [.command, .control])
            let appItem = mi(m, "Appearance", nil)
            let sub = NSMenu(title: "Appearance")
            for (t, v) in [("System", "system"), ("Light", "light"), ("Dark", "dark")] {
                let i = mi(sub, t, #selector(setAppearanceMenu(_:)), "", []); i.representedObject = v; i.target = self
            }
            appItem.submenu = sub
            m.addItem(.separator())
            mi(m, "Reload", #selector(DocWindowController.reload(_:)), "r")
            m.addItem(.separator())
            mi(m, "Actual Size", #selector(DocWindowController.actualSize(_:)), "0")
            mi(m, "Zoom In", #selector(DocWindowController.zoomIn(_:)), "=")
            mi(m, "Zoom Out", #selector(DocWindowController.zoomOut(_:)), "-")
        }
        let windowMenu = add("Window") { m in
            let home = mi(m, "Home", #selector(showHome(_:)), "h", [.command, .shift]); home.target = self
            m.addItem(.separator())
            mi(m, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
            mi(m, "Zoom", #selector(NSWindow.performZoom(_:)), "", [])
            m.addItem(.separator())
            mi(m, "Show Previous Tab", #selector(NSWindow.selectPreviousTab(_:)), "\t", [.control, .shift])
            mi(m, "Show Next Tab", #selector(NSWindow.selectNextTab(_:)), "\t", [.control])
            mi(m, "Merge All Windows", #selector(NSWindow.mergeAllWindows(_:)), "", [])
            m.addItem(.separator())
            mi(m, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), "", [])
        }
        NSApp.windowsMenu = windowMenu
        return main
    }
}
