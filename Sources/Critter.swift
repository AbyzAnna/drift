// Critter.swift — Pip as a realistic plush baby animal, front-facing with chibi proportions:
// a big round head on a round body, short dense velvety fur with soft natural markings,
// tiny glossy eyes, little arms that wave, and feet that waddle.
// The coat (tens of thousands of fine hairs) is rendered once per species; each frame only composes
// those images and draws the living parts: eyes and lids, beak or nose, mouth, whiskers, arms and feet.
// Units: Pip-space points, y up, origin between the feet.

import Cocoa

enum Species: String, CaseIterable {
    case bunny, penguin, lamb, otter, seal, hedgehog
    var label: String {
        switch self {
        case .bunny: return "Bunny"
        case .penguin: return "Penguin chick"
        case .lamb: return "Lamb"
        case .otter: return "Otter pup"
        case .seal: return "Seal pup"
        case .hedgehog: return "Hedgehog"
        }
    }
}

/// A pre-rendered image placed at `rect` in its own coordinate space.
struct Part {
    var image: CGImage?
    var rect: CGRect = .zero
    func draw(_ ctx: CGContext) {
        guard let img = image else { return }
        ctx.draw(img, in: rect)
    }
    /// Draws the part so that its point `pivot` lands at `at`, rotated and scaled around it.
    func draw(_ ctx: CGContext, pivot: CGPoint, at: CGPoint, rotate: CGFloat = 0, sx: CGFloat = 1, sy: CGFloat = 1) {
        guard image != nil else { return }
        ctx.saveGState()
        ctx.translateBy(x: at.x, y: at.y)
        if rotate != 0 { ctx.rotate(by: rotate) }
        if sx != 1 || sy != 1 { ctx.scaleBy(x: sx, y: sy) }
        ctx.translateBy(x: -pivot.x, y: -pivot.y)
        draw(ctx)
        ctx.restoreGState()
    }
}

/// A rotated ellipse: the building block of the anatomy.
struct Blob {
    var c: CGPoint
    var rx: CGFloat
    var ry: CGFloat
    var rot: CGFloat = 0

    init(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat, rot: CGFloat = 0) {
        c = CGPoint(x: x, y: y); self.rx = rx; self.ry = ry; self.rot = rot
    }
    func uv(_ p: CGPoint) -> CGPoint {
        let dx = p.x - c.x, dy = p.y - c.y
        let cs = cos(-rot), sn = sin(-rot)
        return CGPoint(x: (dx * cs - dy * sn) / rx, y: (dx * sn + dy * cs) / ry)
    }
    func dist(_ p: CGPoint) -> CGFloat { let q = uv(p); return sqrt(q.x * q.x + q.y * q.y) }
    func contains(_ p: CGPoint, grow: CGFloat = 1) -> Bool { dist(p) <= grow }
    func point(_ u: CGFloat, _ a: CGFloat) -> CGPoint {
        let x = cos(a) * rx * u, y = sin(a) * ry * u
        return CGPoint(x: c.x + x * cos(rot) - y * sin(rot), y: c.y + x * sin(rot) + y * cos(rot))
    }
    func normal(_ a: CGFloat) -> CGPoint {
        let nx = cos(a) / rx, ny = sin(a) / ry
        let m = max(0.0001, sqrt(nx * nx + ny * ny))
        let x = nx / m, y = ny / m
        return CGPoint(x: x * cos(rot) - y * sin(rot), y: x * sin(rot) + y * cos(rot))
    }
    func addPath(_ ctx: CGContext, grow: CGFloat = 1) {
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: rot)
        ctx.addEllipse(in: CGRect(x: -rx * grow, y: -ry * grow, width: 2 * rx * grow, height: 2 * ry * grow))
        ctx.restoreGState()
    }
}

/// A soft colour patch on the coat (a penguin's white cheeks, an otter's cream face…).
struct Marking {
    var blobs: [Blob]
    var pal: [CGColor]
    var soft: CGFloat = 0.3          // width of the blended edge, in blob radii
    func weight(_ p: CGPoint) -> CGFloat {
        var w: CGFloat = 0
        for b in blobs { w = max(w, min(1, max(0, (1 + soft / 2 - b.dist(p)) / soft))) }
        return w
    }
}

final class CritterArt {
    let species: Species
    var body = Part()
    var head = Part()
    var arm = Part()                       // right arm; mirrored for the left
    var foot = Part()                      // right foot; mirrored for the left

    // Layout (Pip units)
    var headC = CGPoint(x: 0, y: 24.5)
    var headR: CGFloat = 11
    var neck = CGPoint(x: 0, y: 15)
    var shoulder = CGPoint(x: 8.6, y: 15.5)
    var armPivot = CGPoint.zero
    var armRest: CGFloat = 0.12
    var footAt = CGPoint(x: 4.4, y: 1.4)
    // face (head space, head centre at the origin)
    var eyeX: CGFloat = 4.4, eyeY: CGFloat = 1.2, eyeR: CGFloat = 1.4
    var noseAt = CGPoint(x: 0, y: -2.2)
    var beak = false
    var noseW: CGFloat = 1.8, noseH: CGFloat = 1.3
    var noseTop = hex(0xF1A9B3), noseBottom = hex(0xC9707F), nostril = hex(0x8E3E50, 0.85)
    var mouthDark = hex(0xB07A80)
    var whiskers: CGFloat = 0
    var whiskerColor = hex(0xFFFFFF, 0.65)
    var furColor = hex(0xF4EFE8)           // eyelids
    var lidShade = hex(0xD8CEC4)
    var blush: CGFloat = 0.18

    init(_ s: Species, k: CGFloat) {
        species = s
        switch s {
        case .penguin: penguin(k)
        case .bunny, .lamb: lamb(k)
        case .otter: otter(k)
        case .seal: seal(k)
        case .hedgehog: hedgehog(k)
        }
    }

    // MARK: - Rendering helpers

