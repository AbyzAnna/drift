// Sprite.swift — Pip from 3D-rendered parts.
// Each character is modelled and lit in Blender (Tools/characters.py) and rendered as aligned layers:
// body, feet, arms, ears, four head moods (open, closed, happy, surprised) and 3D outfits.
// Every frame the app assembles them: it swaps head images to blink and change expression,
// tilts the head, waves the arms, twitches the ears and waddles — cheap, and it looks sculpted.

import Cocoa
import ImageIO

final class SpriteCritter {
    let species: Species
    let box: CGRect                                  // where every layer image sits, in Pip units
    var parts: [String: CGImage] = [:]
    var pivots: [String: CGPoint] = [:]
    var hatCenter = CGPoint(x: 0, y: 26)
    var hatR: CGFloat = 10
    var fits: [String: String] = [:]                // outfit name -> "head" or "body"
    var ears: [String] = []

    /// Loads Characters/<species>/ from the app bundle. Returns nil if the art isn't there.
    init?(_ species: Species, base: URL) {
        self.species = species
        let dir = base.appendingPathComponent(species.rawValue)
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let ortho = CGFloat((obj["ortho"] as? NSNumber)?.doubleValue ?? 60)
        let cy = CGFloat((obj["center_y"] as? NSNumber)?.doubleValue ?? 28)
        box = CGRect(x: -ortho / 2, y: cy - ortho / 2, width: ortho, height: ortho)
        if let pv = obj["pivots"] as? [String: [NSNumber]] {
            for (k, v) in pv where v.count == 2 { pivots[k] = CGPoint(x: CGFloat(v[0].doubleValue), y: CGFloat(v[1].doubleValue)) }
        }
        if let hat = obj["hat"] as? [String: Any] {
            if let c = hat["center"] as? [NSNumber], c.count == 2 { hatCenter = CGPoint(x: CGFloat(c[0].doubleValue), y: CGFloat(c[1].doubleValue)) }
            if let r = hat["r"] as? NSNumber { hatR = CGFloat(r.doubleValue) }
        }
        fits = (obj["fits"] as? [String: String]) ?? [:]
        ears = (obj["ears"] as? [String]) ?? []
        let names = (obj["parts"] as? [String]) ?? []
        for n in names {
            let url = dir.appendingPathComponent(n + ".png")
            if let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                parts[n] = img
            }
        }
        guard parts["body"] != nil, parts["head_open"] != nil else { return nil }
    }

    static func available(in base: URL) -> [Species] {
        Species.allCases.filter { FileManager.default.fileExists(atPath: base.appendingPathComponent($0.rawValue).appendingPathComponent("manifest.json").path) }
    }

    func pivot(_ k: String, _ fallback: CGPoint) -> CGPoint { pivots[k] ?? fallback }

    /// Draws one layer rotated by `angle` around `pivot`, moved by `offset`.
    func layer(_ ctx: CGContext, _ name: String, pivot: CGPoint = .zero, angle: CGFloat = 0, offset: CGPoint = .zero) {
        guard let img = parts[name] else { return }
        ctx.saveGState()
        ctx.translateBy(x: pivot.x + offset.x, y: pivot.y + offset.y)
        if angle != 0 { ctx.rotate(by: angle) }
        ctx.translateBy(x: -pivot.x, y: -pivot.y)
        ctx.draw(img, in: box)
        ctx.restoreGState()
    }

    /// The 3D outfits each season wears.
    func outfit(for kind: Kind) -> [String] {
        switch kind {
        case .snow: return ["fit_scarf_snow", "fit_beanie"]
        case .leaf: return ["fit_scarf_autumn", "fit_leafhat"]
        case .petal: return ["fit_clip"]
        case .spring: return ["fit_sprout"]
        case .flower: return ["fit_crown"]
        case .rain, .star: return []
        }
    }
}

extension PipArt {
    static let spriteScale: CGFloat = 0.95

    static func drawSprite(_ ctx: CGContext, _ p: Pip, art S: SpriteCritter, kind: Kind, wind: Double, feet F: CGPoint) {
        let hop = CGFloat(p.hop)
        let t = CGFloat(p.time)
        let breathe = 1 + sin(t * 2.3) * 0.012
        let sq = CGFloat(max(-0.3, min(0.5, p.squash)))
        let sx = (1 + sq * 0.4) * breathe, sy = (1 - sq * 0.85) / breathe
        let dir = CGFloat(p.facing)
        let walking = p.state == .walk || p.state == .build || p.state == .wake
        let wp = CGFloat(p.walkPhase)
        let happy = p.face == .happy || p.state == .pet
        let waving = p.state == .wake || p.state == .pet
        let k = spriteScale

        softShadowGround(ctx, F, 15 / (1 + hop / 30))

        ctx.saveGState()
        ctx.translateBy(x: F.x, y: F.y + hop)
        // the art faces left; mirror it when Pip faces right
        ctx.scaleBy(x: sx * k * -dir, y: sy * k)
        let rock = walking ? sin(wp) * 0.08 : sin(t * 1.1) * 0.01
        ctx.rotate(by: rock)

        // feet lift in turn
        for (name, ph) in [("footL", CGFloat.pi), ("footR", 0)] {
            let lift = walking ? max(0, sin(wp + ph)) * 1.4 : 0
            S.layer(ctx, name, offset: CGPoint(x: 0, y: lift))
        }

        S.layer(ctx, "body")

        // arms hang, swing, wave up or pat
        for (name, side) in [("armL", CGFloat(-1)), ("armR", CGFloat(1))] {
            let piv = S.pivot(name == "armL" ? "shoulderL" : "shoulderR", CGPoint(x: side * 6.8, y: 15.5))
            var a: CGFloat = 0
            if waving { a = 2.3 + sin(t * 9 + (side > 0 ? 0 : 1.5)) * 0.3 }
            else if happy { a = 1.0 + sin(t * 12 + side) * 0.3 }
            else if p.state == .build { a = 0.8 + sin(wp + (side > 0 ? 0 : CGFloat.pi)) * 0.4 }
            else if p.state == .catching { a = 1.6 + sin(t * 5 + side) * 0.2 }
            else if walking { a = sin(wp + (side > 0 ? CGFloat.pi : 0)) * 0.3 }
            S.layer(ctx, name, pivot: piv, angle: side * a)
        }

        // soft shadow where the head sits on the body
        let neck = S.pivot("neck", CGPoint(x: 0, y: 17.5))
        if let g = gradient([hex(0x2A2030, 0.28), hex(0x2A2030, 0)], [0, 1]) {
            ctx.saveGState()
            ctx.translateBy(x: neck.x, y: neck.y - 0.5)
            ctx.scaleBy(x: 1, y: 0.3)
            ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 9, options: [])
            ctx.restoreGState()
        }

