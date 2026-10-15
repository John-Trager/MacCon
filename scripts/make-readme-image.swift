// Renders docs/states.png: the three menu bar dots with captions.
// Usage: swift scripts/make-readme-image.swift
import AppKit

struct Item {
    let color: NSColor
    let title: String
    let detail: String
}

let items = [
    Item(color: .systemGreen, title: "Online", detail: "Internet reachable"),
    Item(color: .systemOrange, title: "No internet", detail: "Linked, but nothing gets through"),
    Item(color: .systemRed, title: "Offline", detail: "No network"),
]

let scale = 2
let size = NSSize(width: 720, height: 220)
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
bitmap.size = size

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

func draw(_ text: String, font: NSFont, color: NSColor, centeredAt x: CGFloat, y: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let width = text.size(withAttributes: attributes).width
    text.draw(at: NSPoint(x: x - width / 2, y: y), withAttributes: attributes)
}

// Card background
let card = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 24, yRadius: 24)
NSColor(white: 0.11, alpha: 1).setFill()
card.fill()

let columnWidth = size.width / CGFloat(items.count)
for (index, item) in items.enumerated() {
    let centerX = columnWidth * (CGFloat(index) + 0.5)

    // Mock menu bar pill with the dot inside
    let pill = NSRect(x: centerX - 44, y: 120, width: 88, height: 52)
    NSColor(white: 0.20, alpha: 1).setFill()
    NSBezierPath(roundedRect: pill, xRadius: 14, yRadius: 14).fill()

    let dot = NSRect(x: centerX - 11, y: pill.midY - 11, width: 22, height: 22)
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = item.color.withAlphaComponent(0.6)
    glow.shadowBlurRadius = 10
    glow.set()
    item.color.setFill()
    NSBezierPath(ovalIn: dot).fill()
    NSGraphicsContext.restoreGraphicsState()

    draw(item.title, font: .systemFont(ofSize: 20, weight: .semibold), color: .white, centeredAt: centerX, y: 70)
    draw(item.detail, font: .systemFont(ofSize: 13), color: NSColor(white: 0.62, alpha: 1), centeredAt: centerX, y: 44)
}

NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/states.png"))
