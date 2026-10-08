import Cocoa

@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    private(set) var text = ""
    private(set) var mtime = Date()
    private var watch: Timer?

    override class var autosavesInPlace: Bool { false }
    override var isDocumentEdited: Bool { false }

    override func read(from url: URL, ofType typeName: String) throws {
        let data = try Data(contentsOf: url)
        text = String(decoding: data, as: UTF8.self)
        mtime = MarkdownDocument.modDate(url) ?? Date()
    }

    private static func modDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    override func makeWindowControllers() {
        addWindowController(DocWindowController())
        HomeWindowController.shared.hide()
        watch = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.checkForChanges() }
    }

    func reloadFromDisk() {
        guard let u = fileURL else { return }
        try? read(from: u, ofType: "")
    }

    private func checkForChanges() {
        guard let u = fileURL, let m = MarkdownDocument.modDate(u), m != mtime else { return }
        reloadFromDisk()
        (windowControllers.first as? DocWindowController)?.render(changed: true)
    }

    override func close() {
        watch?.invalidate(); watch = nil
        super.close()
        if !AppDelegate.quitting && NSDocumentController.shared.documents.isEmpty { HomeWindowController.shared.show() }
    }
}
