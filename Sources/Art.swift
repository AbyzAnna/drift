// Art.swift — everything Drift draws: particle sprites, drifts, icicles, frost, and Pip.
// Sprites are rendered once per season into small bitmaps; drifts redraw only when they change;
// Pip redraws every frame into a small layer.

import Cocoa

let rgbSpace = CGColorSpaceCreateDeviceRGB()

extension RGBA {
    var cg: CGColor { CGColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a)) }
    func with(alpha: Double) -> CGColor { CGColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(alpha)) }
}

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor { RGBA(v, Double(a)).cg }

func gradient(_ colors: [CGColor], _ locs: [CGFloat]) -> CGGradient? {
    CGGradient(colorsSpace: rgbSpace, colors: colors as CFArray, locations: locs)
}

/// Seeded random numbers so procedural art looks the same every launch.
struct Seeded {
    var s: UInt64
    init(_ seed: UInt64) { s = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> CGFloat {
        s ^= s << 13; s ^= s >> 7; s ^= s << 17
        return CGFloat(s % 1_000_000) / 1_000_000
    }
    mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * next() }
}

// MARK: - Sprites

enum Sprites {
    typealias Draw = (CGContext) -> Void

    /// Draws into a px×px bitmap whose coordinate space is 48×48 units centred on the origin (y up).
    static func make(_ px: Int, _ draw: Draw) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: rgbSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let k = CGFloat(px) / 48
        ctx.scaleBy(x: k, y: k)
        ctx.translateBy(x: 24, y: 24)
        draw(ctx)
        return ctx.makeImage()
    }

    // Snow ---------------------------------------------------------------

    /// A six-armed dendrite crystal.
    static func crystal(_ variant: Int) -> Draw {
        return { ctx in
            if let g = gradient([hex(0xFFFFFF, 0.55), hex(0xE6F0FF, 0.18), hex(0xFFFFFF, 0)], [0, 0.45, 1]) {
                ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 23, options: [])
            }
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            for arm in 0..<6 {
                ctx.saveGState()
                ctx.rotate(by: CGFloat(arm) * CGFloat.pi / 3)
                ctx.setStrokeColor(hex(0xFFFFFF, 0.97))
                ctx.setLineWidth(2.6)
                ctx.move(to: .zero); ctx.addLine(to: CGPoint(x: 0, y: 20))
                ctx.strokePath()
                ctx.setLineWidth(1.9)
                let branches: [(CGFloat, CGFloat)]
                switch variant % 3 {
                case 0: branches = [(7, 7), (12.5, 5.5), (16.5, 3.5)]
                case 1: branches = [(9, 4.5), (15, 3)]
                default: branches = [(5, 4), (9, 6.5), (13, 5.5), (16.5, 3.5)]
                }
                for (at, len) in branches {
                    for side: CGFloat in [-1, 1] {
                        ctx.move(to: CGPoint(x: 0, y: at))
                        ctx.addLine(to: CGPoint(x: side * len * 0.87, y: at + len * 0.5))
                    }
                }
                ctx.strokePath()
                if variant % 3 == 1 {
                    // little plate at the tip
                    ctx.setFillColor(hex(0xFFFFFF, 0.9))
                    hexagon(ctx, CGPoint(x: 0, y: 19), 2.8)
                    ctx.fillPath()
                }
                ctx.restoreGState()
            }
            ctx.setFillColor(hex(0xFFFFFF, 0.95))
            hexagon(ctx, .zero, 3.6)
            ctx.fillPath()
            ctx.setFillColor(hex(0xCFE2FF, 0.6))
            hexagon(ctx, .zero, 1.6)
            ctx.fillPath()
        }
    }

    static func hexagon(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat) {
        for i in 0..<6 {
            let a = CGFloat(i) * CGFloat.pi / 3 + CGFloat.pi / 6
            let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
        }
        ctx.closePath()
    }

    /// A soft clump of snow (most flakes look like this up close).
    static func clump(_ seed: UInt64) -> Draw {
        return { ctx in
            var r = Seeded(seed)
            for _ in 0..<5 {
                let c = CGPoint(x: r.range(-6, 6), y: r.range(-6, 6))
                let rad = r.range(9, 14)
                if let g = gradient([hex(0xFFFFFF, 0.95), hex(0xF4F8FF, 0.7), hex(0xFFFFFF, 0)], [0, 0.5, 1]) {
                    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: rad, options: [])
                }
            }
        }
    }

    /// Out-of-focus background flake.
    static func bokeh(_ col: CGColor, ring: Bool) -> Draw {
        return { ctx in
            if let g = gradient([col, col, hex(0xFFFFFF, 0)], [0, 0.55, 1]) {
                ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 22, options: [])
            }
            if ring {
                ctx.setStrokeColor(hex(0xFFFFFF, 0.25))
                ctx.setLineWidth(1.5)
                ctx.strokeEllipse(in: CGRect(x: -15, y: -15, width: 30, height: 30))
            }
        }
    }

    // Petals & blossoms ---------------------------------------------------

    static func petalPath(_ ctx: CGContext) {
        ctx.move(to: CGPoint(x: 0, y: -21))
        ctx.addCurve(to: CGPoint(x: -9, y: 18), control1: CGPoint(x: -18, y: -10), control2: CGPoint(x: -19, y: 10))
        ctx.addQuadCurve(to: CGPoint(x: 0, y: 13), control: CGPoint(x: -3, y: 18))
        ctx.addQuadCurve(to: CGPoint(x: 9, y: 18), control: CGPoint(x: 3, y: 18))
        ctx.addCurve(to: CGPoint(x: 0, y: -21), control1: CGPoint(x: 19, y: 10), control2: CGPoint(x: 18, y: -10))
        ctx.closePath()
    }

    static func petal(_ tip: CGColor, _ base: CGColor) -> Draw {
        return { ctx in
            ctx.saveGState()
            petalPath(ctx)
            ctx.clip()
            if let g = gradient([tip, base], [0, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 18), end: CGPoint(x: 0, y: -21), options: [])
            }
            // soft darker rim
            if let g = gradient([hex(0xFFFFFF, 0), hex(0xD9658F, 0.28)], [0.6, 1]) {
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: 0, y: 0), startRadius: 0, endCenter: CGPoint(x: 0, y: 0), endRadius: 22, options: [])
            }
            ctx.restoreGState()
            ctx.setStrokeColor(hex(0xC2507C, 0.35))
            ctx.setLineWidth(0.8)
            ctx.move(to: CGPoint(x: 0, y: -18)); ctx.addQuadCurve(to: CGPoint(x: 0, y: 10), control: CGPoint(x: 1.5, y: -4))
            ctx.move(to: CGPoint(x: -1, y: -12)); ctx.addQuadCurve(to: CGPoint(x: -6, y: 9), control: CGPoint(x: -6, y: -2))
            ctx.move(to: CGPoint(x: 1, y: -12)); ctx.addQuadCurve(to: CGPoint(x: 6, y: 9), control: CGPoint(x: 6, y: -2))
            ctx.strokePath()
        }
    }

    static func blossom(_ col: CGColor, _ inner: CGColor, _ center: CGColor, petals: Int = 5, round: Bool = false) -> Draw {
        return { ctx in
            for i in 0..<petals {
                ctx.saveGState()
                ctx.rotate(by: CGFloat(i) * 2 * CGFloat.pi / CGFloat(petals))
                ctx.translateBy(x: 0, y: 10.5)
                ctx.scaleBy(x: round ? 0.48 : 0.42, y: 0.5)
                petalPath(ctx)
                ctx.clip()
                if let g = gradient([col, inner], [0, 1]) {
                    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 20), end: CGPoint(x: 0, y: -20), options: [])
                }
                ctx.restoreGState()
            }
            ctx.setFillColor(center)
            ctx.fillEllipse(in: CGRect(x: -4.5, y: -4.5, width: 9, height: 9))
            ctx.setFillColor(hex(0xFFF6C8, 0.9))
            for i in 0..<6 {
                let a = CGFloat(i) * CGFloat.pi / 3
                ctx.fillEllipse(in: CGRect(x: cos(a) * 3.2 - 0.9, y: sin(a) * 3.2 - 0.9, width: 1.8, height: 1.8))
            }
        }
    }

    static func daisy() -> Draw {
        return { ctx in
            for i in 0..<14 {
                ctx.saveGState()
                ctx.rotate(by: CGFloat(i) * 2 * CGFloat.pi / 14)
                if let g = gradient([hex(0xFFFFFF), hex(0xE9E4F0)], [0, 1]) {
                    ctx.addEllipse(in: CGRect(x: -2.6, y: 4, width: 5.2, height: 17))
                    ctx.clip()
                    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 21), end: CGPoint(x: 0, y: 4), options: [])
                }
                ctx.restoreGState()
            }
            if let g = gradient([hex(0xFFD54A), hex(0xE59A1C)], [0, 1]) {
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: -1.5, y: 1.5), startRadius: 0, endCenter: .zero, endRadius: 6.5, options: [])
            }
        }
    }

    // Leaves ---------------------------------------------------------------

    static func polar(_ ctx: CGContext, steps: Int = 90, _ r: (CGFloat) -> CGFloat) {
        for i in 0...steps {
            let a = CGFloat(i) / CGFloat(steps) * 2 * CGFloat.pi
            let rr = r(a)
            let p = CGPoint(x: cos(a) * rr, y: sin(a) * rr)
            if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
        }
        ctx.closePath()
    }

    static func maple(_ a: CGColor, _ b: CGColor, _ vein: CGColor) -> Draw {
        return { ctx in
            ctx.saveGState()
            polar(ctx, steps: 140) { t in
                let u = t - CGFloat.pi / 2                       // lobes point up
                let lobes = pow(abs(cos(2.5 * u)), 0.6)
                var r = 9 + 12 * lobes + 1.3 * sin(t * 22)
                let fromStem = abs(atan2(sin(t + CGFloat.pi / 2), cos(t + CGFloat.pi / 2)))
                if fromStem < 0.5 { r *= 0.45 + fromStem }      // notch at the stem
                return r
            }
            ctx.clip()
            if let g = gradient([a, b], [0, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 22), end: CGPoint(x: 0, y: -14), options: [])
            }
            if let g = gradient([hex(0x000000, 0), hex(0x3A1205, 0.25)], [0.55, 1]) {
                ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 22, options: [])
            }
            ctx.restoreGState()
            ctx.setStrokeColor(vein)
            ctx.setLineCap(.round)
            ctx.setLineWidth(1.1)
            for k in 0..<5 {
                let t = CGFloat.pi / 2 + (CGFloat(k) - 2) * 2 * CGFloat.pi / 5 * 0.62
                ctx.move(to: CGPoint(x: 0, y: -2)); ctx.addLine(to: CGPoint(x: cos(t) * 17, y: sin(t) * 17))
            }
            ctx.strokePath()
            ctx.setLineWidth(1.6)
            ctx.move(to: CGPoint(x: 0, y: -2)); ctx.addLine(to: CGPoint(x: 0.5, y: -21))
            ctx.strokePath()
        }
    }

    static func oak(_ a: CGColor, _ b: CGColor, _ vein: CGColor, wavy: Bool) -> Draw {
        return { ctx in
            ctx.saveGState()
            ctx.rotate(by: 0.35)
            polar(ctx, steps: 120) { t in
                let ex: CGFloat = 9, ey: CGFloat = 19
                let base = (ex * ey) / sqrt(pow(ey * cos(t), 2) + pow(ex * sin(t), 2))
                return base * (1 + (wavy ? 0.16 * sin(t * 9) : 0.05 * sin(t * 30)))
            }
            ctx.clip()
            if let g = gradient([a, b], [0, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: -6, y: 20), end: CGPoint(x: 6, y: -20), options: [])
            }
            ctx.restoreGState()
            ctx.saveGState()
            ctx.rotate(by: 0.35)
            ctx.setStrokeColor(vein)
            ctx.setLineCap(.round)
            ctx.setLineWidth(1.3)
            ctx.move(to: CGPoint(x: 0, y: -23)); ctx.addLine(to: CGPoint(x: 0, y: 17))
            ctx.strokePath()
            ctx.setLineWidth(0.8)
            for k in 0..<4 {
                let y = -10 + CGFloat(k) * 7
                ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: -6, y: y + 5))
                ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: 6, y: y + 5))
            }
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    // Spring ---------------------------------------------------------------

    /// A dandelion seed: a tiny seed, a stalk and a parachute of fine filaments.
    static func dandelion() -> Draw {
        return { ctx in
            ctx.setLineCap(.round)
            ctx.setStrokeColor(hex(0xFFFFFF, 0.75))
            ctx.setLineWidth(0.9)
            ctx.move(to: CGPoint(x: 0, y: -18)); ctx.addLine(to: CGPoint(x: 0, y: 4))
            ctx.strokePath()
            ctx.setStrokeColor(hex(0xFFFFFF, 0.6))
            ctx.setLineWidth(0.7)
            for i in 0..<17 {
                let a = CGFloat.pi * (0.08 + 0.84 * CGFloat(i) / 16)
                ctx.move(to: CGPoint(x: 0, y: 4))
                ctx.addQuadCurve(to: CGPoint(x: cos(a) * 17, y: 4 + sin(a) * 15), control: CGPoint(x: cos(a) * 8, y: 4 + sin(a) * 11))
            }
            ctx.strokePath()
            ctx.setFillColor(hex(0xFFFFFF, 0.8))
            for i in 0..<17 {
                let a = CGFloat.pi * (0.08 + 0.84 * CGFloat(i) / 16)
                ctx.fillEllipse(in: CGRect(x: cos(a) * 17 - 1, y: 4 + sin(a) * 15 - 1, width: 2, height: 2))
            }
            ctx.setFillColor(hex(0x8C7A55))
            ctx.fillEllipse(in: CGRect(x: -1.6, y: -22, width: 3.2, height: 6))
        }
    }

    static func youngLeaf(_ a: CGColor, _ b: CGColor) -> Draw {
        return { ctx in
            ctx.saveGState()
            ctx.rotate(by: 0.6)
            ctx.move(to: CGPoint(x: 0, y: -21))
            ctx.addQuadCurve(to: CGPoint(x: 0, y: 21), control: CGPoint(x: -20, y: 2))
            ctx.addQuadCurve(to: CGPoint(x: 0, y: -21), control: CGPoint(x: 20, y: 2))
            ctx.clip()
            if let g = gradient([a, b], [0, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: -10, y: 0), end: CGPoint(x: 10, y: 0), options: [])
            }
            ctx.restoreGState()
            ctx.saveGState()
            ctx.rotate(by: 0.6)
            ctx.setStrokeColor(hex(0xEFFFD8, 0.55))
            ctx.setLineWidth(0.9)
            ctx.move(to: CGPoint(x: 0, y: -21)); ctx.addLine(to: CGPoint(x: 0, y: 19))
            for k in 0..<4 {
                let y = -10 + CGFloat(k) * 7
                ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: -6, y: y + 6))
                ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: 6, y: y + 6))
            }
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    // Stars & rain -----------------------------------------------------------

    static func sparkle(_ col: CGColor, rays: CGFloat = 20) -> Draw {
        return { ctx in
            if let g = gradient([hex(0xFFFFFF), col, hex(0xFFFFFF, 0)], [0, 0.22, 1]) {
                ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 15, options: [])
            }
            ctx.setFillColor(hex(0xFFFFFF, 0.95))
            ctx.move(to: CGPoint(x: 0, y: rays))
            ctx.addQuadCurve(to: CGPoint(x: rays, y: 0), control: .zero)
            ctx.addQuadCurve(to: CGPoint(x: 0, y: -rays), control: .zero)
            ctx.addQuadCurve(to: CGPoint(x: -rays, y: 0), control: .zero)
            ctx.addQuadCurve(to: CGPoint(x: 0, y: rays), control: .zero)
            ctx.closePath()
            ctx.fillPath()
        }
    }

    /// A drop of water on glass: dark refracted rim, bright caustic at the bottom, a highlight on top.
    static func glassDrop() -> Draw {
        return { ctx in
            let r: CGFloat = 20
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 3, color: hex(0x000000, 0.25))
            ctx.setFillColor(hex(0xA9C6DC, 0.35))
            ctx.fillEllipse(in: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
            ctx.clip()
            if let g = gradient([hex(0x1B2B3A, 0.45), hex(0x8FB3CF, 0.15), hex(0xF2FAFF, 0.55)], [0, 0.55, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: r), end: CGPoint(x: 0, y: -r), options: [])
            }
            ctx.restoreGState()
            ctx.setStrokeColor(hex(0x0E1A24, 0.35))
            ctx.setLineWidth(1.6)
            ctx.strokeEllipse(in: CGRect(x: -r + 0.8, y: -r + 0.8, width: 2 * r - 1.6, height: 2 * r - 1.6))
            ctx.setFillColor(hex(0xFFFFFF, 0.85))
            ctx.fillEllipse(in: CGRect(x: -9, y: 7, width: 7, height: 5))
            ctx.setFillColor(hex(0xFFFFFF, 0.5))
            ctx.fillEllipse(in: CGRect(x: 4, y: -14, width: 8, height: 3))
        }
    }

    static func streak(px: Int, head: CGColor) -> CGImage? {
        let w = max(2, px / 16), h = px
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: rgbSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let g = gradient([hex(0xFFFFFF, 0), head], [0, 1])
        else { return nil }
        // bright end at the bottom (y = 0) — the leading end of a falling streak
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(h)), end: .zero, options: [])
        return ctx.makeImage()
    }

    // Per-season sets ---------------------------------------------------------

    struct Set {
        var near: [CGImage] = []
        var far: [CGImage] = []
        var streak: CGImage?
        var glint: CGImage?
        var drop: CGImage?
        var meteor: CGImage?
        var all: [CGImage] { near + far }
    }

    static func set(for kind: Kind, scale: CGFloat) -> Set {
        let px = Int(64 * scale)
        let farPx = max(8, Int(10 * scale))      // rendered tiny, scaled up = soft focus
        var nearDraws: [Draw] = []
        var farDraws: [Draw] = []
        switch kind {
        case .snow:
            nearDraws = [clump(1), clump(2), clump(3), clump(4), crystal(0), crystal(1), crystal(2)]
            farDraws = [bokeh(hex(0xFFFFFF, 0.9), ring: false), bokeh(hex(0xEAF2FF, 0.8), ring: true)]
        case .petal:
            nearDraws = [petal(hex(0xFFF3F7), hex(0xF59ABD)), petal(hex(0xFFE9F1), hex(0xEE86AE)), petal(hex(0xFFFFFF), hex(0xF7B2CB)),
                         blossom(hex(0xFFF4F8), hex(0xF5A3C3), hex(0xE2668F))]
            farDraws = [petal(hex(0xFFE3EE), hex(0xF2A0C0))]
        case .spring:
            nearDraws = [dandelion(), dandelion(), dandelion(), youngLeaf(hex(0xB8E47A), hex(0x6DAA45)), youngLeaf(hex(0xD3F09B), hex(0x88BD52))]
            farDraws = [bokeh(hex(0xFFFFFF, 0.75), ring: false)]
        case .flower:
            nearDraws = [blossom(hex(0xFFE08A), hex(0xF4A93B), hex(0xC0661D)),
                         blossom(hex(0xFFB3AA), hex(0xF26A63), hex(0xFFE08A)),
                         blossom(hex(0xE3D0FF), hex(0xA77EF2), hex(0xFFF2A8), round: true),
                         blossom(hex(0xBDE7FF), hex(0x5DB4EE), hex(0xFFFFFF), round: true),
                         daisy()]
            farDraws = [blossom(hex(0xFFD7A8), hex(0xF2A05A), hex(0xC0661D))]
        case .leaf:
            nearDraws = [maple(hex(0xF4A33A), hex(0xD1451E), hex(0x8E2E10, 0.55)),
                         maple(hex(0xF2C14E), hex(0xE07A22), hex(0x9A5612, 0.55)),
                         maple(hex(0xE0542C), hex(0x9C2416), hex(0x5E140A, 0.55)),
                         oak(hex(0xC99A3B), hex(0x8A5A1E), hex(0x5A3810, 0.6), wavy: true),
                         oak(hex(0xF0C24A), hex(0xC98A22), hex(0x7E5512, 0.5), wavy: false)]
            farDraws = [maple(hex(0xE8873A), hex(0xB8441E), hex(0x8E2E10, 0.4))]
        case .rain:
            nearDraws = [bokeh(hex(0xD8ECFA, 0.9), ring: false)]
            farDraws = []
        case .star:
            nearDraws = [sparkle(hex(0xFFE9A8)), sparkle(hex(0xD9C6FF)), sparkle(hex(0xB2DEFF))]
            farDraws = [bokeh(hex(0xE6DCFF, 0.9), ring: false), bokeh(hex(0xFFF1C8, 0.9), ring: false)]
        }
        var out = Set()
        out.near = nearDraws.compactMap { make(px, $0) }
        out.far = farDraws.compactMap { make(farPx, $0) }
        out.streak = streak(px: px, head: kind == .rain ? hex(0xDDEFFC, 0.95) : hex(0xFFFFFF, 0.9))
        out.meteor = streak(px: px * 2, head: hex(0xFFF6DA, 1))
        out.glint = make(Int(24 * scale), sparkle(hex(0xEAF4FF), rays: 22))
        out.drop = make(px, glassDrop())
        return out
    }

    // MARK: frost

    /// Frost creeping in from a corner. The corner is at the image's bottom-left.
    static func frostCorner(size: CGFloat, scale: CGFloat, seed: UInt64) -> CGImage? {
        let px = Int(size * scale)
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: rgbSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        if let g = gradient([hex(0xEAF4FF, 0.55), hex(0xDDEBFA, 0.22), hex(0xFFFFFF, 0)], [0, 0.45, 1]) {
            ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: size, options: [])
        }
        var r = Seeded(seed)
        ctx.setLineCap(.round)
        func branch(_ p: CGPoint, _ ang: CGFloat, _ len: CGFloat, _ depth: Int) {
            guard depth > 0, len > 3 else { return }
            let q = CGPoint(x: p.x + cos(ang) * len, y: p.y + sin(ang) * len)
            let dist = hypot(q.x, q.y) / size
            let a = max(0, 0.75 - dist * 0.85)
            if a <= 0.02 { return }
            ctx.setStrokeColor(hex(0xFFFFFF, a))
            ctx.setLineWidth(max(0.4, CGFloat(depth) * 0.45))
            ctx.move(to: p); ctx.addLine(to: q)
            ctx.strokePath()
            let n = Int(r.range(2, 5))
            for k in 0..<n {
                let t = r.range(0.25, 1)
                let bp = CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t)
                let side: CGFloat = k % 2 == 0 ? 1 : -1
                branch(bp, ang + side * r.range(0.8, 1.15), len * r.range(0.3, 0.55), depth - 1)
            }
            if r.next() < 0.7 { branch(q, ang + r.range(-0.35, 0.35), len * r.range(0.5, 0.8), depth - 1) }
        }
        for i in 0..<34 {
            let along = r.range(0, size * 0.75)
            let onX = i % 2 == 0
            let start = onX ? CGPoint(x: along, y: 0) : CGPoint(x: 0, y: along)
            let ang = onX ? r.range(0.9, 2.0) : r.range(-0.4, 0.7)
            branch(start, ang, r.range(30, 110) * (1 - along / size * 0.6), 4)
        }
        return ctx.makeImage()
    }
}

