// Draws the small images the lake uses where DynamicLake has no matching component:
// onit's status dots and the still Bead glyph used in cards.
// DynamicLake sizes images in points and the smallest is 12, so each dot sits centred on a larger
// transparent canvas: the dot looks like onit's 7 pt dot while the whole square takes the click.
// Usage: swift Tools/render-ui.swift Package/Onit.dynamiclakeplugin

import AppKit
import SwiftUI

let red = Color(red: 1.0, green: 0.27, blue: 0.23)     // systemRed, dark
let blue = Color(red: 0.04, green: 0.52, blue: 1.0)    // systemBlue, dark
let green = Color(red: 0.19, green: 0.82, blue: 0.35)  // systemGreen, dark
let secondary = Color.white.opacity(0.55)

/// A 28 pt square with onit's StatusDot in the middle.
struct Dot: View {
    var color: Color
    var ring = false
    var halo = false

    var body: some View {
        ZStack {
            if halo { Circle().fill(blue.opacity(0.22)).frame(width: 12, height: 12) }
            if ring {
                Circle().strokeBorder(secondary, lineWidth: 1.5).frame(width: 7, height: 7)
            } else {
                Circle().fill(color).frame(width: 7, height: 7)
            }
        }
        .frame(width: 28, height: 28)
    }
}

/// onit's BeadGlyph: a still Bead, 16 pt on an 18 pt canvas, for cards and the schedule line.
struct Glyph: View {
    var fill: Color
    var eyes: Color

    var body: some View {
        let size: CGFloat = 16
        return ZStack {
            Circle().fill(fill)
            HStack(spacing: size * 0.3 - size * 0.17) {
                Circle().fill(eyes).frame(width: size * 0.17, height: size * 0.17)
                Circle().fill(eyes).frame(width: size * 0.17, height: size * 0.17)
            }
            .offset(y: -size * 0.04)
        }
        .frame(width: size, height: size)
        .frame(width: 18, height: 18)
    }
}

@MainActor
func write<V: View>(_ view: V, _ name: String, to dir: URL) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let cg = renderer.cgImage else { fatalError("render failed: \(name)") }
    let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
    try! data.write(to: dir.appendingPathComponent(name + ".png"))
}

MainActor.assumeIsolated {
    let dir = URL(fileURLWithPath: CommandLine.arguments[1])
    write(Dot(color: red), "dot-failed", to: dir)
    write(Dot(color: blue, halo: true), "dot-running", to: dir)
    write(Dot(color: green), "dot-ok", to: dir)
    write(Dot(color: secondary, ring: true), "dot-idle", to: dir)
    write(Glyph(fill: Color(red: 1.0, green: 0.35, blue: 0.37), eyes: Color(red: 0.29, green: 0.05, blue: 0.06)), "glyph-failed", to: dir)
    write(Glyph(fill: Color(red: 1.0, green: 0.70, blue: 0.14), eyes: Color(red: 0.23, green: 0.15, blue: 0)), "glyph-headsup", to: dir)
    print("wrote status dots and glyphs to \(dir.path)")
}
