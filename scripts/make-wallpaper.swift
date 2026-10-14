// Renders a soft blue-to-amber wallpaper used as the backdrop for screenshots and demo recordings.
// Usage: swift scripts/make-wallpaper.swift <output.png> [width] [height]
import AppKit

let arguments = CommandLine.arguments
let output = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "wallpaper.png")
let width = arguments.count > 2 ? Double(arguments[2])! : 2880
let height = arguments.count > 3 ? Double(arguments[3])! : 1800

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()
NSGradient(colors: [NSColor(red: 0.05, green: 0.08, blue: 0.20, alpha: 1),
                    NSColor(red: 0.13, green: 0.10, blue: 0.24, alpha: 1)])!
    .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -70)

// Large soft glows: cool blue top right, violet centre, warm amber bottom left.
let glows: [(NSColor, CGFloat, CGFloat, CGFloat)] = [
    (NSColor(red: 0.20, green: 0.50, blue: 1.00, alpha: 0.75), 0.72, 0.85, 0.55),
    (NSColor(red: 0.55, green: 0.30, blue: 0.95, alpha: 0.55), 0.40, 0.55, 0.50),
    (NSColor(red: 1.00, green: 0.55, blue: 0.25, alpha: 0.55), 0.12, 0.10, 0.50),
    (NSColor(red: 0.30, green: 0.80, blue: 0.95, alpha: 0.35), 0.95, 0.30, 0.35),
]
for (color, x, y, radius) in glows {
    let center = NSPoint(x: width * x, y: height * y)
    NSGradient(colors: [color, color.withAlphaComponent(0)])!
        .draw(fromCenter: center, radius: 0, toCenter: center, radius: max(width, height) * radius, options: [])
}
image.unlockFocus()

let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: output)
print("Wrote \(output.path)")