// MARK: - Drift layer (one per surface per display; redrawn only when the drift changes)

final class PileLayer: CALayer {
    static let below: CGFloat = 30      // room under the edge for icicles
    weak var surface: Surface?
    weak var engine: Engine?
    var season: Season = Season.all[0]
    var sprites: [CGImage] = []
    var drawnVersion = -1
    var room: CGFloat = 60

    override init() {
        super.init()
        actions = noActions
        needsDisplayOnBoundsChange = true
    }
    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(in ctx: CGContext) {
        guard let s = surface, let e = engine else { return }
        PileLayer.drawDrift(ctx, s, e, season, sprites)
    }

    static func drawDrift(_ ctx: CGContext, _ s: Surface, _ e: Engine, _ S: Season, _ sprites: [CGImage]) {
        guard !s.h.isEmpty else { return }
        let base = PileLayer.below
        let n = s.h.count, cw = CGFloat(s.cw)
        func hv(_ i: Int) -> CGFloat { s.visible[i] ? CGFloat(s.h[i]) : 0 }
        var top: CGFloat = 0
        for i in 0..<n { top = max(top, hv(i)) }

        // icicles hang under the edge
        if !s.icicles.isEmpty {
            for ic in s.icicles where ic.c < n && s.visible[ic.c] {
                let cx = (CGFloat(ic.c) + 0.5) * cw, len = CGFloat(ic.len), w = CGFloat(ic.width)
                ctx.saveGState()
                ctx.move(to: CGPoint(x: cx - w / 2, y: base + 1))
                ctx.addQuadCurve(to: CGPoint(x: cx + 0.3, y: base - len), control: CGPoint(x: cx - w * 0.25, y: base - len * 0.45))
                ctx.addQuadCurve(to: CGPoint(x: cx + w / 2, y: base + 1), control: CGPoint(x: cx + w * 0.3, y: base - len * 0.45))
                ctx.closePath()
                ctx.clip()
                if let g = gradient([hex(0xFFFFFF, 0.95), hex(0xD7E9FA, 0.75), hex(0xB5D4F0, 0.45)], [0, 0.5, 1]) {
                    ctx.drawLinearGradient(g, start: CGPoint(x: cx, y: base), end: CGPoint(x: cx, y: base - len), options: [])
                }
                ctx.restoreGState()
                ctx.setStrokeColor(hex(0xFFFFFF, 0.8))
                ctx.setLineWidth(0.6)
                ctx.move(to: CGPoint(x: cx - w * 0.15, y: base - 1)); ctx.addLine(to: CGPoint(x: cx, y: base - len * 0.7))
                ctx.strokePath()
            }
        }

        if top > 0.15 {
            // drift body path
            func bodyPath() {
                ctx.beginPath()
                ctx.move(to: CGPoint(x: 0, y: base))
                for i in 0..<n { ctx.addLine(to: CGPoint(x: (CGFloat(i) + 0.5) * cw, y: base + hv(i))) }
                ctx.addLine(to: CGPoint(x: CGFloat(s.w), y: base))
                ctx.closePath()
            }
            // soft contact shadow on the window
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 4, color: hex(0x000000, S.kind == .rain ? 0.12 : 0.3))
            bodyPath()
            ctx.setFillColor(S.shade.cg)
            ctx.fillPath()
            ctx.restoreGState()
            // shaded body: bright crest down to a cooler base
            ctx.saveGState()
            bodyPath()
            ctx.clip()
            if let g = gradient([S.crest.cg, S.pile.cg, S.shade.cg], [0, 0.45, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: base + top), end: CGPoint(x: 0, y: base), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            // texture: tiny crystals in snow, specks in everything else
            let speck = S.kind == .snow || S.kind == .star ? hex(0xFFFFFF, 0.9) : S.shade.with(alpha: 0.45)
            ctx.setFillColor(speck)
            var i = 0
            while i < n {
                let v = hv(i)
                if v > 2.5 {
                    let h1 = CGFloat(hash01(s.id, i)), h2 = CGFloat(hash01(i, s.id &+ 7))
                    if h1 < 0.45 {
                        let rr: CGFloat = 0.45 + h2 * 0.5
                        ctx.fillEllipse(in: CGRect(x: (CGFloat(i) + h2) * cw - rr, y: base + v * (0.25 + 0.7 * h1 / 0.45) - rr, width: 2 * rr, height: 2 * rr))
                    }
                }
                i += 2
            }
            ctx.restoreGState()
            // crest highlight
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setStrokeColor(S.crest.with(alpha: min(1, S.crest.a)))
            ctx.setLineWidth(1.3)
            var pen = false
            for i in 0..<n {
                let v = hv(i)
                if v > 0.5 {
                    let pt = CGPoint(x: (CGFloat(i) + 0.5) * cw, y: base + v - 0.4)
                    if pen { ctx.addLine(to: pt) } else { ctx.move(to: pt) }
                    pen = true
                } else { pen = false }
            }
            ctx.strokePath()
        }

        // petals / leaves resting on top
        for d in s.decals where d.c < n && s.visible[d.c] && d.y <= s.h[d.c] + 0.5 && d.sprite < sprites.count {
            let size = CGFloat(d.size)
            let cx = (CGFloat(d.c) + 0.5) * cw
            let cy = base + max(CGFloat(d.y), size * 0.28)
            ctx.saveGState()
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: CGFloat(d.rot))
            ctx.scaleBy(x: 1, y: 0.6)       // lying flat
            ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 1.5, color: hex(0x000000, 0.25))
            ctx.draw(sprites[d.sprite], in: CGRect(x: -size / 2, y: -size / 2, width: size, height: size))
            ctx.restoreGState()
        }

        // balls and snowmen
        for b in s.balls {
            let gp = e.ballPos(s, b)
            let r = CGFloat(b.r)
            let c = CGPoint(x: CGFloat(gp.x - s.x), y: base + CGFloat(s.y - gp.y))
            if b.on == nil {
                ctx.setFillColor(hex(0x000000, 0.18))
                ctx.fillEllipse(in: CGRect(x: c.x - r * 0.9, y: base - r * 0.12, width: r * 1.8, height: r * 0.3))
            }
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            ctx.clip()
            if let g = gradient([S.crest.cg, S.pile.cg, S.shade.cg], [0, 0.55, 1]) {
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: c.x - r * 0.35, y: c.y + r * 0.4), startRadius: r * 0.1,
                                       endCenter: c, endRadius: r * 1.05, options: [.drawsAfterEndLocation])
            }
            if S.decalP > 0 && !sprites.isEmpty {
                for i in 0..<7 {
                    let a = CGFloat(b.seed) + CGFloat(i) * 1.9 + CGFloat(b.rot)
                    let rr = r * (0.15 + CGFloat((i * 37) % 10) / 14)
                    let sz = max(6, r * 0.5)
                    ctx.saveGState()
                    ctx.translateBy(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
                    ctx.rotate(by: a)
                    ctx.draw(sprites[(i + Int(b.seed * 10)) % sprites.count], in: CGRect(x: -sz / 2, y: -sz / 2, width: sz, height: sz))
                    ctx.restoreGState()
                }
            }
            ctx.restoreGState()

            let isHead = b.on != nil && !s.balls.contains(where: { $0.on === b })
            if isHead {
                ctx.setFillColor(hex(0x1B1A26))
                let er = max(1.2, r * 0.085)
                ctx.fillEllipse(in: CGRect(x: c.x - r * 0.3 - er, y: c.y + r * 0.18 - er, width: 2 * er, height: 2 * er))
                ctx.fillEllipse(in: CGRect(x: c.x + r * 0.3 - er, y: c.y + r * 0.18 - er, width: 2 * er, height: 2 * er))
                if S.carrot {
                    if let g = gradient([hex(0xFFA14A), hex(0xE5641C)], [0, 1]) {
                        ctx.saveGState()
                        ctx.move(to: CGPoint(x: c.x - r * 0.05, y: c.y + r * 0.04))
                        ctx.addLine(to: CGPoint(x: c.x + r * 0.7, y: c.y - r * 0.1))
                        ctx.addLine(to: CGPoint(x: c.x - r * 0.05, y: c.y - r * 0.2))
                        ctx.closePath()
                        ctx.clip()
                        ctx.drawLinearGradient(g, start: CGPoint(x: c.x, y: c.y), end: CGPoint(x: c.x + r * 0.7, y: c.y), options: [])
                        ctx.restoreGState()
                    }
                    // coal smile
                    ctx.setFillColor(hex(0x1B1A26, 0.85))
                    for k in 0..<5 {
                        let a = CGFloat.pi * (1.2 + 0.15 * CGFloat(k))
                        let pr = max(0.7, r * 0.05)
                        ctx.fillEllipse(in: CGRect(x: c.x + cos(a) * r * 0.45 - pr, y: c.y - r * 0.1 + sin(a) * r * 0.35 - pr, width: 2 * pr, height: 2 * pr))
                    }
                } else {
                    ctx.setStrokeColor(hex(0x1B1A26))
                    ctx.setLineWidth(max(1.1, r * 0.07))
                    ctx.addArc(center: CGPoint(x: c.x, y: c.y - r * 0.02), radius: r * 0.3,
                               startAngle: -0.8 * CGFloat.pi, endAngle: -0.2 * CGFloat.pi, clockwise: false)
                    ctx.strokePath()
                }
            }
        }
    }
}

