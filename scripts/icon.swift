import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(calibratedWhite: 0.09, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 56, y: 56, width: 912, height: 912), xRadius: 210, yRadius: 210).fill()
        NSColor.white.setStroke()
        let tray = NSBezierPath(); tray.lineWidth = 52; tray.lineJoinStyle = .round; tray.lineCapStyle = .round
        tray.move(to: NSPoint(x: 245, y: 526)); tray.line(to: NSPoint(x: 245, y: 320)); tray.curve(to: NSPoint(x: 303, y: 264), controlPoint1: NSPoint(x: 245, y: 287), controlPoint2: NSPoint(x: 270, y: 264))
        tray.line(to: NSPoint(x: 721, y: 264)); tray.curve(to: NSPoint(x: 779, y: 320), controlPoint1: NSPoint(x: 754, y: 264), controlPoint2: NSPoint(x: 779, y: 287)); tray.line(to: NSPoint(x: 779, y: 526))
        tray.line(to: NSPoint(x: 620, y: 526)); tray.line(to: NSPoint(x: 585, y: 447)); tray.line(to: NSPoint(x: 439, y: 447)); tray.line(to: NSPoint(x: 404, y: 526)); tray.close(); tray.stroke()
        let lines = NSBezierPath(); lines.lineWidth = 45; lines.lineCapStyle = .round
        lines.move(to: NSPoint(x: 332, y: 650)); lines.line(to: NSPoint(x: 692, y: 650)); lines.move(to: NSPoint(x: 398, y: 762)); lines.line(to: NSPoint(x: 626, y: 762)); lines.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let data = bitmap.representation(using: .png, properties: [:])!
        try data.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
