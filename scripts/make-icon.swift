import AppKit
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        let inset = p * 0.045
        let rect = NSRect(x: inset, y: inset, width: p - inset * 2, height: p - inset * 2)
        let badge = NSBezierPath(roundedRect: rect, xRadius: p * 0.22, yRadius: p * 0.22)
        NSGradient(starting: NSColor(red: 0.22, green: 0.31, blue: 0.25, alpha: 1), ending: NSColor(red: 0.065, green: 0.09, blue: 0.075, alpha: 1))!.draw(in: badge, angle: -90)
        NSColor.white.withAlphaComponent(0.1).setStroke(); badge.lineWidth = max(p * 0.002, 1); badge.stroke()
        let circle = NSBezierPath(ovalIn: NSRect(x: p * 0.19, y: p * 0.19, width: p * 0.62, height: p * 0.62))
        NSColor(red: 0.74, green: 0.87, blue: 0.72, alpha: 0.1).setFill(); circle.fill()
        NSColor(red: 0.74, green: 0.87, blue: 0.72, alpha: 0.32).setStroke(); circle.lineWidth = p * 0.008; circle.stroke()
        let play = NSBezierPath(); play.move(to: NSPoint(x: p * 0.42, y: p * 0.32)); play.line(to: NSPoint(x: p * 0.42, y: p * 0.68)); play.line(to: NSPoint(x: p * 0.71, y: p * 0.5)); play.close()
        NSColor(red: 0.74, green: 0.87, blue: 0.72, alpha: 1).setFill(); play.fill()
        image.unlockFocus()
        let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }
}
