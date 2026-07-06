import SwiftUI

// A pair of glowing vacuum-tube VU meters — one per stereo channel — for the
// upper-right corner of every client. Each tube is grey at rest and heats to a
// golden-orange glow with the music's loudness: the filament in the middle burns
// brightest, and the surrounding glass bulb glows more softly. Levels come from
// AudioLevelMonitor (smoothed over ~0.5 s), so the glow rises and falls with the
// music instead of flickering.
//
// Rendered with SwiftUI shapes + gradients so it scales cleanly and stays light
// on both platforms. `scale` sizes the whole meter (≈1 on macOS/iPad, smaller on
// iPhone where the corner is tight).

public struct VacuumTubeMeter: View {
    @ObservedObject private var monitor: AudioLevelMonitor
    private let scale: CGFloat

    public init(monitor: AudioLevelMonitor, scale: CGFloat = 1) {
        self.monitor = monitor
        self.scale = scale
    }

    public var body: some View {
        // Just the two tubes — no housing/border, so they read as instruments
        // sitting directly in the corner (or in the macOS top bar).
        HStack(alignment: .top, spacing: 9 * scale) {
            VacuumTube(level: monitor.left, scale: scale)
            VacuumTube(level: monitor.right, scale: scale)
        }
    }
}

// One valve. `level` is 0...1 (0 = cold/grey, 1 = fully lit).
struct VacuumTube: View {
    var level: Double
    var scale: CGFloat = 1

    // intrinsic geometry (before scale)
    private var w: CGFloat { 30 * scale }
    private var glassH: CGFloat { 64 * scale }
    private var baseH: CGFloat { 15 * scale }
    private var pinH: CGFloat { 5 * scale }

    // warm palette for the excited glow
    private let amber     = Color(djHex: 0xFF9B2E)   // golden-orange filament
    private let amberDeep = Color(djHex: 0xE0620A)   // deeper edge of the glow
    private let hot       = Color(djHex: 0xFFE7B4)   // near white-hot core at high level
    private let glassTop  = Color(white: 0.30)
    private let glassBot  = Color(white: 0.13)
    private let filamentCold = Color(white: 0.42)

    // clamp for safety in case a stray value slips through
    private var lvl: Double { min(1, max(0, level)) }

    var body: some View {
        VStack(spacing: -2 * scale) {
            glass
                .frame(width: w, height: glassH)
            socket
                .frame(width: w * 0.82, height: baseH)
        }
        .animation(.easeOut(duration: 0.12), value: level)
    }

    private var glass: some View {
        let shape = TubeGlassShape()
        return ZStack {
            // glass envelope: cool grey at rest, warming slightly with level
            shape.fill(
                LinearGradient(colors: [glassTop, glassBot],
                               startPoint: .top, endPoint: .bottom))
            // the bulb itself glows — but less than the filament
            shape.fill(
                RadialGradient(colors: [amber.opacity(0.55 * lvl), amber.opacity(0.10 * lvl)],
                               center: .center, startRadius: 0, endRadius: w * 0.9))

            // filament glow (the brightest element), soft and blooming
            FilamentShape()
                .stroke(amber, style: StrokeStyle(lineWidth: 3.2 * scale, lineCap: .round, lineJoin: .round))
                .blur(radius: (2.2 + 4.5 * lvl) * scale)
                .opacity(min(1, lvl * 1.25))
            // filament wire: cold grey wire always visible, heating to amber
            FilamentShape()
                .stroke(filamentCold, style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round, lineJoin: .round))
            FilamentShape()
                .stroke(amber, style: StrokeStyle(lineWidth: 1.7 * scale, lineCap: .round, lineJoin: .round))
                .opacity(lvl)
            // white-hot core once it's really cooking
            FilamentShape()
                .stroke(hot, style: StrokeStyle(lineWidth: 0.9 * scale, lineCap: .round, lineJoin: .round))
                .opacity(max(0, (lvl - 0.55) / 0.45))

            // glass rim + a soft vertical specular highlight to sell the glass
            shape.stroke(
                LinearGradient(colors: [Color(white: 0.6).opacity(0.8), Color(white: 0.3).opacity(0.5)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
            Capsule()
                .fill(Color.white.opacity(0.10))
                .frame(width: w * 0.12, height: glassH * 0.5)
                .offset(x: -w * 0.24, y: -glassH * 0.06)
                .blur(radius: 1.5 * scale)
        }
        // outward glow of the whole bulb (grows with level, gone at rest)
        .shadow(color: amberDeep.opacity(0.7 * lvl), radius: 9 * scale * lvl)
        .shadow(color: amber.opacity(0.5 * lvl), radius: 4 * scale * lvl)
    }

    private var socket: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: DJTheme.cornerRadius(4 * scale), style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.20), Color(white: 0.07)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: DJTheme.cornerRadius(4 * scale), style: .continuous)
                        .strokeBorder(Color(white: 0.32), lineWidth: 0.75))
            // metal pins poking out the bottom
            HStack(spacing: w * 0.13) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(LinearGradient(colors: [Color(white: 0.65), Color(white: 0.35)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 2 * scale, height: pinH)
                }
            }
            .offset(y: pinH * 0.85)
        }
    }
}

// The glass envelope silhouette: a cylinder with a full domed top and lightly
// rounded bottom shoulders — enough to read as a valve without being fussy.
struct TubeGlassShape: Shape {
    func path(in rect: CGRect) -> Path {
        let topR = rect.width / 2
        let botR = rect.width * 0.2
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY - botR))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topR))
        p.addQuadCurve(to: CGPoint(x: rect.minX + topR, y: rect.minY),
                       control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + topR),
                       control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - botR))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - botR, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + botR, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - botR),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// A hairpin filament (an inverted U with slightly splayed legs), centered in the
// bulb — the classic glowing element you can see suspended inside the glass.
struct FilamentShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let topY = rect.minY + rect.height * 0.28
        let botY = rect.minY + rect.height * 0.72
        let splay = rect.width * 0.19    // legs wider apart at the bottom
        let neck  = rect.width * 0.11    // and closer together at the top
        var p = Path()
        p.move(to: CGPoint(x: cx - splay, y: botY))
        p.addLine(to: CGPoint(x: cx - neck, y: topY))
        p.addQuadCurve(to: CGPoint(x: cx + neck, y: topY),
                       control: CGPoint(x: cx, y: topY - rect.height * 0.12))
        p.addLine(to: CGPoint(x: cx + splay, y: botY))
        return p
    }
}
