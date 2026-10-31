// Draws the plugin icon: onit's app icon (Bead on the run) as a full-bleed square.
// DynamicLake rounds the corners itself, so the black tile fills the whole canvas.
// Adapted from onit's SupportFiles/generate-icon.swift.
// Usage: swift Tools/render-icon.swift Package/Onit.dynamiclakeplugin/icon.png
import AppKit

let canvas: CGFloat = 1024

func drawIcon(in context: CGContext) {
    context.setFillColor(NSColor.black.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
    // onit draws on an 824 pt tile inset by 100; stretch that tile to the whole canvas.
    context.scaleBy(x: canvas / 824, y: canvas / 824)
    context.translateBy(x: -100, y: -100)

    let blue = NSColor(red: 0.30, green: 0.64, blue: 1, alpha: 1).cgColor
    context.setStrokeColor(blue)
    context.setLineWidth(26)
    context.setLineCap(.round)
    for (dy, inset) in [(80.0, 40.0), (0.0, 0.0), (-80.0, 40.0)] as [(CGFloat, CGFloat)] {
        context.move(to: CGPoint(x: 210 + inset, y: 500 + dy))
        context.addLine(to: CGPoint(x: 320, y: 500 + dy))
        context.strokePath()
    }

    let center = CGPoint(x: 560, y: 500)
    let radius: CGFloat = 200
    context.setFillColor(NSColor(white: 0.95, alpha: 1).cgColor)
    context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))

    context.setFillColor(NSColor(white: 0.07, alpha: 1).cgColor)
    let eye = radius * 0.17
    for side: CGFloat in [-1, 1] {
        let point = CGPoint(x: center.x + side * radius * 0.32 + radius * 0.09, y: center.y + radius * 0.05)
        context.fillEllipse(in: CGRect(x: point.x - eye, y: point.y - eye, width: eye * 2, height: eye * 2))
    }
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.cgContext.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawIcon(in: graphics.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try render(size: 512).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("Wrote \(CommandLine.arguments[1])")
