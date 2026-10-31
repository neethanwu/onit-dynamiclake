// Renders Bead's frames for the plugin package.
// The drawing follows onit's BeadView (colors and proportions); each frame is one pose.
// DynamicLake can't run SwiftUI animation, so the plugin swaps these frames as one image asset.
// Usage: swift Tools/render-bead.swift Package/Onit.dynamiclakeplugin/bead

import AppKit
import SwiftUI

enum Mood { case dozing, onIt, headsUp, failed, nothing }

extension Mood {
    var body: Color {
        switch self {
        case .dozing: Color(white: 0.95)
        case .onIt: Color(red: 0.30, green: 0.64, blue: 1.0)
        case .headsUp: Color(red: 1.0, green: 0.70, blue: 0.14)
        case .failed: Color(red: 1.0, green: 0.35, blue: 0.37)
        case .nothing: .clear
        }
    }
    var eyes: Color {
        switch self {
        case .dozing: Color(white: 0.08)
        case .onIt: Color(red: 0.02, green: 0.16, blue: 0.29)
        case .headsUp: Color(red: 0.23, green: 0.15, blue: 0)
        case .failed: Color(red: 0.29, green: 0.05, blue: 0.06)
        case .nothing: .white.opacity(0.4)
        }
    }
}

struct Pose {
    var mood: Mood
    var x: CGFloat = 0          // offset, in units of body size
    var y: CGFloat = 0
    var breathe: CGFloat = 0    // 0...1
    var blink: CGFloat = 0      // 0 open ... 1 shut
    var closedEyes = false
    var peek = false            // dozing: one eye open
    var glance = CGVector.zero
    var lines: CGFloat = 0      // speed lines opacity; sign = side
    var drop: CGFloat? = nil    // 0 formed ... 1 run off
    var squash: CGFloat = 0     // >0 wide and short, at a turn
}

struct ClosedEye: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 1.6))
        return p
    }
}

struct Drop: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.minX - rect.width * 0.3, y: rect.maxY * 0.95))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.maxX + rect.width * 0.3, y: rect.maxY * 0.95))
        return p
    }
}

struct SpeedLines: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for (i, inset) in [0.25, 0.0, 0.25].enumerated() {
            let y = rect.minY + rect.height * CGFloat(i) / 2
            p.move(to: CGPoint(x: rect.minX + rect.width * inset, y: y))
            p.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return p
    }
}

/// Canvas is 1.5 × body so offsets, lines and the drop never clip, and every frame has the same bounds.
struct BeadFrame: View {
    let pose: Pose
    let size: CGFloat

    var body: some View {
        let s = size
        let dot = s * 0.17
        ZStack {
            if pose.lines != 0 {
                SpeedLines()
                    .stroke(pose.mood.body.opacity(0.55 * abs(pose.lines)), style: StrokeStyle(lineWidth: s * 0.07, lineCap: .round))
                    .frame(width: s * 0.16, height: s * 0.4)
                    .scaleEffect(x: pose.lines > 0 ? 1 : -1)
                    .offset(x: (pose.lines > 0 ? -1 : 1) * s * 0.63)
            }
            ZStack {
                if pose.mood == .nothing {
                    Circle().strokeBorder(.white.opacity(0.4), style: StrokeStyle(lineWidth: max(1, s * 0.06), dash: [s * 0.09, s * 0.1]))
                } else {
                    Circle().fill(pose.mood.body)
                }
                HStack(spacing: s * 0.32 - dot) {
                    ForEach(0..<2, id: \.self) { i in
                        if pose.closedEyes && !(pose.peek && i == 1) {
                            ClosedEye()
                                .stroke(pose.mood.eyes, style: StrokeStyle(lineWidth: s * 0.08, lineCap: .round))
                                .frame(width: dot * 1.1, height: dot * 0.5)
                        } else {
                            Capsule().fill(pose.mood.eyes)
                                .frame(width: dot, height: dot * (1 - 0.85 * pose.blink))
                        }
                    }
                }
                .frame(height: dot)
                .offset(x: pose.glance.dx * s * 0.08, y: -s * 0.05 + pose.glance.dy * s * 0.07)
                if let d = pose.drop {
                    Drop().fill(Color(red: 0.42, green: 0.77, blue: 1))
                        .frame(width: s * 0.2, height: s * 0.26)
                        .offset(x: s * (0.48 + 0.02 * d), y: s * (-0.5 + 0.2 * d))
                        .opacity(1 - d)
                }
            }
            .frame(width: s, height: s)
            .scaleEffect(x: 1 + 0.05 * pose.breathe + 0.07 * pose.squash, y: 1 + 0.12 * pose.breathe - 0.07 * pose.squash, anchor: .bottom)
            .offset(x: pose.x * s, y: pose.y * s)
        }
        .frame(width: s * 1.5, height: s * 1.5)
    }
}

