// Renders docs/social-preview.png (1280×640), the image shown when the repo link is shared.
// Usage: swift scripts/make-social-preview.swift   (after docs/screenshot.png and docs/icon.png exist)
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let docs = root.appendingPathComponent("docs")
let size = NSSize(width: 1280, height: 640)

let image = NSImage(size: size)
image.lockFocus()

NSGradient(colors: [NSColor(red: 0.18, green: 0.13, blue: 0.15, alpha: 1),
                    NSColor(red: 0.06, green: 0.06, blue: 0.10, alpha: 1)])!
    .draw(in: NSRect(origin: .zero, size: size), angle: -60)

// Soft cool/warm glow behind the panel, echoing the slider gradient.
for (color, center) in [(NSColor(red: 0.25, green: 0.55, blue: 1.0, alpha: 0.22), NSPoint(x: 860, y: 380)),
                        (NSColor(red: 1.0, green: 0.6, blue: 0.25, alpha: 0.16), NSPoint(x: 1080, y: 220))] {
    NSGradient(colors: [color, color.withAlphaComponent(0)])!
        .draw(fromCenter: center, radius: 0, toCenter: center, radius: 360, options: [])
}

if let icon = NSImage(contentsOf: docs.appendingPathComponent("icon.png")) {
    icon.draw(in: NSRect(x: 64, y: 420, width: 150, height: 150))
}

/// Draws one line of text with its bottom-left corner at `point`.
func text(_ string: String, font: NSFont, color: NSColor, at point: NSPoint) {
    NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color]).draw(at: point)
}

let rounded = { (size: CGFloat, weight: NSFont.Weight) -> NSFont in
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
}
text("Hawadaar", font: rounded(92, .semibold), color: .white, at: NSPoint(x: 76, y: 290))
// The name in Urdu script, beside the title.
text("ہوادار", font: .systemFont(ofSize: 44, weight: .regular),
     color: NSColor(red: 1.0, green: 0.68, blue: 0.40, alpha: 1), at: NSPoint(x: 545, y: 318))
let tagline = NSFont.systemFont(ofSize: 34, weight: .regular)
let dim = NSColor(white: 1, alpha: 0.78)
text("Control your MirAIe air conditioner", font: tagline, color: dim, at: NSPoint(x: 80, y: 232))
text("from the macOS menu bar.", font: tagline, color: dim, at: NSPoint(x: 80, y: 188))
text("Free & open source  ·  Native SwiftUI  ·  macOS 14+", font: .systemFont(ofSize: 22, weight: .medium),
     color: NSColor(red: 0.45, green: 0.68, blue: 1.0, alpha: 1), at: NSPoint(x: 80, y: 110))

// The panel screenshot (with its window shadow), scaled to fit the right side.
if let shot = NSImage(contentsOf: docs.appendingPathComponent("panel.png")) {
    let height: CGFloat = 600
    let width = shot.size.width / shot.size.height * height
    shot.draw(in: NSRect(x: 1280 - width - 40, y: 20, width: width, height: height))
}

image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: docs.appendingPathComponent("social-preview.png"))
print("Wrote docs/social-preview.png")