    static func render(_ box: CGRect, k: CGFloat, _ draw: (CGContext) -> Void) -> Part {
        let pw = max(4, Int(box.width * k)), ph = max(4, Int(box.height * k))
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: rgbSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return Part() }
        ctx.scaleBy(x: CGFloat(pw) / box.width, y: CGFloat(ph) / box.height)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        draw(ctx)
        return Part(image: ctx.makeImage(), rect: box)
    }

    static func pal(_ v: [UInt32], _ a: CGFloat = 0.9) -> [CGColor] { v.map { hex($0, a) } }

    static func smooth(_ keys: [CGColor], steps: Int, alpha: CGFloat) -> [CGColor] {
        let comps = keys.map { $0.components ?? [0, 0, 0, 1] }
        guard comps.count > 1 else { return keys }
        var out: [CGColor] = []
        for i in 0..<steps {
            let u = CGFloat(i) / CGFloat(steps - 1) * CGFloat(comps.count - 1)
            let a = min(comps.count - 2, Int(u)), f = u - CGFloat(a)
            let c0 = comps[a], c1 = comps[a + 1]
            let al = min(c0[3], c1[3]) * alpha / 0.9
            out.append(CGColor(red: c0[0] + (c1[0] - c0[0]) * f, green: c0[1] + (c1[1] - c0[1]) * f,
                               blue: c0[2] + (c1[2] - c0[2]) * f, alpha: min(1, al)))
        }
        return out
    }

    static let light = CGPoint(x: -0.45, y: 0.89)

    /// Shaded underlayer so no gaps show between hairs.
    static func base(_ ctx: CGContext, _ b: Blob, _ pal: [CGColor], grow: CGFloat = 0.97) {
        ctx.saveGState()
        b.addPath(ctx, grow: grow)
        ctx.clip()
        let hl = b.point(0.55, CGFloat.pi * 0.62)
        let dk = b.point(0.6, CGFloat.pi * 1.6)
        if let g = gradient([pal[pal.count - 1], pal[pal.count / 2], pal[0]], [0, 0.5, 1]) {
            ctx.drawRadialGradient(g, startCenter: hl, startRadius: 0, endCenter: dk, endRadius: max(b.rx, b.ry) * 1.5, options: [.drawsAfterEndLocation])
        }
        ctx.restoreGState()
    }

    /// Velvety plush coat: dense short hairs pointing outward and a little down, lit from the top-left,
    /// with markings blended in hair by hair so their edges look natural. Hairs at the outline are
    /// longer, which gives the soft fuzzy silhouette.
    static func plush(_ ctx: CGContext, _ b: Blob, pal: [CGColor], marks: [Marking] = [], density: CGFloat, len: CGFloat,
                      seed: UInt64, droop: CGFloat = 0.3, edge: CGFloat = 1.5, width: CGFloat = 0.2, keep: ((CGPoint) -> Bool)? = nil) {
        base(ctx, b, pal)
        if !marks.isEmpty {
            ctx.saveGState()
            b.addPath(ctx, grow: 0.97)
            ctx.clip()
            for m in marks {
                let mid = m.pal[m.pal.count * 2 / 3]
                for mb in m.blobs {
                    ctx.saveGState()
                    ctx.translateBy(x: mb.c.x, y: mb.c.y)
                    ctx.rotate(by: mb.rot)
                    ctx.scaleBy(x: 1, y: mb.ry / mb.rx)
                    if let g = gradient([mid, mid, mid.copyAlpha(0)], [0, 0.78, 1]) {
                        ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: mb.rx * (1 + m.soft / 2), options: [])
                    }
                    ctx.restoreGState()
                }
            }
            ctx.restoreGState()
        }

        var r = Seeded(seed)
        let regions = [smooth(pal, steps: 10, alpha: 0.6)] + marks.map { smooth($0.pal, steps: 10, alpha: 0.6) }
        let nb = 10
        var paths = [[CGPoint]](repeating: [], count: regions.count * nb * 2)
        let count = Int(CGFloat.pi * b.rx * b.ry * density * 1.7)
        for _ in 0..<count {
            let u = sqrt(r.next())
            let a = r.next() * 2 * CGFloat.pi
            let p = b.point(u, a)
            if let k = keep, !k(p) { continue }
            var reg = 0
            let pick = r.next()
            for (i, m) in marks.enumerated().reversed() where pick < m.weight(p) { reg = i + 1; break }
            let n = b.normal(a)
            let rim = u * u * u
            var dx = n.x * (0.35 + u), dy = n.y * (0.35 + u) - droop
            let mm = max(0.001, sqrt(dx * dx + dy * dy)); dx /= mm; dy /= mm
            let L = len * (0.6 + 0.8 * r.next()) * (1 + edge * 0.55 * rim)
            var s = 0.56 + 0.42 * (n.x * light.x + n.y * light.y) * u - 0.24 * rim + 0.24 * (r.next() - 0.5)
            s = min(0.999, max(0, s))
            let ci = Int(s * CGFloat(nb))
            let wi = r.next() < 0.5 ? 0 : 1
            let q = CGPoint(x: p.x + dx * L, y: p.y + dy * L)
            let side = (r.next() - 0.5) * 0.35 * L
            let mid = CGPoint(x: (p.x + q.x) / 2 - dy * side, y: (p.y + q.y) / 2 + dx * side)
            paths[(reg * nb + ci) * 2 + wi].append(contentsOf: [p, mid, q])
        }
        ctx.setLineCap(.round)
        for i in 0..<paths.count where !paths[i].isEmpty {
            let reg = i / (nb * 2), ci = (i / 2) % nb
            ctx.setStrokeColor(regions[reg][ci])
            ctx.setLineWidth(width * (i % 2 == 0 ? 0.8 : 1.25))
            let pts = paths[i]
            var j = 0
            while j + 2 < pts.count {
                ctx.move(to: pts[j]); ctx.addQuadCurve(to: pts[j + 2], control: pts[j + 1])
                j += 3
            }
            ctx.strokePath()
        }
    }

    /// Lamb's wool: tight little curls.
    static func wool(_ ctx: CGContext, _ b: Blob, pal keys: [CGColor], density: CGFloat, size: CGFloat, seed: UInt64) {
        var r = Seeded(seed)
        let pal = smooth(keys, steps: 9, alpha: 0.85)
        let nb = pal.count
        let count = Int(CGFloat.pi * b.rx * b.ry * density)
        var arcs = [[(CGPoint, CGFloat, CGFloat)]](repeating: [], count: nb)
        for _ in 0..<count {
            let u = pow(r.next(), 0.45) * 1.04
            let a = r.next() * 2 * CGFloat.pi
            let p = b.point(u, a)
            let n = b.normal(a)
            var s = 0.56 + 0.4 * (n.x * light.x + n.y * light.y) * min(1, u) - 0.18 * u * u * u + 0.32 * (r.next() - 0.5)
            s = min(0.999, max(0, s))
            arcs[Int(s * CGFloat(nb))].append((p, size * (0.55 + 0.7 * r.next()), r.next() * 2 * CGFloat.pi))
        }
        ctx.setLineCap(.round)
        ctx.setLineWidth(0.4)
        for i in 0..<nb where !arcs[i].isEmpty {
            ctx.setStrokeColor(pal[i])
            for (p, rr, a0) in arcs[i] {
                ctx.move(to: CGPoint(x: p.x + cos(a0) * rr, y: p.y + sin(a0) * rr))
                ctx.addArc(center: p, radius: rr, startAngle: a0, endAngle: a0 + 1.5 * CGFloat.pi, clockwise: false)
            }
            ctx.strokePath()
        }
    }

    /// Soft dark shadow (contact or ambient occlusion).
    static func shadow(_ ctx: CGContext, _ b: Blob, alpha: CGFloat) {
        guard let g = gradient([hex(0x1E1610, alpha), hex(0x1E1610, 0)], [0, 1]) else { return }
        ctx.saveGState()
        ctx.translateBy(x: b.c.x, y: b.c.y)
        ctx.rotate(by: b.rot)
        ctx.scaleBy(x: 1, y: b.ry / b.rx)
        ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: b.rx, options: [])
        ctx.restoreGState()
    }

    /// Hedgehog quills fanning out around an ellipse (behind the face), each banded cream and brown with a pale tip.
    static func quills(_ ctx: CGContext, around b: Blob, from a0: CGFloat, to a1: CGFloat, count: Int, len: CGFloat, seed: UInt64) {
        var r = Seeded(seed)
        struct Q { var p: CGPoint; var q: CGPoint; var b: [CGFloat]; var dark: Bool; var u: CGFloat }
        var list: [Q] = []
        for _ in 0..<count {
            let a = a0 + (a1 - a0) * r.next()
            let u = 0.62 + 0.42 * r.next()
            let p = b.point(u, a)
            let n = b.normal(a)
            let jit = (r.next() - 0.5) * 0.32
            var dx = n.x * cos(jit) - n.y * sin(jit), dy = n.x * sin(jit) + n.y * cos(jit) + 0.35
            let m = max(0.001, sqrt(dx * dx + dy * dy)); dx /= m; dy /= m
            let L = len * (0.65 + 0.5 * r.next()) * (0.7 + 0.5 * (u - 0.62) / 0.42)
            let bands: [CGFloat] = [0.12 + 0.18 * r.next(), 0.45 + 0.15 * r.next(), 0.74 + 0.14 * r.next()]
            list.append(Q(p: p, q: CGPoint(x: p.x + dx * L, y: p.y + dy * L), b: bands, dark: r.next() < 0.3, u: u))
        }
        list.sort { $0.u > $1.u }          // outer quills behind, inner ones on top
        ctx.setLineCap(.round)
        let slices = 6
        for sIdx in 0..<slices {
            let lo = list.count * sIdx / slices, hi = list.count * (sIdx + 1) / slices
            if lo >= hi { continue }
            let layers: [(UInt32, UInt32, CGFloat, Int, Int)] = [
                (0x3A2B21, 0x2B1F17, 0.46, -1, 3), (0xE3D6C1, 0x6B5242, 0.38, 0, 1), (0x4C382B, 0x3A2A20, 0.34, 1, 2), (0xF3ECE1, 0xE9E0D2, 0.26, 2, 3),
            ]
            for (lightC, darkC, w, from, to) in layers {
                for isDark in [false, true] {
                    ctx.setStrokeColor(hex(isDark ? darkC : lightC, 0.95))
                    ctx.setLineWidth(w)
                    for i in lo..<hi where list[i].dark == isDark {
                        let qd = list[i]
                        let s0: CGFloat = from < 0 ? 0 : qd.b[from]
                        let s1: CGFloat = to >= 3 ? 1 : qd.b[to]
                        ctx.move(to: CGPoint(x: qd.p.x + (qd.q.x - qd.p.x) * s0, y: qd.p.y + (qd.q.y - qd.p.y) * s0))
                        ctx.addLine(to: CGPoint(x: qd.p.x + (qd.q.x - qd.p.x) * s1, y: qd.p.y + (qd.q.y - qd.p.y) * s1))
                    }
                    ctx.strokePath()
                }
            }
        }
    }

    /// A small fluffy limb (arm, flipper or paw), hanging from a pivot at (0, 0).
    static func limb(_ k: CGFloat, blob: Blob, pal: [CGColor], seed: UInt64, len: CGFloat = 0.55, toes: CGColor? = nil) -> Part {
        let m = max(blob.rx, blob.ry)
        let box = CGRect(x: blob.c.x - m - 2.5, y: blob.c.y - m - 2.5, width: 2 * m + 5, height: 2 * m + 5)
        return render(box, k: k) { ctx in
            plush(ctx, blob, pal: pal, density: 30, len: len, seed: seed, droop: 0.35, edge: 1.4)
            if let t = toes {
                ctx.setStrokeColor(t); ctx.setLineWidth(0.22); ctx.setLineCap(.round)
                for i in 0..<3 {
                    let p = blob.point(0.92, -CGFloat.pi / 2 + (CGFloat(i) - 1) * 0.35)
                    ctx.move(to: p); ctx.addLine(to: CGPoint(x: p.x + (p.x - blob.c.x) * 0.12, y: p.y + 0.9))
                }
                ctx.strokePath()
            }
        }
    }

    // MARK: - Penguin chick (emperor)

    private func penguin(_ k: CGFloat) {
        let charcoal = CritterArt.pal([0x141416, 0x232327, 0x34343A, 0x48484F, 0x5E5E66])
        let white = CritterArt.pal([0xB9B8B6, 0xD9D8D5, 0xECEBE8, 0xF7F6F3, 0xFFFFFF])
        let down = CritterArt.pal([0x8D8B89, 0xA9A7A4, 0xC2C0BD, 0xD6D4D1, 0xE6E4E1])
        let belly = CritterArt.pal([0xA6A4A1, 0xC3C1BE, 0xD7D5D2, 0xE6E4E1, 0xF1EFEC])
        headC = CGPoint(x: 0, y: 25); headR = 11
        neck = CGPoint(x: 0, y: 16)
        eyeX = 4.6; eyeY = 0.4; eyeR = 1.35
        noseAt = CGPoint(x: 0, y: -2.0); beak = true
        furColor = hex(0xF2F1EE); lidShade = hex(0x9A9895)
        blush = 0.1

        body = CritterArt.render(CGRect(x: -15, y: -2, width: 30, height: 26), k: k) { ctx in
            let b = Blob(0, 10.5, 11.2, 10.4)
            CritterArt.plush(ctx, b, pal: down, marks: [Marking(blobs: [Blob(0, 9, 7.2, 7.6)], pal: belly, soft: 0.5)],
                             density: 34, len: 0.85, seed: 1, droop: 0.4, edge: 1.7)
            CritterArt.shadow(ctx, Blob(0, 19.2, 9.5, 2.6), alpha: 0.28)
        }
        head = CritterArt.render(CGRect(x: -15, y: -14, width: 30, height: 29), k: k) { ctx in
            let h = Blob(0, 0, 11, 10.4)
            let cheeks = Marking(blobs: [Blob(-5.4, -1.4, 4.5, 5.6, rot: 0.28), Blob(5.4, -1.4, 4.5, 5.6, rot: -0.28)], pal: white, soft: 0.35)
            CritterArt.plush(ctx, h, pal: charcoal, marks: [cheeks], density: 36, len: 0.75, seed: 2, droop: 0.2, edge: 1.6)
        }
        arm = CritterArt.limb(k, blob: Blob(1.6, -4.8, 2.7, 5.2, rot: 0.32), pal: down, seed: 3, len: 0.7)
        armRest = 0.15
        shoulder = CGPoint(x: 8.8, y: 15.6)
        foot = CritterArt.render(CGRect(x: -3.5, y: -2, width: 7, height: 4), k: k) { ctx in
            ctx.saveGState()
            ctx.move(to: CGPoint(x: -2.6, y: 0.9))
            ctx.addQuadCurve(to: CGPoint(x: 2.8, y: 0.6), control: CGPoint(x: 0, y: 2.2))
            ctx.addLine(to: CGPoint(x: 2.6, y: -0.9))
            ctx.addQuadCurve(to: CGPoint(x: -2.8, y: -0.9), control: CGPoint(x: 0, y: -1.4))
            ctx.closePath()
            ctx.clip()
            if let g = gradient([hex(0x4A4A50), hex(0x141416)], [0, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 1.6), end: CGPoint(x: 0, y: -1), options: [])
            }
            ctx.restoreGState()
            ctx.setStrokeColor(hex(0x000000, 0.5)); ctx.setLineWidth(0.18)
            for x: CGFloat in [-0.9, 0.9] { ctx.move(to: CGPoint(x: x, y: -0.9)); ctx.addLine(to: CGPoint(x: x * 0.6, y: 0.4)) }
            ctx.strokePath()
            ctx.setFillColor(hex(0xFFFFFF, 0.25))
            ctx.fillEllipse(in: CGRect(x: -1.6, y: 0.5, width: 2.2, height: 0.6))
        }
        footAt = CGPoint(x: 4.6, y: 0.9)
    }

    // MARK: - Lamb

    private func lamb(_ k: CGFloat) {
        let wool = CritterArt.pal([0xA89E92, 0xC8BFB3, 0xE2DBD1, 0xF2EDE6, 0xFFFDF9])
        let face = CritterArt.pal([0xC4BAAE, 0xDDD5CB, 0xEEE8E1, 0xF9F6F2, 0xFFFFFF])
        headC = CGPoint(x: 0, y: 25); headR = 10.5
        neck = CGPoint(x: 0, y: 16)
        eyeX = 4.1; eyeY = 0.2; eyeR = 1.3
        noseAt = CGPoint(x: 0, y: -3.6); noseW = 2.0; noseH = 1.4
        noseTop = hex(0xF0A4B0); noseBottom = hex(0xC86F80); nostril = hex(0x8E3E50, 0.8); mouthDark = hex(0xB07A80)
        furColor = hex(0xF6F2EC); lidShade = hex(0xC9C0B5)
        blush = 0.22

        body = CritterArt.render(CGRect(x: -15, y: 0, width: 30, height: 24), k: k) { ctx in
            let b = Blob(0, 11.5, 11, 9.6)
            CritterArt.base(ctx, b, wool)
            CritterArt.wool(ctx, b, pal: wool, density: 13, size: 0.85, seed: 11)
            CritterArt.shadow(ctx, Blob(0, 19.5, 9, 2.4), alpha: 0.25)
        }
        head = CritterArt.render(CGRect(x: -18, y: -14, width: 36, height: 28), k: k) { ctx in
            for side: CGFloat in [-1, 1] {
                let e = Blob(side * 11.5, 1.2, 4.6, 2.0, rot: side * -0.25)
                CritterArt.plush(ctx, e, pal: face, density: 26, len: 0.4, seed: side > 0 ? 12 : 13, droop: 0.1, edge: 1)
                let inner = Blob(side * 12.0, 1.0, 3.2, 1.0, rot: side * -0.25)
                ctx.saveGState(); inner.addPath(ctx); ctx.clip()
                if let g = gradient([hex(0xF4AFB0), hex(0xE58C93)], [0, 1]) {
                    ctx.drawRadialGradient(g, startCenter: inner.c, startRadius: 0, endCenter: inner.c, endRadius: 3.4, options: [.drawsAfterEndLocation])
                }
                ctx.restoreGState()
            }
            let h = Blob(0, -1, 8.8, 9.4)
            let muzzle = Marking(blobs: [Blob(0, -4.6, 4.6, 3.6)], pal: CritterArt.pal([0xE7E1D9, 0xF4F0EB, 0xFBF9F6, 0xFFFFFF, 0xFFFFFF]), soft: 0.5)
            CritterArt.plush(ctx, h, pal: face, marks: [muzzle], density: 34, len: 0.6, seed: 14, droop: 0.15, edge: 1.3)
            CritterArt.shadow(ctx, Blob(0, 3.4, 9.5, 2.6), alpha: 0.22)
            let crown = Blob(0, 6.2, 10.6, 6.6)
            CritterArt.base(ctx, crown, wool)
            CritterArt.wool(ctx, crown, pal: wool, density: 15, size: 0.8, seed: 15)
        }
        foot = CritterArt.render(CGRect(x: -2.5, y: -1, width: 5, height: 9), k: k) { ctx in
            let r = CGRect(x: -1.7, y: -0.4, width: 3.4, height: 8)
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
            ctx.clip()
            if let g = gradient([hex(0xFFFDF9), hex(0xD6CDC2)], [0, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: -1.7, y: 0), end: CGPoint(x: 1.7, y: 0), options: [])
            }
            ctx.setFillColor(hex(0x8A807A))
            ctx.fill(CGRect(x: -1.8, y: -0.5, width: 3.6, height: 1.5))
            ctx.restoreGState()
        }
        footAt = CGPoint(x: 4.4, y: 0)
        arm = Part()
    }

    // MARK: - Otter pup

    private func otter(_ k: CGFloat) {
        let brown = CritterArt.pal([0x3A2416, 0x56382A, 0x704C35, 0x8A6448, 0xA4805F])
        let cream = CritterArt.pal([0xA88E72, 0xC7AF92, 0xDCC8AC, 0xEBDDC8, 0xF6EEE2])
        headC = CGPoint(x: 0, y: 24.5); headR = 11
        neck = CGPoint(x: 0, y: 16)
        eyeX = 4.8; eyeY = 1.6; eyeR = 1.5
        noseAt = CGPoint(x: 0, y: -1.6); noseW = 2.4; noseH = 1.6
        noseTop = hex(0xD09A8C); noseBottom = hex(0x99604F); nostril = hex(0x4A2620, 0.8); mouthDark = hex(0x4A3024, 0.8)
        whiskers = 6; whiskerColor = hex(0xF2EADF, 0.55)
        furColor = hex(0x7A563D); lidShade = hex(0x3C2618)
        blush = 0.08

        body = CritterArt.render(CGRect(x: -15, y: -2, width: 30, height: 26), k: k) { ctx in
            let b = Blob(0, 10.5, 11, 10.2)
            let chest = Marking(blobs: [Blob(0, 13, 6.4, 6.4)], pal: cream, soft: 0.5)
            CritterArt.plush(ctx, b, pal: brown, marks: [chest], density: 36, len: 0.65, seed: 21, droop: 0.4, edge: 1.2)
            CritterArt.shadow(ctx, Blob(0, 19.2, 9.5, 2.6), alpha: 0.3)
        }
        head = CritterArt.render(CGRect(x: -15, y: -14, width: 30, height: 28), k: k) { ctx in
            for side: CGFloat in [-1, 1] {
                let e = Blob(side * 9.4, 6.6, 2.4, 2.1)
                CritterArt.plush(ctx, e, pal: brown, density: 30, len: 0.4, seed: side > 0 ? 22 : 23, droop: 0, edge: 1)
                ctx.setFillColor(hex(0x2A190F, 0.75))
                ctx.fillEllipse(in: CGRect(x: e.c.x - 1.0, y: e.c.y - 0.9, width: 2.0, height: 1.6))
            }
            let h = Blob(0, 0, 11, 10)
            let face = Marking(blobs: [Blob(0, -3.4, 8.6, 5.6), Blob(-5.6, -0.6, 3.8, 3.6), Blob(5.6, -0.6, 3.8, 3.6)], pal: cream, soft: 0.45)
            CritterArt.plush(ctx, h, pal: brown, marks: [face], density: 36, len: 0.62, seed: 24, droop: 0.15, edge: 1.3)
        }
        arm = CritterArt.limb(k, blob: Blob(1.2, -3.2, 2.4, 3.6, rot: 0.25), pal: brown, seed: 25, len: 0.5, toes: hex(0x22140B, 0.6))
        armRest = -0.45
        shoulder = CGPoint(x: 6.2, y: 15.5)
        foot = CritterArt.limb(k, blob: Blob(0, 0.6, 3.0, 1.8), pal: brown, seed: 26, len: 0.4, toes: hex(0x22140B, 0.6))
        footAt = CGPoint(x: 4.6, y: 0.4)
    }

    // MARK: - Seal pup

    private func seal(_ k: CGFloat) {
        let white = CritterArt.pal([0xA9B2BE, 0xC8CFD9, 0xE0E5EC, 0xF1F4F7, 0xFFFFFF])
        headC = CGPoint(x: 0, y: 23.5); headR = 11.5
        neck = CGPoint(x: 0, y: 15)
        eyeX = 4.9; eyeY = 1.8; eyeR = 2.25
        noseAt = CGPoint(x: 0, y: -1.6); noseW = 2.2; noseH = 1.8
        noseTop = hex(0x3B3330); noseBottom = hex(0x0E0B0A); nostril = hex(0x000000, 0.9); mouthDark = hex(0x3A2E2A, 0.8)
        whiskers = 9; whiskerColor = hex(0xFFFFFF, 0.7)
        furColor = hex(0xF1F3F7); lidShade = hex(0xB8C1CC)
        blush = 0.1

        body = CritterArt.render(CGRect(x: -17, y: -2, width: 34, height: 26), k: k) { ctx in
            let b = Blob(0, 10, 13, 10)
            CritterArt.plush(ctx, b, pal: white, density: 30, len: 0.95, seed: 31, droop: 0.4, edge: 1.6)
            CritterArt.shadow(ctx, Blob(0, 17.5, 10.5, 2.6), alpha: 0.2)
        }
        head = CritterArt.render(CGRect(x: -16, y: -15, width: 32, height: 30), k: k) { ctx in
            let h = Blob(0, 0, 11.5, 11)
            CritterArt.plush(ctx, h, pal: white, density: 30, len: 0.85, seed: 32, droop: 0.15, edge: 1.6)
            for side: CGFloat in [-1, 1] {
                let pad = Blob(side * 2.3, -3.8, 2.6, 2.2, rot: side * 0.15)
                ctx.saveGState()
                pad.addPath(ctx); ctx.clip()
                if let g = gradient([hex(0xC2BAB3), hex(0x958C85)], [0, 1]) {
                    ctx.drawRadialGradient(g, startCenter: CGPoint(x: pad.c.x - 0.5, y: pad.c.y + 0.8), startRadius: 0, endCenter: pad.c,
                                           endRadius: 3, options: [.drawsAfterEndLocation])
                }
                var r = Seeded(side > 0 ? 33 : 34)
                ctx.setFillColor(hex(0x3A322E, 0.7))
                for _ in 0..<11 {
                    let p = pad.point(sqrt(r.next()) * 0.85, r.next() * 2 * CGFloat.pi)
                    ctx.fillEllipse(in: CGRect(x: p.x - 0.17, y: p.y - 0.17, width: 0.34, height: 0.34))
                }
                ctx.restoreGState()
            }
            CritterArt.plush(ctx, Blob(0, -3.8, 5.2, 2.6), pal: CritterArt.pal([0xE0E5EC, 0xFFFFFF], 0.5), density: 8, len: 0.35, seed: 35, droop: 0.1, edge: 0.8,
                             keep: { p in !Blob(-2.3, -3.8, 2.4, 2.0).contains(p) && !Blob(2.3, -3.8, 2.4, 2.0).contains(p) })
        }
        arm = CritterArt.limb(k, blob: Blob(1.4, -3.6, 2.3, 4.4, rot: 0.5), pal: white, seed: 36, len: 0.5, toes: hex(0x3A322E, 0.5))
        armRest = 0.35
        shoulder = CGPoint(x: 10, y: 9)
        foot = Part()
    }

    // MARK: - Hedgehog

    private func hedgehog(_ k: CGFloat) {
        let face = CritterArt.pal([0x9C8C7C, 0xC0B2A2, 0xD9CEC0, 0xEAE3D8, 0xF7F3EE])
        let mask = CritterArt.pal([0x6A5848, 0x85715F, 0x9D8A78, 0xB4A290, 0xC6B6A5])
        headC = CGPoint(x: 0, y: 23.5); headR = 10
        neck = CGPoint(x: 0, y: 15)
        eyeX = 3.8; eyeY = 1.0; eyeR = 1.3
        noseAt = CGPoint(x: 0, y: -3.3); noseW = 1.9; noseH = 1.5
        noseTop = hex(0x4A3A34); noseBottom = hex(0x120D0B); nostril = hex(0x000000, 0.9); mouthDark = hex(0x3A2A22, 0.8)
        whiskers = 3.5; whiskerColor = hex(0x5A4A40, 0.45)
        furColor = hex(0xD9CEC0); lidShade = hex(0x7A6656)
        blush = 0.2

        body = CritterArt.render(CGRect(x: -20, y: -2, width: 40, height: 30), k: k) { ctx in
            CritterArt.quills(ctx, around: Blob(0, 11, 11, 9.6), from: -0.15 * CGFloat.pi, to: 1.15 * CGFloat.pi, count: 2200, len: 3.2, seed: 41)
            CritterArt.plush(ctx, Blob(0, 9, 8.4, 9), pal: face, density: 34, len: 0.7, seed: 42, droop: 0.4, edge: 1.4)
            CritterArt.shadow(ctx, Blob(0, 18.5, 8.5, 2.4), alpha: 0.25)
        }
        head = CritterArt.render(CGRect(x: -19, y: -16, width: 38, height: 34), k: k) { ctx in
            CritterArt.quills(ctx, around: Blob(0, 1.2, 10.6, 9.6), from: -0.1 * CGFloat.pi, to: 1.1 * CGFloat.pi, count: 3200, len: 3.6, seed: 43)
            for side: CGFloat in [-1, 1] {
                let e = Blob(side * 7.4, 6.4, 2.3, 2.1)
                ctx.setFillColor(hex(0xA48A7E)); ctx.fillEllipse(in: CGRect(x: e.c.x - e.rx, y: e.c.y - e.ry, width: 2 * e.rx, height: 2 * e.ry))
                ctx.setFillColor(hex(0xD6B3A8)); ctx.fillEllipse(in: CGRect(x: e.c.x - 1.3, y: e.c.y - 1.2, width: 2.6, height: 2.4))
            }
            let h = Blob(0, -1.2, 8.2, 8.2)
            let eyes = Marking(blobs: [Blob(-3.8, 2.2, 2.4, 2.0, rot: 0.3), Blob(3.8, 2.2, 2.4, 2.0, rot: -0.3), Blob(0, -2.6, 2.4, 2.4)], pal: mask, soft: 0.6)
            CritterArt.plush(ctx, h, pal: face, marks: [eyes], density: 36, len: 0.62, seed: 44, droop: 0.15, edge: 1.4)
            CritterArt.shadow(ctx, Blob(0, -4.8, 3.6, 1.4), alpha: 0.25)
            CritterArt.plush(ctx, Blob(0, -3.0, 3.3, 2.7), pal: mask, density: 38, len: 0.4, seed: 45, droop: 0.05, edge: 0.6)
        }
        arm = CritterArt.render(CGRect(x: -2, y: -5, width: 5, height: 6), k: k) { ctx in
            ctx.setFillColor(hex(0xD9A79C))
            ctx.fillEllipse(in: CGRect(x: -0.4, y: -3.8, width: 2.8, height: 2.4))
            ctx.setStrokeColor(hex(0xB07F74, 0.8)); ctx.setLineWidth(0.2)
            for i in 0..<3 { let x = 0.3 + CGFloat(i) * 0.7; ctx.move(to: CGPoint(x: x, y: -3.8)); ctx.addLine(to: CGPoint(x: x, y: -3.1)) }
            ctx.strokePath()
        }
        armRest = 0
        shoulder = CGPoint(x: 4.2, y: 12)
        foot = CritterArt.render(CGRect(x: -2, y: -1, width: 4, height: 3), k: k) { ctx in
            ctx.setFillColor(hex(0xD3A296))
            ctx.fillEllipse(in: CGRect(x: -1.6, y: -0.4, width: 3.2, height: 1.9))
        }
        footAt = CGPoint(x: 4.2, y: 0.4)
    }
}