@MainActor
func write(_ pose: Pose, _ name: String, to dir: URL, pixels: CGFloat = 192) {
    let renderer = ImageRenderer(content: BeadFrame(pose: pose, size: pixels / 1.5))
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed: \(name)") }
    let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
    try! data.write(to: dir.appendingPathComponent(name + ".png"))
}

@MainActor
func main() {
    let dir = URL(fileURLWithPath: CommandLine.arguments[1])
    try? FileManager.default.removeItem(at: dir)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let down = CGVector(dx: 0, dy: 0.9)

    // Stills, one per mood.
    write(Pose(mood: .dozing, closedEyes: true), "still-dozing", to: dir)
    write(Pose(mood: .onIt), "still-onit", to: dir)
    write(Pose(mood: .headsUp), "still-headsup", to: dir)
    write(Pose(mood: .failed, glance: down, drop: 0), "still-failed", to: dir)
    write(Pose(mood: .nothing), "still-nothing", to: dir)

    // Dozing peeks with one eye now and then.
    write(Pose(mood: .dozing, closedEyes: true, peek: true), "peek-dozing", to: dir)

    // Blinks: half shut, shut.
    for (mood, name, glance, drop) in [(Mood.onIt, "onit", CGVector.zero, CGFloat?.none), (.headsUp, "headsup", .zero, nil), (.failed, "failed", down, 0)] {
        write(Pose(mood: mood, blink: 0.5, glance: glance, drop: drop), "blink-\(name)-1", to: dir)
        write(Pose(mood: mood, blink: 1, glance: glance, drop: drop), "blink-\(name)-2", to: dir)
    }

    // Heads-up hop: up and back with a small overshoot.
    for (i, y) in [-0.1, -0.2, -0.12, 0.02, -0.01].enumerated() {
        write(Pose(mood: .headsUp, y: y), "hop-\(i)", to: dir)
    }

    // Failed shiver: three quick shakes.
    for (i, x) in [0.09, -0.09, 0.09, -0.09, 0.09].enumerated() {
        write(Pose(mood: .failed, x: x, glance: down, drop: 0), "shiver-\(i)", to: dir)
    }

    // Failed drip: the drop runs off and a new one forms.
    for i in 1...5 {
        write(Pose(mood: .failed, glance: down, drop: CGFloat(i) / 5), "drip-\(i)", to: dir)
    }

    // Running: 8 key poses with a squash at each turn, made to read well at 8 fps.
    let poses: [(x: CGFloat, heading: CGFloat, squash: CGFloat, bob: CGFloat)] = [
        (-0.13, 1, 1, 0), (-0.07, 1, 0, -0.07), (0.02, 1, 0, 0), (0.09, 1, 0, -0.07),
        (0.13, -1, 1, 0), (0.07, -1, 0, -0.07), (-0.02, -1, 0, 0), (-0.09, -1, 0, -0.07),
    ]
    for (i, p) in poses.enumerated() {
        let lines: CGFloat = p.squash > 0 ? 0 : p.heading * (p.bob < 0 ? 1 : 0.6)
        write(Pose(mood: .onIt, x: p.x, y: p.bob, glance: CGVector(dx: p.heading, dy: 0), lines: lines, squash: p.squash), "run-\(i)", to: dir)
    }
    print("wrote Bead frames to \(dir.path)")
}

MainActor.assumeIsolated { main() }
