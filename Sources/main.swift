import Cocoa

if CommandLine.arguments.contains("--install-skill") {
    do {
        let dst = try AppDelegate.installSkill()
        print("installed \(dst.path)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("mdv: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

if CommandLine.arguments.contains("--check-update") { Updater.shared.checkFromCommandLine() }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