// MARK: - Pip

final class PipLayer: CALayer {
    static let size = CGSize(width: 260, height: 210)
    static let feet = CGPoint(x: 130, y: 34)
    weak var pip: Pip?
    var art: CritterArt?
    var sprite: SpriteCritter?
    var kind: Kind = .snow
    var wind = 0.0

    override init() {
        super.init()
        actions = noActions
    }
    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(in ctx: CGContext) {
        guard let p = pip else { return }
        ctx.translateBy(x: PipLayer.feet.x, y: PipLayer.feet.y)
        ctx.scaleBy(x: PipArt.scale, y: PipArt.scale)
        if let sp = sprite { PipArt.drawSprite(ctx, p, art: sp, kind: kind, wind: wind, feet: .zero) }
        else if let a = art { PipArt.drawCritter(ctx, p, art: a, kind: kind, wind: wind, feet: .zero) }
        else { PipArt.draw(ctx, p, kind: kind, wind: wind, feet: .zero) }
    }
}

enum PipArt {
    static let scale: CGFloat = 1.2
    static let ink = hex(0x2A2147)
    static let leafHat = Sprites.make(64, Sprites.maple(hex(0xF4A33A), hex(0xD1451E), hex(0x8E2E10, 0.55)))

    // Palette: warm cream fur with lavender shadows, strawberry-milk pinks.
    static let furLight = hex(0xFFFFFF)
    static let furBase = hex(0xFFF8F1)
    static let furMid = hex(0xF4EAF2)
    static let furShadow = hex(0xDCCDEA)
    static let furDeep = hex(0xC6B4DD)
    static let pinkInner = hex(0xFFB3C8)