        if kind == .rain {
            ctx.saveGState()
            ctx.translateBy(x: S.hatCenter.x, y: S.hatCenter.y)
            ctx.scaleBy(x: S.hatR / 14, y: S.hatR / 14)
            umbrella(ctx, .zero, 14, -1, -wind * Double(dir), t)
            ctx.restoreGState()
        }

        // head group: ears, head (with the right expression), hats — all tilting together
        var tilt = CGFloat(p.lookX) * dir * 0.08 + sin(t * 0.9) * 0.02
        if happy { tilt += sin(t * 4) * 0.05 }
        if p.face == .sleep { tilt -= 0.08 }
        ctx.saveGState()
        ctx.translateBy(x: neck.x, y: neck.y)
        ctx.rotate(by: tilt)
        ctx.translateBy(x: -neck.x, y: -neck.y + (p.face == .sleep ? -0.6 : 0) + CGFloat(-p.lookY) * 0.3)

        let twitch = (sin(t * 0.7) > 0.97 ? sin(t * 40) * 0.12 : 0) + (p.face == .sleep ? 0.15 : 0) + (p.face == .surprised ? -0.1 : 0)
        for e in S.ears {
            let side: CGFloat = e.hasSuffix("L") ? -1 : 1
            let piv = S.pivot(e, CGPoint(x: side * 4.5, y: 31))
            S.layer(ctx, e, pivot: piv, angle: -side * (twitch + (happy ? sin(t * 6) * 0.06 : 0)))
        }
        let headName: String
        switch p.face {
        case .sleep: headName = "head_closed"
        case .happy, .eat: headName = "head_happy"
        case .surprised: headName = "head_surprised"
        default: headName = p.blink > 0.5 ? "head_closed" : "head_open"
        }
        S.layer(ctx, S.parts[headName] != nil ? headName : "head_open")
        for f in S.outfit(for: kind) where S.fits[String(f.dropFirst(4))] == "head" { S.layer(ctx, f) }
        if kind == .star {
            ctx.saveGState()
            ctx.translateBy(x: S.hatCenter.x, y: S.hatCenter.y)
            ctx.scaleBy(x: S.hatR / 14, y: S.hatR / 14)
            outfit(ctx, .star, .zero, 14, -1, wind, t, walking)
            ctx.restoreGState()
        }
        ctx.restoreGState()

        // scarves sit over the chin
        for f in S.outfit(for: kind) where S.fits[String(f.dropFirst(4))] == "body" { S.layer(ctx, f) }
        ctx.restoreGState()

        let top = (S.hatCenter.y + S.hatR) * sy * k
        if p.face == .dizzy {
            for i in 0..<3 {
                let a = t * 3.2 + CGFloat(i) * 2.1
                let c = CGPoint(x: F.x + cos(a) * 12, y: F.y + hop + top + 2 + sin(a) * 2.5)
                ctx.saveGState()
                ctx.translateBy(x: c.x, y: c.y)
                ctx.scaleBy(x: 0.11, y: 0.11)
                Sprites.sparkle(hex(0xFFF1B0), rays: 20)(ctx)
                ctx.restoreGState()
            }
        }
        if happy {
            for i in 0..<2 {
                let ph = t * 1.3 + CGFloat(i) * 3
                let u = ph.truncatingRemainder(dividingBy: 2.4) / 2.4
                let c = CGPoint(x: F.x + (i == 0 ? -18 : 19), y: F.y + hop + 24 + u * 12)
                ctx.saveGState()
                ctx.translateBy(x: c.x, y: c.y)
                let s = 0.1 * sin(u * CGFloat.pi)
                ctx.scaleBy(x: s, y: s)
                Sprites.sparkle(hex(0xFFE7F0), rays: 20)(ctx)
                ctx.restoreGState()
            }
        }
        effects(ctx, p, CGPoint(x: F.x, y: F.y - 8))
        if let text = p.bubble, p.bubbleAlpha > 0.01 {
            let earTop: CGFloat = S.ears.isEmpty ? 0 : 12
            bubble(ctx, text, alpha: CGFloat(p.bubbleAlpha), at: CGPoint(x: F.x, y: F.y + hop + top + earTop * k + 4))
        }
    }
}
