// Renders Resources/AppIcon.icns: an indoor AC unit with a breeze below it, on a dark gradient tile.
// Usage: swift scripts/make-icon.swift
import AppKit

func render(size: CGFloat) -> Data {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = size / 1024

    // macOS icon grid: 824pt rounded square centred in 1024.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(red: 0.20, green: 0.15, blue: 0.17, alpha: 1),
                        NSColor(red: 0.07, green: 0.07, blue: 0.11, alpha: 1)])!.draw(in: tilePath, angle: -90)

    // Indoor unit.
    let unit = NSRect(x: 230 * s, y: 560 * s, width: 564 * s, height: 170 * s)
    NSGradient(colors: [.white, NSColor(white: 0.82, alpha: 1)])!
        .draw(in: NSBezierPath(roundedRect: unit, xRadius: 44 * s, yRadius: 44 * s), angle: -90)
    NSColor(white: 0.62, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 290 * s, y: 588 * s, width: 444 * s, height: 14 * s),
                 xRadius: 7 * s, yRadius: 7 * s).fill()
    NSColor(red: 0.35, green: 0.85, blue: 0.45, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 730 * s, y: 680 * s, width: 22 * s, height: 22 * s)).fill()

    // A breeze below the unit: three soft waves drifting sideways, cool blue to warm orange.
    let colors = [NSColor(red: 0.36, green: 0.66, blue: 1.0, alpha: 1), NSColor(red: 1.0, green: 0.64, blue: 0.32, alpha: 1)]
    for index in 0..<3 {
        let t = CGFloat(index) / 2
        let y = (470 - CGFloat(index) * 105) * s
        let start = (250 + CGFloat(index) * 40) * s
        let end = (770 - CGFloat(index) * 70) * s
        let span = end - start
        let wave = NSBezierPath()
        wave.lineWidth = 38 * s
        wave.lineCapStyle = .round
        wave.move(to: NSPoint(x: start, y: y))
        wave.curve(to: NSPoint(x: start + span * 0.5, y: y),
                   controlPoint1: NSPoint(x: start + span * 0.17, y: y + 60 * s),
                   controlPoint2: NSPoint(x: start + span * 0.33, y: y + 60 * s))
        wave.curve(to: NSPoint(x: end, y: y),
                   controlPoint1: NSPoint(x: start + span * 0.67, y: y - 60 * s),
                   controlPoint2: NSPoint(x: start + span * 0.83, y: y - 60 * s))
        colors[0].blended(withFraction: t, of: colors[1])!.setStroke()
        wave.stroke()
    }

    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return bitmap.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(size: CGFloat(points)).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(size: CGFloat(points * 2)).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let resources = root.appendingPathComponent("Resources")
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try render(size: 512).write(to: root.appendingPathComponent("docs/icon.png"))
print("Wrote Resources/AppIcon.icns and docs/icon.png")