    /// Short curved hair strands fanned around an ellipse — the fluff.
    static func fur(_ ctx: CGContext, c: CGPoint, rx: CGFloat, ry: CGFloat, count: Int, len: CGFloat, width: CGFloat,
                    color: CGColor, seed: Int, t: CGFloat, from a0: CGFloat = 0, to a1: CGFloat = 2 * CGFloat.pi,
                    inset: CGFloat = 0.82, curl: CGFloat = 0.55) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        for i in 0..<count {
            let h1 = CGFloat(hash01(seed, i)), h2 = CGFloat(hash01(i, seed &+ 11))
            let a = a0 + (a1 - a0) * (CGFloat(i) + h1 * 0.8) / CGFloat(count)
            let ca = cos(a), sa = sin(a)
            let p0 = CGPoint(x: c.x + ca * rx * inset, y: c.y + sa * ry * inset)
            let l = len * (0.65 + 0.7 * h2)
            let p1 = CGPoint(x: c.x + ca * (rx + l), y: c.y + sa * (ry + l))
            // strands curl a little and sway gently
            let sway = sin(t * 2.1 + CGFloat(i) * 0.7) * 0.6
            let side = (h1 > 0.5 ? 1 : -1) * (curl * l + sway)
            let mid = CGPoint(x: (p0.x + p1.x) / 2 - sa * side, y: (p0.y + p1.y) / 2 + ca * side)
            ctx.move(to: p0)
            ctx.addQuadCurve(to: p1, control: mid)
        }
        ctx.strokePath()
    }

    /// Soft overlapping puffs around an ellipse: a cotton-cloud silhouette.
    static func puffs(_ ctx: CGContext, c: CGPoint, rx: CGFloat, ry: CGFloat, count: Int, r: CGFloat, color: CGColor, seed: Int,
                      t: CGFloat, inset: CGFloat = 0.94, from a0: CGFloat = 0, to a1: CGFloat = 2 * CGFloat.pi) {
        ctx.setFillColor(color)
        for i in 0..<count {
            let h1 = CGFloat(hash01(seed, i)), h2 = CGFloat(hash01(i, seed &+ 5))
            let a = a0 + (a1 - a0) * (CGFloat(i) + 0.5 * h1) / CGFloat(count)
            let pr = r * (0.8 + 0.45 * h2) * (1 + 0.04 * sin(t * 2.3 + CGFloat(i)))
            let pc = CGPoint(x: c.x + cos(a) * rx * inset, y: c.y + sin(a) * ry * inset)
            ctx.fillEllipse(in: CGRect(x: pc.x - pr, y: pc.y - pr, width: 2 * pr, height: 2 * pr))
        }
    }

    static func ellipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> CGRect {
        CGRect(x: c.x - rx, y: c.y - ry, width: 2 * rx, height: 2 * ry)
    }

    static func draw(_ ctx: CGContext, _ p: Pip, kind: Kind, wind: Double, feet F: CGPoint) {
        let R: CGFloat = 15
        let hop = CGFloat(p.hop)
        let t = CGFloat(p.time)
        let breathe = 1 + sin(t * 2.3) * 0.018
        let sq = CGFloat(max(-0.3, min(0.5, p.squash)))
        let sx = (1 + sq * 0.55) * breathe, sy = (1 - sq) / breathe
        let dir = CGFloat(p.facing)
        let walking = p.state == .walk || p.state == .build || p.state == .wake
        let wp = CGFloat(p.walkPhase)
        let happy = p.face == .happy || p.state == .pet

        // soft shadow on the ground
        let shK = 1 / (1 + hop / 30)
        if let g = gradient([hex(0x1A1430, 0.28 * shK), hex(0x1A1430, 0)], [0, 1]) {
            ctx.saveGState()
            ctx.translateBy(x: F.x, y: F.y)
            ctx.scaleBy(x: 1, y: 0.24)
            ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 17 * shK, options: [])
            ctx.restoreGState()
        }

        ctx.saveGState()
        ctx.translateBy(x: F.x, y: F.y + hop)
        ctx.scaleBy(x: sx, y: sy)

        let C = CGPoint(x: 0, y: R * 0.95 + 2)      // centre of the round mochi body
        let rx = R * 1.08, ry = R

        // fluffy tail, wagging, behind the body
        let wag = sin(t * (happy ? 12 : 3.2)) * (happy ? 0.45 : 0.18)
        ctx.saveGState()
        ctx.translateBy(x: C.x - dir * rx * 0.78, y: C.y - R * 0.45)
        ctx.rotate(by: -dir * (0.5 + wag))
        let tc = CGPoint(x: -dir * 5, y: 3)
        puffs(ctx, c: tc, rx: 5, ry: 5, count: 9, r: 2.8, color: furShadow, seed: 31, t: t, inset: 0.75)
        ctx.setFillColor(furBase)
        ctx.fillEllipse(in: ellipse(tc, 5.2, 5.2))
        puffs(ctx, c: tc, rx: 4.6, ry: 4.6, count: 8, r: 2.4, color: furBase, seed: 32, t: t, inset: 0.7)
        fur(ctx, c: tc, rx: 5.4, ry: 5.4, count: 12, len: 1.8, width: 0.9, color: hex(0xD8CAE8, 0.8), seed: 33, t: t, inset: 0.95)
        ctx.setFillColor(hex(0xFFFFFF, 0.9))
        ctx.fillEllipse(in: ellipse(CGPoint(x: tc.x - 1.4, y: tc.y + 1.6), 2, 1.6))
        ctx.restoreGState()

        // feet (little round paws with pink beans)
        let lift1 = walking ? max(0, sin(wp)) * 2.4 : 0
        let lift2 = walking ? max(0, -sin(wp)) * 2.4 : 0
        for (i, lx) in [CGFloat(-6.5), 6.5].enumerated() {
            let fy = i == 0 ? lift1 : lift2
            let fc = CGPoint(x: lx + dir * 1, y: 2.4 + fy)
            ctx.setFillColor(furMid)
            ctx.fillEllipse(in: ellipse(fc, 4.6, 3.0))
            ctx.setFillColor(hex(0xFFC2D2, 0.9))
            ctx.fillEllipse(in: ellipse(CGPoint(x: fc.x, y: fc.y - 0.4), 1.5, 1.0))
        }

        // ears: round, fluffy, with tufts — drawn behind the head fur
        let earBob = sin(t * 2.3 + 1) * 0.04 + (p.face == .surprised ? -0.15 : 0) + (p.face == .sleep ? 0.25 : 0)
        for side: CGFloat in [-1, 1] {
            ctx.saveGState()
            ctx.translateBy(x: C.x + side * R * 0.62, y: C.y + R * 0.72)
            ctx.rotate(by: -side * (0.38 + earBob))
            let ec = CGPoint(x: 0, y: 6.5)
            puffs(ctx, c: CGPoint(x: 0, y: 5.5), rx: 4.6, ry: 6.2, count: 9, r: 1.9, color: furShadow, seed: 40 + Int(side), t: t, inset: 0.92,
                  from: -0.2, to: CGFloat.pi + 0.2)
            ctx.move(to: CGPoint(x: -5.6, y: 0))
            ctx.addCurve(to: CGPoint(x: 0, y: 14), control1: CGPoint(x: -6.2, y: 7), control2: CGPoint(x: -3.2, y: 13.5))
            ctx.addCurve(to: CGPoint(x: 5.6, y: 0), control1: CGPoint(x: 3.2, y: 13.5), control2: CGPoint(x: 6.2, y: 7))
            ctx.closePath()
            ctx.setFillColor(furBase)
            ctx.fillPath()
            // inner ear, soft pink gradient
            ctx.saveGState()
            ctx.move(to: CGPoint(x: -3, y: 1.5))
            ctx.addCurve(to: CGPoint(x: 0, y: 10.5), control1: CGPoint(x: -3.4, y: 6), control2: CGPoint(x: -1.8, y: 10))
            ctx.addCurve(to: CGPoint(x: 3, y: 1.5), control1: CGPoint(x: 1.8, y: 10), control2: CGPoint(x: 3.4, y: 6))
            ctx.closePath()
            ctx.clip()
            if let g = gradient([hex(0xFFD6E2), pinkInner], [0, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 10), end: CGPoint(x: 0, y: 1), options: [])
            }
            ctx.restoreGState()
            // white tuft inside the ear
            fur(ctx, c: CGPoint(x: 0, y: 2.5), rx: 1, ry: 1, count: 5, len: 3.4, width: 1.1, color: hex(0xFFFFFF, 0.95), seed: 50 + Int(side), t: t,
                from: 0.35 * CGFloat.pi, to: 0.65 * CGFloat.pi, inset: 0.5, curl: 0.3)
            // soft round puff at the tip
            ctx.setFillColor(furBase)
            ctx.fillEllipse(in: ellipse(CGPoint(x: 0, y: 13.3), 1.9, 1.7))
            ctx.setFillColor(hex(0xFFFFFF, 0.9))
            ctx.fillEllipse(in: ellipse(CGPoint(x: -0.4, y: 13.8), 0.9, 0.7))
            ctx.restoreGState()
        }

        // body: a cotton-cloud silhouette (shadow puffs, body, light puffs), then fine wisps of hair
        puffs(ctx, c: C, rx: rx, ry: ry, count: 30, r: 4.2, color: furShadow, seed: 1, t: t, inset: 0.93)
        puffs(ctx, c: C, rx: rx, ry: ry, count: 14, r: 4.4, color: hex(0xC6B4DD, 0.55), seed: 9, t: t, inset: 0.92,
              from: CGFloat.pi * 1.15, to: CGFloat.pi * 1.85)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: hex(0x3A2A66, 0.2))
        ctx.setFillColor(furMid)
        ctx.fillEllipse(in: ellipse(C, rx, ry))
        ctx.restoreGState()
        puffs(ctx, c: C, rx: rx, ry: ry, count: 28, r: 3.9, color: furBase, seed: 2, t: t, inset: 0.86)
        ctx.saveGState()
        ctx.addEllipse(in: ellipse(C, rx * 0.97, ry * 0.97))
        ctx.clip()
        if let g = gradient([furLight, furBase, furMid, furShadow], [0, 0.45, 0.8, 1]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: C.x - rx * 0.28, y: C.y + ry * 0.4), startRadius: 0.5,
                                   endCenter: CGPoint(x: C.x, y: C.y - ry * 0.1), endRadius: rx * 1.15, options: [.drawsAfterEndLocation])
        }
        // soft fur texture inside
        fur(ctx, c: C, rx: rx * 0.72, ry: ry * 0.72, count: 24, len: 2.4, width: 1.1, color: hex(0xEADFF3, 0.45), seed: 3, t: t,
            from: CGFloat.pi * 1.1, to: CGFloat.pi * 1.9, inset: 0.8, curl: 0.7)
        fur(ctx, c: C, rx: rx * 0.7, ry: ry * 0.7, count: 22, len: 2.4, width: 1.2, color: hex(0xFFFFFF, 0.55), seed: 4, t: t,
            from: CGFloat.pi * 0.15, to: CGFloat.pi * 0.85, inset: 0.8, curl: 0.7)
        ctx.restoreGState()
        // highlight puffs on the upper rim
        puffs(ctx, c: C, rx: rx, ry: ry, count: 9, r: 2.6, color: hex(0xFFFFFF, 0.9), seed: 8, t: t, inset: 0.86,
              from: CGFloat.pi * 0.25, to: CGFloat.pi * 0.75)
        // fine wisps of hair escaping the silhouette
        fur(ctx, c: C, rx: rx, ry: ry, count: 34, len: 1.5, width: 0.8, color: hex(0xD3C3E6, 0.6), seed: 5, t: t, inset: 1.0, curl: 0.5)
        fur(ctx, c: C, rx: rx, ry: ry, count: 16, len: 1.4, width: 0.8, color: hex(0xFFFFFF, 0.8), seed: 6, t: t,
            from: CGFloat.pi * 0.1, to: CGFloat.pi * 0.9, inset: 1.0, curl: 0.8)
        // cheek tufts poking out at the sides
        for side: CGFloat in [-1, 1] {
            let base = side > 0 ? 0.0 : CGFloat.pi
            fur(ctx, c: CGPoint(x: C.x + side * rx * 0.85, y: C.y - R * 0.12), rx: 1, ry: 1, count: 4, len: 3.6, width: 1.8, color: furBase,
                seed: 60 + Int(side), t: t, from: base - 0.45, to: base + 0.45, inset: 0.5, curl: 0.25)
        }
        // fluffy bib on the chest
        fur(ctx, c: CGPoint(x: C.x + dir * 0.8, y: C.y - R * 0.55), rx: 3.5, ry: 2, count: 12, len: 3, width: 1.5, color: hex(0xFFFFFF, 0.95),
            seed: 7, t: t, from: CGFloat.pi * 1.15, to: CGFloat.pi * 1.85, inset: 0.4, curl: 0.4)
        // ahoge: the single curl of hair on top
        ctx.setStrokeColor(furBase)
        ctx.setLineWidth(2)
        ctx.setLineCap(.round)
        let hs = sin(t * 2.6) * 1.2
        let top = CGPoint(x: C.x + dir * 1.5, y: C.y + ry + 1)
        ctx.move(to: top)
        ctx.addCurve(to: CGPoint(x: top.x - dir * 3 + hs, y: top.y + 6.5), control1: CGPoint(x: top.x + dir * 3, y: top.y + 3),
                     control2: CGPoint(x: top.x + dir * 2 + hs, y: top.y + 7.5))
        ctx.strokePath()

        // face
        let shift = dir * 1.5 + CGFloat(p.lookX) * 1.6
        let eyeY = C.y + R * 0.05 - CGFloat(p.lookY) * 1.3
        // blush with little kawaii lines
        for side: CGFloat in [-1, 1] {
            let bc = CGPoint(x: shift + side * 9.2, y: C.y - R * 0.32)
            if let g = gradient([hex(0xFF8FB0, happy ? 0.75 : 0.55), hex(0xFF8FB0, 0)], [0, 1]) {
                ctx.saveGState()
                ctx.translateBy(x: bc.x, y: bc.y)
                ctx.scaleBy(x: 1.5, y: 1)
                ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 3.6, options: [])
                ctx.restoreGState()
            }
            ctx.setStrokeColor(hex(0xF0648E, 0.55))
            ctx.setLineWidth(0.6)
            for k in 0..<3 {
                let x = bc.x - 2 + CGFloat(k) * 1.8
                ctx.move(to: CGPoint(x: x, y: bc.y - 1)); ctx.addLine(to: CGPoint(x: x + 1, y: bc.y + 1))
            }
            ctx.strokePath()
        }

        ctx.setLineCap(.round)
        for side: CGFloat in [-1, 1] {
            let ex = shift + side * 5.6
            switch p.face {
            case .happy, .eat:
                ctx.setStrokeColor(ink); ctx.setLineWidth(1.6)
                ctx.addArc(center: CGPoint(x: ex, y: eyeY - 1.6), radius: 2.6, startAngle: 0.2 * CGFloat.pi, endAngle: 0.8 * CGFloat.pi, clockwise: false)
                ctx.strokePath()
            case .sleep:
                ctx.setStrokeColor(ink); ctx.setLineWidth(1.5)
                ctx.addArc(center: CGPoint(x: ex, y: eyeY + 1.4), radius: 2.5, startAngle: 1.2 * CGFloat.pi, endAngle: 1.8 * CGFloat.pi, clockwise: false)
                ctx.strokePath()
                // lashes
                ctx.setLineWidth(0.8)
                ctx.move(to: CGPoint(x: ex + side * 2.3, y: eyeY - 0.6)); ctx.addLine(to: CGPoint(x: ex + side * 3.4, y: eyeY - 1.4))
                ctx.strokePath()
            case .dizzy:
                ctx.setStrokeColor(ink); ctx.setLineWidth(1)
                var first = true
                for k in 0..<24 {
                    let u = CGFloat(k) / 23
                    let a = u * 4 * CGFloat.pi + t * 8 * side
                    let pt = CGPoint(x: ex + cos(a) * u * 3, y: eyeY + sin(a) * u * 3)
                    if first { ctx.move(to: pt); first = false } else { ctx.addLine(to: pt) }
                }
                ctx.strokePath()
            case .normal, .surprised:
                let big: CGFloat = p.face == .surprised ? 1.12 : 1
                let ew: CGFloat = 3.3 * big, eh = max(0.5, 4.3 * big * (1 - CGFloat(p.blink)))
                if eh < 1.2 {
                    ctx.setStrokeColor(ink); ctx.setLineWidth(1.4)
                    ctx.move(to: CGPoint(x: ex - 2.6, y: eyeY)); ctx.addLine(to: CGPoint(x: ex + 2.6, y: eyeY))
                    ctx.strokePath()
                    continue
                }
                let er = ellipse(CGPoint(x: ex, y: eyeY), ew, eh)
                ctx.saveGState()
                ctx.addEllipse(in: er)
                ctx.clip()
                // deep violet iris, lighter at the bottom: sparkly anime eyes
                if let g = gradient([hex(0x1B1433), hex(0x3B2A6E), hex(0x8C6BD6)], [0, 0.55, 1]) {
                    ctx.drawLinearGradient(g, start: CGPoint(x: ex, y: eyeY + eh), end: CGPoint(x: ex, y: eyeY - eh), options: [])
                }
                if let g = gradient([hex(0xC9B6FF, 0.75), hex(0xC9B6FF, 0)], [0, 1]) {
                    ctx.drawRadialGradient(g, startCenter: CGPoint(x: ex, y: eyeY - eh * 0.7), startRadius: 0,
                                           endCenter: CGPoint(x: ex, y: eyeY - eh * 0.7), endRadius: ew * 0.9, options: [])
                }
                ctx.restoreGState()
                // highlights
                ctx.setFillColor(hex(0xFFFFFF))
                ctx.fillEllipse(in: ellipse(CGPoint(x: ex + ew * 0.32, y: eyeY + eh * 0.38), ew * 0.42, eh * 0.33))
                ctx.setFillColor(hex(0xFFFFFF, 0.9))
                ctx.fillEllipse(in: ellipse(CGPoint(x: ex - ew * 0.38, y: eyeY - eh * 0.42), ew * 0.2, eh * 0.15))
                // a tiny twinkle that comes and goes
                let tw = max(0, sin(t * 1.7 + side))
                if tw > 0.6 {
                    ctx.saveGState()
                    ctx.translateBy(x: ex + ew * 0.05, y: eyeY + eh * 0.05)
                    ctx.scaleBy(x: 0.055 * tw, y: 0.055 * tw)
                    Sprites.sparkle(hex(0xFFFFFF), rays: 20)(ctx)
                    ctx.restoreGState()
                }
                // outer lash flick
                ctx.setStrokeColor(ink); ctx.setLineWidth(0.9)
                ctx.move(to: CGPoint(x: ex + side * ew * 0.85, y: eyeY + eh * 0.55))
                ctx.addLine(to: CGPoint(x: ex + side * (ew + 1.3), y: eyeY + eh * 0.85))
                ctx.strokePath()
            }
        }
        // tiny nose and ω mouth
        let mx = shift, my = C.y - R * 0.3
        ctx.setFillColor(hex(0xF27A9A))
        ctx.fillEllipse(in: ellipse(CGPoint(x: mx, y: my + 1.9), 0.95, 0.65))
        ctx.setStrokeColor(ink)
        ctx.setLineWidth(1)
        switch p.face {
        case .surprised:
            ctx.setFillColor(hex(0x6B2A4A))
            ctx.fillEllipse(in: ellipse(CGPoint(x: mx, y: my - 0.4), 1.3, 1.6))
        case .eat:
            let open: CGFloat = 0.8 + abs(sin(t * 18)) * 1.0
            ctx.setFillColor(hex(0x6B2A4A))
            ctx.fillEllipse(in: ellipse(CGPoint(x: mx, y: my - 0.3), 1.5, open))
        case .sleep:
            ctx.addArc(center: CGPoint(x: mx, y: my + 0.6), radius: 1.1, startAngle: 1.15 * CGFloat.pi, endAngle: 1.85 * CGFloat.pi, clockwise: false)
            ctx.strokePath()
        default:
            ctx.addArc(center: CGPoint(x: mx - 1.25, y: my + 0.8), radius: 1.25, startAngle: 1.05 * CGFloat.pi, endAngle: 1.95 * CGFloat.pi, clockwise: false)
            ctx.strokePath()
            ctx.addArc(center: CGPoint(x: mx + 1.25, y: my + 0.8), radius: 1.25, startAngle: 1.05 * CGFloat.pi, endAngle: 1.95 * CGFloat.pi, clockwise: false)
            ctx.strokePath()
            if happy {
                // little open smile with a pink tongue
                ctx.setFillColor(hex(0xFF7C9C))
                ctx.fillEllipse(in: ellipse(CGPoint(x: mx, y: my - 0.6), 1.2, 0.9))
            }
        }

        // little paws (raised when waving or building)
        let wave = p.state == .wake || p.state == .pet
        for side: CGFloat in [-1, 1] {
            ctx.saveGState()
            ctx.translateBy(x: C.x + side * rx * 0.58, y: C.y - R * 0.52)
            var ang: CGFloat = side * 0.15
            if wave && side == dir { ang = side * (2.3 + 0.45 * sin(t * 14)) }
            else if p.state == .build { ang = side * (0.7 + 0.4 * sin(wp + (side > 0 ? 0 : CGFloat.pi))) }
            else if walking { ang = side * (0.2 + 0.25 * sin(wp + (side > 0 ? 0 : CGFloat.pi))) }
            ctx.rotate(by: ang)
            let pc = CGPoint(x: 0, y: -2.2)
            puffs(ctx, c: pc, rx: 2.4, ry: 2.6, count: 6, r: 1.5, color: furShadow, seed: 70 + Int(side), t: t, inset: 0.8)
            ctx.setFillColor(furBase)
            ctx.fillEllipse(in: ellipse(pc, 2.6, 2.9))
            ctx.setStrokeColor(hex(0xD9C8E8))
            ctx.setLineWidth(0.6)
            ctx.move(to: CGPoint(x: -0.8, y: -4.6)); ctx.addLine(to: CGPoint(x: -0.8, y: -3.4))
            ctx.move(to: CGPoint(x: 0.8, y: -4.6)); ctx.addLine(to: CGPoint(x: 0.8, y: -3.4))
            ctx.strokePath()
            ctx.restoreGState()
        }

        outfit(ctx, kind, C, R, dir, wind, t, walking)
        ctx.restoreGState()

        // happy sparkles drifting around
        if happy {
            for k in 0..<3 {
                let ph = t * 1.4 + CGFloat(k) * 2.1
                let u = ph.truncatingRemainder(dividingBy: 2.2) / 2.2
                let a = CGFloat(k) * 2.2 + 0.6
                let pos = CGPoint(x: F.x + cos(a) * 26, y: F.y + hop + 20 + sin(a) * 14 + u * 10)
                ctx.saveGState()
                ctx.translateBy(x: pos.x, y: pos.y)
                let s = 0.1 * sin(u * CGFloat.pi)
                ctx.scaleBy(x: s, y: s)
                Sprites.sparkle(hex(0xFFE7F0), rays: 20)(ctx)
                ctx.restoreGState()
            }
        }

        effects(ctx, p, F)
        if let text = p.bubble, p.bubbleAlpha > 0.01 {
            bubble(ctx, text, alpha: CGFloat(p.bubbleAlpha), at: CGPoint(x: F.x, y: F.y + hop + 2 * R * sy + 30))
        }
    }

    // MARK: outfits

    static func outfit(_ ctx: CGContext, _ kind: Kind, _ C: CGPoint, _ R: CGFloat, _ dir: CGFloat, _ wind: Double, _ t: CGFloat, _ walking: Bool) {
        switch kind {
        case .snow:
            scarf(ctx, C, R, dir, wind, t, walking, hex(0xF4EEE4), hex(0xB9A9A6))
            beanie(ctx, C, R, t, hex(0xF0788C), hex(0xFFF7F2))
        case .leaf:
            scarf(ctx, C, R, dir, wind, t, walking, hex(0xE8A13C), hex(0xFFF0D6), hi: hex(0xF7C76E), lo: hex(0xB86F1E))
            ctx.saveGState()
            ctx.translateBy(x: C.x + 3, y: C.y + R + 3)
            ctx.rotate(by: -0.4)
            if let leaf = leafHat { ctx.draw(leaf, in: CGRect(x: -10, y: -10, width: 20, height: 20)) }
            ctx.restoreGState()
        case .petal:
            ctx.saveGState()
            ctx.translateBy(x: C.x + 7.5, y: C.y + R * 0.95)
            flower(ctx, r: 2.6, petal: hex(0xFFC2D6), center: hex(0xE0618C))
            ctx.restoreGState()
        case .spring:
            ctx.setStrokeColor(hex(0x5E9E3A))
            ctx.setLineWidth(1.4)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: C.x, y: C.y + R - 1))
            ctx.addQuadCurve(to: CGPoint(x: C.x + 1, y: C.y + R + 8), control: CGPoint(x: C.x - 1.5, y: C.y + R + 4))
            ctx.strokePath()
            ctx.setFillColor(hex(0x86C85A))
            for side: CGFloat in [-1, 1] {
                ctx.saveGState()
                ctx.translateBy(x: C.x + 1, y: C.y + R + 8)
                ctx.rotate(by: side * 0.9 + sin(t * 2) * 0.1)
                ctx.fillEllipse(in: CGRect(x: -2.2, y: 0, width: 4.4, height: 8))
                ctx.restoreGState()
            }
        case .flower:
            let cols: [(UInt32, UInt32)] = [(0xFFD166, 0xE07A1F), (0xFF8FA3, 0xFFE08A), (0xB79CFF, 0xFFF2A8), (0x7FD0FF, 0xFFFFFF)]
            for (k, c) in cols.enumerated() {
                let a = CGFloat.pi * (0.78 - 0.18 * CGFloat(k))
                ctx.saveGState()
                ctx.translateBy(x: C.x + cos(a) * (R + 0.5), y: C.y + sin(a) * (R + 0.5))
                flower(ctx, r: 2.4, petal: hex(c.0), center: hex(c.1))
                ctx.restoreGState()
            }
        case .rain:
            break
        case .star:
            // glowing lantern held out front
            let L = CGPoint(x: C.x + dir * (R + 6), y: C.y - 2)
            if let g = gradient([hex(0xFFE9A8, 0.75), hex(0xFFD36E, 0.25), hex(0xFFD36E, 0)], [0, 0.35, 1]) {
                ctx.drawRadialGradient(g, startCenter: L, startRadius: 0, endCenter: L, endRadius: 20 + sin(t * 3) * 2, options: [])
            }
            ctx.setStrokeColor(hex(0x6B5A3A))
            ctx.setLineWidth(0.9)
            ctx.move(to: CGPoint(x: C.x + dir * R * 0.9, y: C.y)); ctx.addLine(to: CGPoint(x: L.x, y: L.y + 5))
            ctx.strokePath()
            ctx.setFillColor(hex(0xFFF3C4))
            ctx.fillEllipse(in: CGRect(x: L.x - 3, y: L.y - 3.5, width: 6, height: 7))
            ctx.setStrokeColor(hex(0xB08A3E))
            ctx.strokeEllipse(in: CGRect(x: L.x - 3, y: L.y - 3.5, width: 6, height: 7))
        }
    }

    static func flower(_ ctx: CGContext, r: CGFloat, petal: CGColor, center: CGColor) {
        ctx.setFillColor(petal)
        for i in 0..<5 {
            let a = CGFloat(i) * 2 * CGFloat.pi / 5
            ctx.fillEllipse(in: CGRect(x: cos(a) * r - r * 0.75, y: sin(a) * r - r * 0.75, width: r * 1.5, height: r * 1.5))
        }
        ctx.setFillColor(center)
        ctx.fillEllipse(in: CGRect(x: -r * 0.55, y: -r * 0.55, width: r * 1.1, height: r * 1.1))
    }

    static func beanie(_ ctx: CGContext, _ C: CGPoint, _ R: CGFloat, _ t: CGFloat, _ col: CGColor, _ band: CGColor) {
        let y0 = C.y + R * 0.6
        ctx.saveGState()
        ctx.move(to: CGPoint(x: C.x - R * 0.92, y: y0))
        ctx.addCurve(to: CGPoint(x: C.x + R * 0.92, y: y0), control1: CGPoint(x: C.x - R * 0.9, y: y0 + R * 1.25),
                     control2: CGPoint(x: C.x + R * 0.9, y: y0 + R * 1.25))
        ctx.closePath()
        ctx.clip()
        if let g = gradient([hex(0xFFB3C2), col, hex(0xD9566F)], [0, 0.5, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: C.x - R, y: y0 + R), end: CGPoint(x: C.x + R, y: y0), options: [])
        }
        // knit ribs
        ctx.setStrokeColor(hex(0xB8405C, 0.3))
        ctx.setLineWidth(0.7)
        for k in -4...4 {
            let x = C.x + CGFloat(k) * 2.6
            ctx.move(to: CGPoint(x: x, y: y0)); ctx.addLine(to: CGPoint(x: x * 0.85 + C.x * 0.15, y: y0 + R))
        }
        ctx.strokePath()
        ctx.restoreGState()
        // folded band
        let bandRect = CGRect(x: C.x - R * 0.98, y: y0 - 1.8, width: R * 1.96, height: 4.6)
        ctx.setFillColor(band)
        ctx.addPath(CGPath(roundedRect: bandRect, cornerWidth: 2.3, cornerHeight: 2.3, transform: nil))
        ctx.fillPath()
        ctx.setStrokeColor(hex(0xD9CFC2, 0.8))
        ctx.setLineWidth(0.6)
        var x = bandRect.minX + 1.5
        while x < bandRect.maxX - 1 {
            ctx.move(to: CGPoint(x: x, y: bandRect.minY + 0.8)); ctx.addLine(to: CGPoint(x: x, y: bandRect.maxY - 0.8))
            x += 2.2
        }
        ctx.strokePath()
        // pompom
        let pp = CGPoint(x: C.x + sin(t * 3) * 0.6, y: y0 + R * 0.98 + 2)
        if let g = gradient([hex(0xFFFFFF), hex(0xE7E1DA)], [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: pp.x - 1, y: pp.y + 1), startRadius: 0, endCenter: pp, endRadius: 3.6, options: [])
        }
    }

    /// A chunky knitted scarf: wrapped around the neck, knotted at one side with a tail hanging down.
    static func scarf(_ ctx: CGContext, _ C: CGPoint, _ R: CGFloat, _ dir: CGFloat, _ wind: Double, _ t: CGFloat, _ walking: Bool, _ col: CGColor, _ stripe: CGColor,
                      hi: CGColor = hex(0xFFFDF8), lo: CGColor = hex(0xD8D0C4)) {
        let y = C.y - R * 0.8
        let knot = CGPoint(x: C.x + dir * R * 0.36, y: y - 0.6)
        // hanging tail, fluttering a little
        let flutter = sin(t * (walking ? 9 : 3.5)) * (walking ? 0.12 : 0.05) - CGFloat(wind) * 0.06
        ctx.saveGState()
        ctx.translateBy(x: knot.x, y: knot.y)
        ctx.rotate(by: dir * 0.18 + flutter)
        let tail = CGRect(x: -2.5, y: -9.5, width: 5.0, height: 9.5)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -0.6), blur: 1.5, color: hex(0x000000, 0.25))
        ctx.addPath(CGPath(roundedRect: tail, cornerWidth: 1.6, cornerHeight: 1.6, transform: nil))
        ctx.setFillColor(col)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: tail, cornerWidth: 1.6, cornerHeight: 1.6, transform: nil))
        ctx.clip()
        knit(ctx, tail, col, hi, lo)
        ctx.restoreGState()
        // fringe
        ctx.setStrokeColor(lo); ctx.setLineWidth(0.5); ctx.setLineCap(.round)
        var fx = tail.minX + 0.6
        while fx < tail.maxX - 0.3 { ctx.move(to: CGPoint(x: fx, y: tail.minY + 0.2)); ctx.addLine(to: CGPoint(x: fx + 0.1, y: tail.minY - 1.3)); fx += 1.0 }
        ctx.strokePath()
        // a small embroidered stripe
        ctx.setStrokeColor(stripe); ctx.setLineWidth(0.6)
        ctx.move(to: CGPoint(x: tail.minX + 0.8, y: tail.minY + 3)); ctx.addLine(to: CGPoint(x: tail.maxX - 0.8, y: tail.minY + 3))
        ctx.strokePath()
        ctx.restoreGState()

        // the wrap around the neck, curving with the body
        ctx.saveGState()
        ctx.move(to: CGPoint(x: C.x - R * 0.8, y: y + 2.2))
        ctx.addQuadCurve(to: CGPoint(x: C.x + R * 0.8, y: y + 2.2), control: CGPoint(x: C.x, y: y + 0.6))
        ctx.addLine(to: CGPoint(x: C.x + R * 0.74, y: y - 2.2))
        ctx.addQuadCurve(to: CGPoint(x: C.x - R * 0.74, y: y - 2.2), control: CGPoint(x: C.x, y: y - 4.6))
        ctx.closePath()
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 2, color: hex(0x000000, 0.25))
        ctx.setFillColor(col)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.move(to: CGPoint(x: C.x - R * 0.8, y: y + 2.2))
        ctx.addQuadCurve(to: CGPoint(x: C.x + R * 0.8, y: y + 2.2), control: CGPoint(x: C.x, y: y + 0.6))
        ctx.addLine(to: CGPoint(x: C.x + R * 0.74, y: y - 2.2))
        ctx.addQuadCurve(to: CGPoint(x: C.x - R * 0.74, y: y - 2.2), control: CGPoint(x: C.x, y: y - 4.6))
        ctx.closePath()
        ctx.clip()
        knit(ctx, CGRect(x: C.x - R, y: y - 5, width: 2 * R, height: 8), col, hi, lo, curve: true, cx: C.x, R: R)
        ctx.restoreGState()

        // knot
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -0.6), blur: 1.2, color: hex(0x000000, 0.3))
        ctx.setFillColor(col)
        ctx.fillEllipse(in: CGRect(x: knot.x - 2.6, y: knot.y - 2.3, width: 5.2, height: 4.4))
        ctx.restoreGState()
        if let g = gradient([hi, col, lo], [0, 0.5, 1]) {
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: knot.x - 2.6, y: knot.y - 2.3, width: 5.2, height: 4.4))
            ctx.clip()
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: knot.x - 0.8, y: knot.y + 1), startRadius: 0, endCenter: knot, endRadius: 3.2, options: [.drawsAfterEndLocation])
            ctx.setStrokeColor(lo.copyAlpha(0.6)); ctx.setLineWidth(0.35)
            for k in 0..<3 {
                let a = CGFloat(k) * 0.9 - 0.9
                ctx.move(to: CGPoint(x: knot.x + cos(a) * 2.2, y: knot.y + sin(a) * 2.0))
                ctx.addQuadCurve(to: CGPoint(x: knot.x - cos(a) * 2.2, y: knot.y - sin(a) * 2.0), control: CGPoint(x: knot.x + 0.6, y: knot.y + 0.4))
            }
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    /// Knit texture: rows of little V-shaped stitches with soft shading.
    static func knit(_ ctx: CGContext, _ r: CGRect, _ col: CGColor, _ hi: CGColor, _ lo: CGColor, curve: Bool = false, cx: CGFloat = 0, R: CGFloat = 1) {
        if let g = gradient([hi, col, lo], [0, 0.55, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: r.minX, y: r.maxY), end: CGPoint(x: r.maxX, y: r.minY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        let sw: CGFloat = 1.1, sh: CGFloat = 1.0
        ctx.setLineCap(.round)
        for (color, dy, w) in [(lo.copyAlpha(0.55), -0.12, CGFloat(0.42)), (hi.copyAlpha(0.8), 0.1, CGFloat(0.3))] {
            ctx.setStrokeColor(color)
            ctx.setLineWidth(w)
            var y = r.minY
            while y < r.maxY + sh {
                var x = r.minX
                while x < r.maxX + sw {
                    let bend = curve ? -pow((x - cx) / R, 2) * 1.6 : 0
                    let yy = y + bend + dy
                    ctx.move(to: CGPoint(x: x - sw * 0.45, y: yy + sh * 0.45))
                    ctx.addLine(to: CGPoint(x: x, y: yy - sh * 0.35))
                    ctx.addLine(to: CGPoint(x: x + sw * 0.45, y: yy + sh * 0.45))
                    x += sw
                }
                y += sh
            }
            ctx.strokePath()
        }
    }

    static func umbrella(_ ctx: CGContext, _ C: CGPoint, _ R: CGFloat, _ dir: CGFloat, _ wind: Double, _ t: CGFloat) {
        let tilt = -CGFloat(wind) * 0.08 + sin(t * 1.7) * 0.03
        ctx.saveGState()
        ctx.translateBy(x: C.x + dir * R * 0.75, y: C.y - 2)
        ctx.rotate(by: tilt)
        ctx.setStrokeColor(hex(0x5B4A3A))
        ctx.setLineWidth(1.2)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: 0, y: 0)); ctx.addLine(to: CGPoint(x: 0, y: R * 2.4))
        ctx.strokePath()
        // canopy
        let top = CGPoint(x: 0, y: R * 2.4)
        let w: CGFloat = 23
        ctx.saveGState()
        ctx.move(to: CGPoint(x: -w, y: top.y))
        ctx.addCurve(to: CGPoint(x: w, y: top.y), control1: CGPoint(x: -w, y: top.y + 19), control2: CGPoint(x: w, y: top.y + 19))
        for k in 0..<5 {
            let x0 = w - CGFloat(k) * (2 * w / 5)
            ctx.addQuadCurve(to: CGPoint(x: x0 - 2 * w / 5, y: top.y), control: CGPoint(x: x0 - w / 5, y: top.y + 3.5))
        }
        ctx.closePath()
        ctx.clip()
        if let g = gradient([hex(0x6FD3C4), hex(0x2E9C8F)], [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: top.y + 15), end: CGPoint(x: 0, y: top.y), options: [])
        }
        ctx.setFillColor(hex(0xFFFFFF, 0.25))
        ctx.fill(CGRect(x: -w / 5, y: top.y - 1, width: 2 * w / 5, height: 20))
        ctx.restoreGState()
        ctx.setFillColor(hex(0x2E9C8F))
        ctx.fillEllipse(in: CGRect(x: -1.5, y: top.y + 13.5, width: 3, height: 4))
        ctx.restoreGState()
    }

    // MARK: effects & speech

    static func effects(_ ctx: CGContext, _ p: Pip, _ F: CGPoint) {
        for e in p.effects {
            let a = CGFloat(max(0, min(1, e.life / e.maxLife * 1.6)))
            let pos = CGPoint(x: F.x + CGFloat(e.x), y: F.y - CGFloat(e.y))
            let k = CGFloat(1 - e.life / e.maxLife)
            switch e.kind {
            case .heart:
                let s: CGFloat = 4 + k * 2.5
                ctx.saveGState()
                ctx.translateBy(x: pos.x, y: pos.y)
                ctx.rotate(by: CGFloat(e.spin) * 0.3)
                ctx.move(to: CGPoint(x: 0, y: -s))
                ctx.addCurve(to: CGPoint(x: 0, y: s * 0.55), control1: CGPoint(x: -s * 1.6, y: -s * 0.1), control2: CGPoint(x: -s * 0.7, y: s * 1.3))
                ctx.addCurve(to: CGPoint(x: 0, y: -s), control1: CGPoint(x: s * 0.7, y: s * 1.3), control2: CGPoint(x: s * 1.6, y: -s * 0.1))
                ctx.closePath()
                ctx.setFillColor(hex(0xFF5C7A, a))
                ctx.fillPath()
                ctx.restoreGState()
            case .z:
                text(ctx, "z", at: pos, size: 9 + k * 6, color: hex(0x5C6B9A, a * 0.9), weight: .bold)
            case .bang:
                text(ctx, "!", at: pos, size: 16, color: hex(0xFF7A3D, a), weight: .heavy)
            case .sparkle:
                ctx.saveGState()
                ctx.translateBy(x: pos.x, y: pos.y)
                ctx.scaleBy(x: 0.22, y: 0.22)
                ctx.setAlpha(a)
                Sprites.sparkle(hex(0xFFF1B0), rays: 18)(ctx)
                ctx.restoreGState()
            }
        }
    }

    static func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let d = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { return f }
        return base
    }

    static func line(_ s: String, size: CGFloat, color: CGColor, weight: NSFont.Weight) -> CTLine {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font(size, weight),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs) as CFAttributedString)
    }

    static func text(_ ctx: CGContext, _ s: String, at p: CGPoint, size: CGFloat, color: CGColor, weight: NSFont.Weight) {
        let l = line(s, size: size, color: color, weight: weight)
        let w = CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil))
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: p.x - w / 2, y: p.y - size * 0.35)
        CTLineDraw(l, ctx)
    }

    static func bubble(_ ctx: CGContext, _ s: String, alpha: CGFloat, at p: CGPoint) {
        let size: CGFloat = 12
        let l = line(s, size: size, color: hex(0x2A2638, alpha), weight: .semibold)
        let w = CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil))
        let box = CGRect(x: p.x - w / 2 - 9, y: p.y, width: w + 18, height: 22)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 5, color: hex(0x10142A, 0.3 * alpha))
        ctx.setFillColor(hex(0xFFFFFF, 0.96 * alpha))
        ctx.addPath(CGPath(roundedRect: box, cornerWidth: 11, cornerHeight: 11, transform: nil))
        ctx.fillPath()
        ctx.move(to: CGPoint(x: p.x - 5, y: p.y + 1))
        ctx.addLine(to: CGPoint(x: p.x - 1, y: p.y - 6))
        ctx.addLine(to: CGPoint(x: p.x + 4, y: p.y + 1))
        ctx.closePath()
        ctx.fillPath()
        ctx.restoreGState()
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: box.minX + 9, y: box.minY + 7)
        CTLineDraw(l, ctx)
    }
}
