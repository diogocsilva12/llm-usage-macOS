import AppKit

guard CommandLine.arguments.count == 2 else { exit(1) }
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("limitbar-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: iconset) }

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let factor = CGFloat(pixels) / 512
        let transform = NSAffineTransform()
        transform.scale(by: factor)
        transform.concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 16, y: 16, width: 480, height: 480), xRadius: 108, yRadius: 108)
        NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.25, blue: 0.48, alpha: 1),
                   ending: NSColor(srgbRed: 0.06, green: 0.08, blue: 0.20, alpha: 1))!.draw(in: background, angle: 90)
        for (index, fraction) in [0.32, 0.78, 0.06].enumerated() {
            let y = CGFloat(322 - index * 84)
            NSColor.white.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: NSRect(x: 104, y: y, width: 304, height: 24), xRadius: 12, yRadius: 12).fill()
            (index == 1 ? NSColor(srgbRed: 1, green: 0.70, blue: 0.12, alpha: 1) : NSColor(srgbRed: 0.83, green: 0.88, blue: 1, alpha: 1)).setFill()
            NSBezierPath(roundedRect: NSRect(x: 104, y: y, width: CGFloat(max(24, 304 * fraction)), height: 24), xRadius: 12, yRadius: 12).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        try png.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", destination.path]
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
