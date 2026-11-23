// Renders the Sotto app icon (waveform on a deep indigo rounded square).
// Usage: swift make_icon.swift /path/to/output.png
import AppKit

let outputPath = CommandLine.arguments[1]
let size = 1024

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Rounded-square background with the standard macOS icon margin
let bgRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 185, yRadius: 185)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.20, green: 0.20, blue: 0.42, alpha: 1.0),
    NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.18, alpha: 1.0),
])!
gradient.draw(in: bgPath, angle: -90)

// Symmetric waveform bars
let barColor = NSColor(calibratedRed: 0.62, green: 0.78, blue: 1.0, alpha: 1.0)
let heights: [CGFloat] = [130, 250, 400, 540, 400, 250, 130]
let barWidth: CGFloat = 58
let gap: CGFloat = 46
let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
var x = (CGFloat(size) - totalWidth) / 2
for h in heights {
    let barRect = NSRect(x: x, y: (CGFloat(size) - h) / 2, width: barWidth, height: h)
    barColor.setFill()
    NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    x += barWidth + gap
}

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
