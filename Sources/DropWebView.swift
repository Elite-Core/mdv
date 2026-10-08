import Cocoa
import WebKit

/// WKWebView that accepts markdown file drops natively (HTML5 drops in WebKit don't expose file paths).
final class DropWebView: WKWebView {
    var onDrop: (([URL]) -> Void)?
    var onDragState: ((Bool) -> Void)?
    static let exts: Set<String> = ["md", "markdown", "mdown", "mdx", "txt"]

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