// MARK: - Per-frame drawing

extension PipArt {
    static func drawCritter(_ ctx: CGContext, _ p: Pip, art A: CritterArt, kind: Kind, wind: Double, feet F: CGPoint) {
        let hop = CGFloat(p.hop)
        let t = CGFloat(p.time)
        let breathe = 1 + sin(t * 2.3) * 0.014
        let sq = CGFloat(max(-0.3, min(0.5, p.squash)))
        let sx = (1 + sq * 0.45) * breathe, sy = (1 - sq * 0.9) / breathe
        let dir = CGFloat(p.facing)
        let walking = p.state == .walk || p.state == .build || p.state == .wake
        let wp = CGFloat(p.walkPhase)
        let happy = p.face == .happy || p.state == .pet
        let waving = p.state == .wake || p.state == .pet

        softShadowGround(ctx, F, 15 / (1 + hop / 30))

        ctx.saveGState()
        ctx.translateBy(x: F.x, y: F.y + hop)
        ctx.scaleBy(x: sx, y: sy)
        let rock = walking ? sin(wp) * 0.09 : sin(t * 1.1) * 0.012       // waddle
        ctx.rotate(by: rock)

        for side: CGFloat in [-1, 1] {
            let lift = walking ? max(0, sin(wp + (side > 0 ? 0 : CGFloat.pi))) * 1.6 : 0
            A.foot.draw(ctx, pivot: .zero, at: CGPoint(x: side * A.footAt.x, y: A.footAt.y + lift), rotate: -side * 0.12, sx: side)
        }

        A.body.draw(ctx)

        for side: CGFloat in [-1, 1] {
            var ang = A.armRest
            if waving { ang = -2.2 + sin(t * 9 + (side > 0 ? 0 : 1.5)) * 0.3 }
            else if happy { ang = -1.0 + sin(t * 12 + side) * 0.35 }
            else if p.state == .build { ang = -0.9 + sin(wp + (side > 0 ? 0 : CGFloat.pi)) * 0.4 }
            else if p.state == .catching { ang = -1.6 + sin(t * 5 + side) * 0.2 }
            else if walking { ang += sin(wp + (side > 0 ? CGFloat.pi : 0)) * 0.3 }
            A.arm.draw(ctx, pivot: A.armPivot, at: CGPoint(x: side * A.shoulder.x, y: A.shoulder.y), rotate: -side * ang, sx: side)
        }

        if kind == .rain {
            ctx.saveGState()
            ctx.translateBy(x: A.headC.x, y: A.headC.y)
            ctx.scaleBy(x: A.headR / 14, y: A.headR / 14)
            umbrella(ctx, .zero, 14, dir, wind, t)
            ctx.restoreGState()
        }

        var tilt = -CGFloat(p.lookX) * 0.09 + sin(t * 0.9) * 0.025
        if happy { tilt += sin(t * 4) * 0.06 }
        if p.face == .sleep { tilt += 0.1 }
        ctx.saveGState()
        ctx.translateBy(x: A.neck.x, y: A.neck.y)
        ctx.rotate(by: tilt)
        ctx.translateBy(x: A.headC.x - A.neck.x, y: A.headC.y - A.neck.y + (p.face == .sleep ? -0.8 : 0))
        A.head.draw(ctx)
        face(ctx, p, A, t: t, happy: happy, dir: dir)
        ctx.saveGState()
        ctx.scaleBy(x: A.headR / 14, y: A.headR / 14)
        outfit(ctx, kind, .zero, 14, dir, wind, t, walking)
        ctx.restoreGState()
        ctx.restoreGState()
        ctx.restoreGState()

        if p.face == .dizzy {
            for k in 0..<3 {
                let a = t * 3.2 + CGFloat(k) * 2.1
                let c = CGPoint(x: F.x + cos(a) * 11, y: F.y + hop + (A.headC.y + A.headR + 3) * sy + sin(a) * 2.5)
                ctx.saveGState()
                ctx.translateBy(x: c.x, y: c.y)
                ctx.scaleBy(x: 0.11, y: 0.11)
                Sprites.sparkle(hex(0xFFF1B0), rays: 20)(ctx)
                ctx.restoreGState()
            }
        }
        if happy {
            for k in 0..<2 {
                let ph = t * 1.3 + CGFloat(k) * 3
                let u = ph.truncatingRemainder(dividingBy: 2.4) / 2.4
                let c = CGPoint(x: F.x + (k == 0 ? -17 : 18), y: F.y + hop + 26 + u * 12)
                ctx.saveGState()
                ctx.translateBy(x: c.x, y: c.y)
                let s = 0.1 * sin(u * CGFloat.pi)
                ctx.scaleBy(x: s, y: s)
                Sprites.sparkle(hex(0xFFE7F0), rays: 20)(ctx)
                ctx.restoreGState()
            }
        }
        effects(ctx, p, CGPoint(x: F.x, y: F.y - 6))
        if let text = p.bubble, p.bubbleAlpha > 0.01 {
            bubble(ctx, text, alpha: CGFloat(p.bubbleAlpha), at: CGPoint(x: F.x, y: F.y + hop + (A.headC.y + A.headR) * sy + 8))
        }
    }

