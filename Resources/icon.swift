import Cocoa

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let box = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
    let bg = NSBezierPath(roundedRect: box, xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.20, blue: 0.24, alpha: 1),
               ending: NSColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 1))!.draw(in: bg, angle: -90)
    let inner = NSRect(x: s * 0.20, y: s * 0.30, width: s * 0.60, height: s * 0.40)
    let frame = NSBezierPath(roundedRect: inner, xRadius: s * 0.045, yRadius: s * 0.045)
    frame.lineWidth = max(1, s * 0.035)
    NSColor.white.withAlphaComponent(0.92).setStroke(); frame.stroke()
    let font = NSFont.systemFont(ofSize: s * 0.26, weight: .bold)
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let text = NSAttributedString(string: "M↓", attributes: [.font: font, .foregroundColor: NSColor.white, .paragraphStyle: para])
    let tsz = text.size()
    text.draw(in: NSRect(x: 0, y: (s - tsz.height) / 2 + s * 0.01, width: s, height: tsz.height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
