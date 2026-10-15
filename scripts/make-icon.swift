// Renders Resources/AppIcon.icns: a green dot on a dark rounded square.
// Usage: swift scripts/make-icon.swift
import AppKit

func render(size: Int) -> Data {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let tile = rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08)
        let background = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
        NSGradient(
            starting: NSColor(white: 0.20, alpha: 1),
            ending: NSColor(white: 0.07, alpha: 1)
        )?.draw(in: background, angle: -90)

        let dot = NSBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.32, dy: rect.height * 0.32))
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = NSColor.systemGreen.withAlphaComponent(0.7)
        glow.shadowBlurRadius = rect.width * 0.06
        glow.set()
        NSColor.systemGreen.setFill()
        dot.fill()
        NSGraphicsContext.restoreGraphicsState()
        return true
    }
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return bitmap.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let output = URL(fileURLWithPath: "Resources/AppIcon.icns")
let tool = Process()
tool.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
tool.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try tool.run()
tool.waitUntilExit()