    static func softShadowGround(_ ctx: CGContext, _ F: CGPoint, _ r: CGFloat) {
        guard let g = gradient([hex(0x150F0A, 0.32), hex(0x150F0A, 0)], [0, 1]) else { return }
        ctx.saveGState()
        ctx.translateBy(x: F.x, y: F.y)
        ctx.scaleBy(x: 1, y: 0.22)
        ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r, options: [])
        ctx.restoreGState()
    }

    /// Eyes, beak or nose, mouth, whiskers (head space). The face shifts a little toward where Pip is facing,
    /// which reads as a slight turn of the head.
    static func face(_ ctx: CGContext, _ p: Pip, _ A: CritterArt, t: CGFloat, happy: Bool, dir: CGFloat) {
        let turn = dir * 0.9 + CGFloat(p.lookX) * 0.6
        let lookY = -CGFloat(p.lookY) * 0.35

        if A.blush > 0, let g = gradient([hex(0xFF9AAE, A.blush * (happy ? 1.6 : 1)), hex(0xFF9AAE, 0)], [0, 1]) {
            for side: CGFloat in [-1, 1] {
                let c = CGPoint(x: side * (A.eyeX + 1.6) + turn, y: A.eyeY - 2.4)
                ctx.saveGState()
                ctx.translateBy(x: c.x, y: c.y)
                ctx.scaleBy(x: 1.4, y: 1)
                ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 2.2, options: [])
                ctx.restoreGState()
            }
        }

        for side: CGFloat in [-1, 1] {
            let near = side * dir < 0
            let r = A.eyeR * (p.face == .surprised ? 1.12 : 1) * (near ? 1 : 0.94)
            let c = CGPoint(x: side * A.eyeX * (near ? 1 : 0.92) + turn, y: A.eyeY + lookY)
            if let g = gradient([A.lidShade.copyAlpha(0.4), A.lidShade.copyAlpha(0)], [0.45, 1]) {
                ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r * 1.9, options: [])
            }
            if p.face == .sleep {
                lid(ctx, c, r, closed: 1, A)
                continue
            }
            eyeball(ctx, c, r, t: t, side: side, sp: A.species)
            if p.face == .dizzy {
                ctx.setStrokeColor(hex(0xFFFFFF, 0.5)); ctx.setLineWidth(0.18)
                ctx.addArc(center: c, radius: r * 0.5, startAngle: t * 6 * side, endAngle: t * 6 * side + 4, clockwise: false)
                ctx.strokePath()
            }
            let closed = CGFloat(p.blink)
            if closed > 0.02 { lid(ctx, c, r, closed: closed, A) }
            if happy || p.face == .eat {
                // cheeks push the lower lid up: a smiling squint, kept inside the eye
                ctx.saveGState()
                ctx.addEllipse(in: CGRect(x: c.x - r * 1.02, y: c.y - r * 1.07, width: r * 2.04, height: r * 2.14))
                ctx.clip()
                ctx.setFillColor(A.furColor)
                ctx.fillEllipse(in: CGRect(x: c.x - r * 1.5, y: c.y - r * 2.55, width: r * 3.0, height: r * 2.0))
                ctx.restoreGState()
                ctx.setStrokeColor(hex(0x1E1410, 0.5)); ctx.setLineWidth(0.25)
                ctx.addArc(center: CGPoint(x: c.x, y: c.y - r * 1.55), radius: r * 1.1, startAngle: 0.28 * CGFloat.pi, endAngle: 0.72 * CGFloat.pi, clockwise: false)
                ctx.strokePath()
            }
        }

        let n = CGPoint(x: A.noseAt.x + turn * 1.15, y: A.noseAt.y + lookY * 0.6)
        if A.beak {
            beakShape(ctx, n, open: happy || p.face == .surprised ? 0.5 : (p.face == .eat ? abs(sin(t * 16)) * 0.6 : 0))
        } else {
            noseShape(ctx, n, w: A.noseW, h: A.noseH, top: A.noseTop, bottom: A.noseBottom, nostril: A.nostril)
            let m = CGPoint(x: n.x, y: n.y - A.noseH * 1.2)
            ctx.setStrokeColor(A.mouthDark)
            ctx.setLineWidth(0.3)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: n.x, y: n.y - A.noseH * 0.5)); ctx.addLine(to: m)
            ctx.strokePath()
            if happy || p.face == .surprised || p.face == .eat {
                let open: CGFloat = p.face == .eat ? 0.4 + abs(sin(t * 16)) * 0.5 : (p.face == .surprised ? 0.9 : 0.7)
                ctx.saveGState()
                ctx.addEllipse(in: CGRect(x: m.x - 1.3, y: m.y - open * 1.5, width: 2.6, height: open * 1.9))
                ctx.clip()
                if let g = gradient([hex(0x5A1E2A), hex(0xE8879A)], [0, 1]) {
                    ctx.drawLinearGradient(g, start: CGPoint(x: m.x, y: m.y + 0.3), end: CGPoint(x: m.x, y: m.y - open * 1.5), options: [])
                }
                ctx.restoreGState()
            } else {
                for side: CGFloat in [-1, 1] {
                    ctx.move(to: m)
                    ctx.addQuadCurve(to: CGPoint(x: m.x + side * 1.5, y: m.y + 0.3), control: CGPoint(x: m.x + side * 0.7, y: m.y - 0.45))
                }
                ctx.strokePath()
            }
        }

        if A.whiskers > 0 {
            ctx.setLineCap(.round)
            ctx.setStrokeColor(A.whiskerColor)
            ctx.setLineWidth(0.17)
            for side: CGFloat in [-1, 1] {
                for i in 0..<4 {
                    let fi = CGFloat(i)
                    let o = CGPoint(x: n.x + side * (1.6 + fi * 0.2), y: n.y - 0.9 - fi * 0.35)
                    let ang = (side > 0 ? 0 : CGFloat.pi) + side * (0.12 - fi * 0.13) + sin(t * 1.8 + fi) * 0.03
                    let L = A.whiskers * (0.8 + 0.07 * fi)
                    let e = CGPoint(x: o.x + cos(ang) * L, y: o.y + sin(ang) * L)
                    ctx.move(to: o)
                    ctx.addQuadCurve(to: e, control: CGPoint(x: (o.x + e.x) / 2, y: (o.y + e.y) / 2 + 0.6))
                }
            }
            ctx.strokePath()
        }
    }

    /// A penguin chick's small glossy black beak.
    static func beakPath(_ ctx: CGContext, _ c: CGPoint, _ w: CGFloat, _ h: CGFloat) {
        ctx.move(to: CGPoint(x: c.x - w / 2, y: c.y + h * 0.3))
        ctx.addCurve(to: CGPoint(x: c.x + w / 2, y: c.y + h * 0.3), control1: CGPoint(x: c.x - w * 0.35, y: c.y + h * 0.8), control2: CGPoint(x: c.x + w * 0.35, y: c.y + h * 0.8))
        ctx.addCurve(to: CGPoint(x: c.x, y: c.y - h * 0.5), control1: CGPoint(x: c.x + w * 0.45, y: c.y - h * 0.1), control2: CGPoint(x: c.x + w * 0.15, y: c.y - h * 0.45))
        ctx.addCurve(to: CGPoint(x: c.x - w / 2, y: c.y + h * 0.3), control1: CGPoint(x: c.x - w * 0.15, y: c.y - h * 0.45), control2: CGPoint(x: c.x - w * 0.45, y: c.y - h * 0.1))
        ctx.closePath()
    }

    static func beakShape(_ ctx: CGContext, _ c: CGPoint, open: CGFloat) {
        let w: CGFloat = 3.0, h: CGFloat = 2.4
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -0.4), blur: 0.8, color: hex(0x000000, 0.35))
        beakPath(ctx, c, w, h)
        ctx.setFillColor(hex(0x1A1A1E))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        beakPath(ctx, c, w, h)
        ctx.clip()
        if let g = gradient([hex(0x5A5A62), hex(0x26262B), hex(0x0B0B0D)], [0, 0.45, 1]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: c.x - w * 0.18, y: c.y + h * 0.4), startRadius: 0,
                                   endCenter: c, endRadius: w * 0.75, options: [.drawsAfterEndLocation])
        }
        ctx.restoreGState()
        ctx.setStrokeColor(hex(0x000000, 0.75))
        ctx.setLineWidth(0.22)
        ctx.move(to: CGPoint(x: c.x - w * 0.42, y: c.y + h * 0.05))
        ctx.addQuadCurve(to: CGPoint(x: c.x + w * 0.42, y: c.y + h * 0.05), control: CGPoint(x: c.x, y: c.y - h * 0.12 - open))
        ctx.strokePath()
        if open > 0.05 {
            ctx.setFillColor(hex(0xD77A8C, 0.9))
            ctx.fillEllipse(in: CGRect(x: c.x - 0.6, y: c.y - h * 0.12 - open * 0.8, width: 1.2, height: open * 0.8))
        }
        ctx.setFillColor(hex(0xFFFFFF, 0.55))
        ctx.fillEllipse(in: CGRect(x: c.x - w * 0.3, y: c.y + h * 0.36, width: w * 0.32, height: h * 0.14))
        ctx.setFillColor(hex(0xFFFFFF, 0.25))
        ctx.fillEllipse(in: CGRect(x: c.x + w * 0.08, y: c.y - h * 0.3, width: w * 0.14, height: h * 0.1))
    }

    /// A glossy dark eye with a window-shaped highlight and a faint rim of sky light.
    static func eyeball(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, t: CGFloat, side: CGFloat, sp: Species) {
        let rx = r * 0.95, ry = r
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: c.x - rx, y: c.y - ry, width: 2 * rx, height: 2 * ry))
        ctx.clip()
        let mid: UInt32 = sp == .otter ? 0x2A1A12 : (sp == .lamb ? 0x2B1E18 : 0x161112)
        if let g = gradient([hex(mid), hex(0x060405)], [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: c.x + r * 0.15, y: c.y - r * 0.35), startRadius: 0,
                                   endCenter: c, endRadius: r * 1.1, options: [.drawsAfterEndLocation])
        }
        ctx.setStrokeColor(hex(0x9DB7D8, 0.3))
        ctx.setLineWidth(r * 0.2)
        ctx.addArc(center: c, radius: r * 0.82, startAngle: 1.15 * CGFloat.pi, endAngle: 1.85 * CGFloat.pi, clockwise: false)
        ctx.strokePath()
        ctx.restoreGState()
        ctx.setFillColor(hex(0xFFFFFF, 0.95))
        let hx = c.x - r * 0.28, hy = c.y + r * 0.36
        ctx.addPath(CGPath(roundedRect: CGRect(x: hx - r * 0.22, y: hy - r * 0.19, width: r * 0.44, height: r * 0.4), cornerWidth: r * 0.13, cornerHeight: r * 0.13, transform: nil))
        ctx.fillPath()
        ctx.setFillColor(hex(0xFFFFFF, 0.5))
        ctx.fillEllipse(in: CGRect(x: c.x + r * 0.3, y: c.y - r * 0.42, width: r * 0.2, height: r * 0.18))
        ctx.setStrokeColor(hex(0x000000, 0.35))
        ctx.setLineWidth(0.22)
        ctx.strokeEllipse(in: CGRect(x: c.x - rx, y: c.y - ry, width: 2 * rx, height: 2 * ry))
    }

    /// Fur-coloured eyelid closing from the top, with a dark lash line.
    static func lid(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, closed: CGFloat, _ A: CritterArt) {
        let edge = c.y + r * (1.05 - 2.1 * closed)
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: c.x - r * 1.15, y: c.y - r * 1.15, width: r * 2.3, height: r * 2.3))
        ctx.clip()
        ctx.setFillColor(A.furColor)
        ctx.fill(CGRect(x: c.x - r * 1.3, y: edge, width: r * 2.6, height: r * 2.6))
        ctx.restoreGState()
        ctx.setStrokeColor(hex(0x1E1410, 0.85))
        ctx.setLineWidth(0.38)
        ctx.setLineCap(.round)
        let w = r * (0.75 + 0.25 * closed)
        ctx.move(to: CGPoint(x: c.x - w, y: edge + 0.1))
        ctx.addQuadCurve(to: CGPoint(x: c.x + w, y: edge + 0.1), control: CGPoint(x: c.x, y: edge - r * 0.35 * closed))
        ctx.strokePath()
    }

    static func noseShape(_ ctx: CGContext, _ c: CGPoint, w: CGFloat, h: CGFloat, top: CGColor, bottom: CGColor, nostril: CGColor) {
        ctx.saveGState()
        ctx.move(to: CGPoint(x: c.x - w / 2, y: c.y + h * 0.35))
        ctx.addCurve(to: CGPoint(x: c.x + w / 2, y: c.y + h * 0.35), control1: CGPoint(x: c.x - w * 0.4, y: c.y + h * 0.8), control2: CGPoint(x: c.x + w * 0.4, y: c.y + h * 0.8))
        ctx.addCurve(to: CGPoint(x: c.x, y: c.y - h * 0.5), control1: CGPoint(x: c.x + w * 0.55, y: c.y - h * 0.15), control2: CGPoint(x: c.x + w * 0.2, y: c.y - h * 0.5))
        ctx.addCurve(to: CGPoint(x: c.x - w / 2, y: c.y + h * 0.35), control1: CGPoint(x: c.x - w * 0.2, y: c.y - h * 0.5), control2: CGPoint(x: c.x - w * 0.55, y: c.y - h * 0.15))
        ctx.closePath()
        ctx.clip()
        if let g = gradient([top, bottom], [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: c.x, y: c.y + h * 0.7), end: CGPoint(x: c.x, y: c.y - h * 0.5), options: [])
        }
        ctx.restoreGState()
        ctx.setFillColor(nostril)
        for side: CGFloat in [-1, 1] {
            ctx.fillEllipse(in: CGRect(x: c.x + side * w * 0.22 - w * 0.09, y: c.y - h * 0.05, width: w * 0.18, height: h * 0.22))
        }
        ctx.setFillColor(hex(0xFFFFFF, 0.6))
        ctx.fillEllipse(in: CGRect(x: c.x - w * 0.22, y: c.y + h * 0.3, width: w * 0.3, height: h * 0.16))
    }
}

extension CGColor {
    func copyAlpha(_ a: CGFloat) -> CGColor {
        let c = components ?? [0, 0, 0, 1]
        if c.count >= 4 { return CGColor(red: c[0], green: c[1], blue: c[2], alpha: a) }
        return CGColor(red: c[0], green: c[0], blue: c[0], alpha: a)
    }
}
