import AppKit

// Vector artwork in a 1024 x 1024 coordinate space, matching Resources/RightNook.svg.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let iconset = root.appendingPathComponent("_build/RightNook.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        context.translateBy(x: 0, y: 1024)
        context.scaleBy(x: 1, y: -1)
        let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 188, yRadius: 188)
        NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.60, blue: 1, alpha: 1),
                   ending: NSColor(srgbRed: 0.12, green: 0.29, blue: 0.89, alpha: 1))!.draw(in: tile, angle: 90)
        NSColor.white.withAlphaComponent(0.96).setFill()
        NSBezierPath(roundedRect: NSRect(x: 467, y: 282, width: 288, height: 312), xRadius: 44, yRadius: 44).fill()
        NSColor(srgbRed: 0.22, green: 0.44, blue: 0.88, alpha: 1).setStroke()
        for y in [354, 438, 522] {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 535, y: y)); line.line(to: NSPoint(x: 687, y: y))
            line.lineWidth = 24; line.lineCapStyle = .round; line.stroke()
        }
        let cursor = NSBezierPath()
        cursor.move(to: NSPoint(x: 294, y: 346))
        for point in [NSPoint(x: 294, y: 691), NSPoint(x: 382, y: 617), NSPoint(x: 452, y: 765),
                      NSPoint(x: 527, y: 730), NSPoint(x: 456, y: 583), NSPoint(x: 570, y: 564)] {
            cursor.line(to: point)
        }
        cursor.close()
        NSColor(srgbRed: 0.13, green: 0.33, blue: 0.83, alpha: 1).setStroke()
        cursor.lineWidth = 30; cursor.lineJoinStyle = .round; cursor.stroke()
        NSColor.white.setFill(); cursor.fill()
        NSGraphicsContext.restoreGraphicsState()
        let data = bitmap.representation(using: .png, properties: [:])!
        let filename = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try data.write(to: iconset.appendingPathComponent(filename))
        if pixels == 1024 { try data.write(to: resources.appendingPathComponent("RightNook.png")) }
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("RightNook.icns").path]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
