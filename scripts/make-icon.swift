import AppKit

// Draw the icon at each required size so all outputs remain crisp on Retina
// displays. The transparent canvas preserves the native macOS icon silhouette.
func makeIcon(size: Int, destination: URL) throws {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB,
        bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    let tile = NSBezierPath(roundedRect: NSRect(x: 102, y: 102, width: 820, height: 820), xRadius: 188, yRadius: 188)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 32
    shadow.shadowOffset = NSSize(width: 0, height: -15)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(calibratedRed: 0.14, green: 0.43, blue: 0.36, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.34, blue: 0.29, alpha: 1),
        NSColor(calibratedRed: 0.27, green: 0.67, blue: 0.53, alpha: 1),
    ])!.draw(in: tile, angle: 65)

    let card = NSBezierPath(roundedRect: NSRect(x: 245, y: 263, width: 534, height: 493), xRadius: 65, yRadius: 65)
    let cardShadow = NSShadow()
    cardShadow.shadowColor = NSColor.black.withAlphaComponent(0.17)
    cardShadow.shadowBlurRadius = 24
    cardShadow.shadowOffset = NSSize(width: 0, height: -10)
    NSGraphicsContext.saveGraphicsState()
    cardShadow.set()
    NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
    card.fill()
    NSGraphicsContext.restoreGraphicsState()

    let ink = NSColor(calibratedRed: 0.14, green: 0.43, blue: 0.35, alpha: 1)
    ink.setStroke()
    let rule = NSBezierPath()
    rule.move(to: NSPoint(x: 299, y: 614))
    rule.line(to: NSPoint(x: 725, y: 614))
    rule.lineWidth = 17
    rule.lineCapStyle = .round
    rule.stroke()

    for x in [365.0, 659.0] {
        let ring = NSBezierPath()
        ring.move(to: NSPoint(x: x, y: 710))
        ring.line(to: NSPoint(x: x, y: 790))
        ring.lineWidth = 35
        ring.lineCapStyle = .round
        ring.stroke()
    }

    // A sparse calendar grid gives the clock the visual emphasis.
    NSColor(calibratedRed: 0.72, green: 0.84, blue: 0.77, alpha: 1).setFill()
    for point in [NSPoint(x: 334, y: 502), NSPoint(x: 434, y: 502), NSPoint(x: 334, y: 402)] {
        NSBezierPath(roundedRect: NSRect(x: point.x - 24, y: point.y - 24, width: 48, height: 48), xRadius: 12, yRadius: 12).fill()
    }

    let clockCenter = NSPoint(x: 630, y: 407)
    let clock = NSBezierPath(ovalIn: NSRect(x: 493, y: 270, width: 274, height: 274))
    ink.setFill()
    clock.fill()
    NSColor.white.setStroke()
    let hands = NSBezierPath()
    hands.move(to: NSPoint(x: clockCenter.x, y: 488))
    hands.line(to: clockCenter)
    hands.line(to: NSPoint(x: 693, y: 366))
    hands.lineWidth = 21
    hands.lineJoinStyle = .round
    hands.lineCapStyle = .round
    hands.stroke()

    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
}

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: make-icon <output.iconset> <output.icns>")
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let entries: [(points: Int, scale: Int, type: String)] = [
    (16, 1, "icp4"), (16, 2, "ic11"), (32, 1, "icp5"), (32, 2, "ic12"),
    (128, 1, "ic07"), (128, 2, "ic13"), (256, 1, "ic08"), (256, 2, "ic14"),
    (512, 1, "ic09"), (512, 2, "ic10"),
]

func lengthBytes(_ value: Int) -> Data {
    var bigEndian = UInt32(value).bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
}

// Modern ICNS entries contain the PNG bytes directly. Encoding the small
// container here avoids an additional runtime dependency on iconutil.
var iconEntries = Data()
for (points, scale, type) in entries {
    let filename = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    let file = directory.appendingPathComponent(filename)
    try makeIcon(size: points * scale, destination: file)
    let png = try Data(contentsOf: file)
    iconEntries.append(Data(type.utf8))
    iconEntries.append(lengthBytes(png.count + 8))
    iconEntries.append(png)
}
var icns = Data("icns".utf8)
icns.append(lengthBytes(iconEntries.count + 8))
icns.append(iconEntries)
try icns.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
