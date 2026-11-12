// Sim.swift — Drift's weather simulation.
// Pure Foundation (no AppKit) so it stays small and testable.
// All coordinates are global Quartz points: origin at the top-left of the main display, y grows downward.

import Foundation

// MARK: - Colours & seasons

struct RGBA {
    var r: Double, g: Double, b: Double, a: Double
    init(_ hex: UInt32, _ a: Double = 1) {
        r = Double((hex >> 16) & 0xff) / 255
        g = Double((hex >> 8) & 0xff) / 255
        b = Double(hex & 0xff) / 255
        self.a = a
    }
}

enum Kind { case snow, petal, spring, flower, leaf, rain, star }

struct Season {
    let id: String
    let label: String
    let kind: Kind
    let symbol: String              // SF Symbol for the menu bar
    var base: Double                // particles on a 1400pt-wide screen at "Steady"
    var size: ClosedRange<Double>
    var dm: Double                  // drawn size = size * dm
    var vy: ClosedRange<Double>     // fall speed, pt/s
    var sway: Double = 0, swayF: Double = 0, spin: Double = 0
    var flip = false, flipF: Double = 0
    var windK: Double = 1
    var grain: Double = 3           // pile area each landing adds
    var maxH: Double = 30           // tallest a drift can get
    var slope: Double = 1.2         // how steep a drift can be per column
    var evap: Double = 0            // rain dries up
    var twinkle = false
    var farFrac = 0.35              // share of particles in the blurred background layer
    var pile: RGBA, crest: RGBA, shade: RGBA
    var decalP: Double = 0          // chance a landed petal/leaf stays visible on the drift
    var decMax = 0
    var carrot = false
    var sizeAvg: Double { (size.lowerBound + size.upperBound) / 2 }
}

extension Season {
    static let all: [Season] = [
        Season(id: "snow", label: "Snow", kind: .snow, symbol: "snowflake",
               base: 170, size: 1.2...3.4, dm: 3.2, vy: 30...70,
               sway: 14, swayF: 0.9,
               windK: 1, grain: 3.5, maxH: 44, slope: 1.5, farFrac: 0.4,
               pile: RGBA(0xEDF3FC), crest: RGBA(0xFFFFFF), shade: RGBA(0xA9BCDD),
               carrot: true),
        Season(id: "sakura", label: "Sakura", kind: .petal, symbol: "camera.macro",
               base: 80, size: 4...7, dm: 2.5, vy: 40...75,
               sway: 38, swayF: 1.6, spin: 2.2, flip: true, flipF: 3.5,
               windK: 1.3, grain: 4, maxH: 22, slope: 1.1, farFrac: 0.3,
               pile: RGBA(0xF4B3CB), crest: RGBA(0xFFE3EE), shade: RGBA(0xC9708F),
               decalP: 0.9, decMax: 300),
        Season(id: "spring", label: "Spring", kind: .spring, symbol: "leaf",
               base: 60, size: 4...8, dm: 2.8, vy: 16...38,
               sway: 26, swayF: 0.7, spin: 1,
               windK: 1.5, grain: 6, maxH: 18, slope: 1, farFrac: 0.3,
               pile: RGBA(0x6FAE52), crest: RGBA(0xB9E48E), shade: RGBA(0x3F7A2E),
               decalP: 0.85, decMax: 240),
        Season(id: "flowers", label: "Flowers", kind: .flower, symbol: "camera.macro.circle",
               base: 70, size: 4...6.5, dm: 2.6, vy: 45...80,
               sway: 26, swayF: 1.2, spin: 1.4, flip: true, flipF: 2.5,
               windK: 1.1, grain: 5, maxH: 22, slope: 1.2, farFrac: 0.3,
               pile: RGBA(0x5C934D), crest: RGBA(0x95C77E), shade: RGBA(0x355F2C),
               decalP: 0.95, decMax: 320),
        Season(id: "autumn", label: "Autumn", kind: .leaf, symbol: "leaf.fill",
               base: 45, size: 7...12, dm: 2.3, vy: 50...95,
               sway: 55, swayF: 1.1, spin: 2.6, flip: true, flipF: 2.2,
               windK: 1.4, grain: 9, maxH: 30, slope: 1.4, farFrac: 0.22,
               pile: RGBA(0x93451F), crest: RGBA(0xD37A3A), shade: RGBA(0x5E260F),
               decalP: 1, decMax: 280),
        Season(id: "rain", label: "Rain", kind: .rain, symbol: "cloud.rain",
               base: 230, size: 1...1, dm: 1, vy: 650...900,
               windK: 2.2, grain: 1.5, maxH: 3, slope: 0.3, evap: 0.25, farFrac: 0.45,
               pile: RGBA(0x96C3E6, 0.5), crest: RGBA(0xE1F0FC, 0.85), shade: RGBA(0x5082AA, 0.6)),
        Season(id: "stardust", label: "Stardust", kind: .star, symbol: "sparkles",
               base: 120, size: 1.5...3.5, dm: 3.6, vy: 20...45,
               sway: 8, swayF: 0.5,
               windK: 0.8, grain: 2.5, maxH: 14, slope: 0.8, twinkle: true, farFrac: 0.45,
               pile: RGBA(0x9F8BEB), crest: RGBA(0xF1E9FF), shade: RGBA(0x5B48B0),
               decalP: 0.6, decMax: 220),
    ]

    /// Season that matches the calendar (northern hemisphere).
    static func forDate(_ d: Date) -> Season {
        let m = Calendar.current.component(.month, from: d)
        let id: String
        switch m {
        case 12, 1, 2: id = "snow"
        case 3, 4: id = "sakura"
        case 5: id = "spring"
        case 6, 7, 8: id = "flowers"
        default: id = "autumn"
        }
        return all.first { $0.id == id } ?? all[0]
    }
}

/// Small deterministic hash, used for stable "random" details (glints, frost, sparkle texture).
@inline(__always) func hash01(_ a: Int, _ b: Int) -> Double {
    var x = UInt64(bitPattern: Int64(a &* 73_856_093 ^ b &* 19_349_663))
    x ^= x >> 33; x = x &* 0xff51afd7ed558ccd; x ^= x >> 33; x = x &* 0xc4ceb9fe1a85ec53; x ^= x >> 33
    return Double(x % 1_000_000) / 1_000_000
}

// MARK: - Surfaces (window tops, the Dock, the screen bottom)

enum SurfaceKind { case window, dock, ground }

struct Decal { var c: Int; var y: Double; var sprite: Int; var rot: Double; var size: Double }

struct Icicle { var c: Int; var len: Double; var maxLen: Double; var drip: Double; var width: Double }

final class Ball {
    var x: Double           // centre, relative to the surface's left edge
    var r: Double
    weak var on: Ball?      // the ball this one is stacked on
    let seed: Double
    var rot = 0.0
    var byPip = false
    init(x: Double, r: Double, seed: Double) { self.x = x; self.r = r; self.seed = seed }
}

final class Surface {
    static let colW = 3.0
    let id: Int
    var kind: SurfaceKind = .window
    var x = 0.0, y = 0.0, w = 0.0
    var cw = 3.0
    var h: [Double] = []
    var visible: [Bool] = []
    var decals: [Decal] = []
    var balls: [Ball] = []
    var icicles: [Icicle] = []
    var version = 0
    var gen = 0
    var maxScale = 1.0
    var vx = 0.0, vy = 0.0      // how fast the window is moving (pt/s)

    init(id: Int) { self.id = id }

    var hasContent: Bool { !balls.isEmpty || !icicles.isEmpty || h.contains { $0 > 0.15 } }

    func col(_ gx: Double) -> Int { min(h.count - 1, max(0, Int((gx - x) / cw))) }

    func layout(x: Double, y: Double, w: Double) {
        self.x = x; self.y = y; self.w = w
        let n = max(1, Int(w / Surface.colW))
        if n != h.count {
            let old = h
            var nh = [Double](repeating: 0, count: n)
            if !old.isEmpty { for i in 0..<n { nh[i] = old[i * old.count / n] } }
            h = nh
            visible = [Bool](repeating: true, count: n)
            decals.removeAll { $0.c >= n }
            icicles.removeAll { $0.c >= n }
            version += 1
        }
        cw = w / Double(n)
        for b in balls { b.x = min(max(b.r, b.x), max(b.r, w - b.r)) }
    }
}

// MARK: - Particles

struct Particle {
    var x = 0.0, y = 0.0, py = 0.0, s = 1.0, vx = 0.0, vy = 0.0
    var ph = 0.0, rot = 0.0, spin = 0.0, fl = 0.0, tw = 0.0
    var sprite = 0
    var far = false
    var alpha = 1.0
    var life = 0.0
    var d = 0.0
    var streak = false          // drawn as a thin falling streak (rain, icicle drips)
}

/// A raindrop stuck to the "glass" of the screen. It waits, then slides down leaving a trail.
struct GlassDrop {
    var x = 0.0, y = 0.0, r = 2.0
    var vy = 0.0
    var wait = 0.0
    var trail = 0.0
    var wob = 0.0
}

struct Meteor { var x = 0.0, y = 0.0, vx = 0.0, vy = 0.0, life = 0.0, maxLife = 1.0 }

final class ScreenSim {
    var frame: CGRect
    var particles: [Particle] = []
    var flings: [Particle] = []
    var drops: [GlassDrop] = []
    var meteors: [Meteor] = []
    var refill = true
    var nextMeteor = 4.0
    init(frame: CGRect) { self.frame = frame }
}

// MARK: - Engine

final class Engine {
    struct SurfaceInput {
        let id: Int
        let rect: CGRect
        var kind: SurfaceKind = .window
        var maxScale = 1.0
        var occludes = true     // hides surfaces behind it
        var isSurface = true    // things can settle on its top edge
    }

    private(set) var season: Season = Season.all[0]
    private(set) var spriteNear = 1
    private(set) var spriteFar = 1
    var density = 1.0
    var powerScale = 1.0
    var wind = 0                // −4 … 4, set by the user
    var gusts = true
    var icicles = true
    var glassDrops = true
    var paused = false
    var screens: [ScreenSim] = []
    private(set) var surfaces: [Surface] = []
    private(set) var t = 0.0
    private(set) var windNow = 0.0
    private(set) var rolling: (s: Surface, b: Ball)?
    private(set) var swirlT = 0.0
    private(set) var swirlX = 0.0, swirlY = 0.0
    private var byId: [Int: Surface] = [:]
    private var gen = 0
    private var lastUpdateT = 0.0

    var windPx: Double { windNow * season.windK * 32 }

    func setSeason(_ s: Season, near: Int, far: Int) {
        season = s
        spriteNear = max(1, near)
        spriteFar = max(0, far)
        for sc in screens {
            sc.particles.removeAll(); sc.flings.removeAll(); sc.drops.removeAll(); sc.meteors.removeAll()
            sc.refill = true
        }
        clearAll()
    }

    func resume() { for sc in screens where sc.particles.isEmpty { sc.refill = true } }

    func surface(_ id: Int?) -> Surface? { id.flatMap { byId[$0] } }

    func target(for sc: ScreenSim) -> Int {
        let k = max(0.45, Double(sc.frame.width) / 1400)
        return min(650, Int(season.base * density * powerScale * k))
    }

    // MARK: stepping

    func step(_ dt: Double) {
        t += dt
        // Natural wind: the user's setting plus slow, layered gusts.
        let g = sin(t * 0.13) * 0.6 + sin(t * 0.37 + 1.3) * 0.3 + sin(t * 0.71 + 2.1) * 0.15
        windNow = Double(wind) + (gusts ? g * (wind == 0 ? 0.45 : 0.9) : 0)
        if swirlT > 0 { swirlT = max(0, swirlT - dt) }

        if !paused { for sc in screens { stepFalling(sc, dt) } }
        for sc in screens {
            stepFlings(sc, dt)
            if season.kind == .rain && glassDrops && !paused { stepDrops(sc, dt) } else if !sc.drops.isEmpty { sc.drops.removeAll() }
            if season.kind == .star && !paused { stepMeteors(sc, dt) }
        }
        if season.evap > 0 {
            let e = season.evap * dt
            for s in surfaces {
                var changed = false
                for i in s.h.indices where s.h[i] > 0 { s.h[i] = max(0, s.h[i] - e); changed = true }
                if changed { s.version += 1 }
            }
        }
        if season.kind == .snow && icicles { stepIcicles(dt) }
    }

    private func spawn(_ p: inout Particle, in f: CGRect, initial: Bool, far: Bool) {
        let S = season
        let fx = Double(f.minX), fy = Double(f.minY), fw = Double(f.width), fh = Double(f.height)
        let avg = (S.vy.lowerBound + S.vy.upperBound) / 2
        let shift = max(-fw * 0.6, min(fw * 0.6, -windPx * (fh / avg) * 0.6))
        p.far = far && spriteFar > 0
        let z = Double.random(in: 0...1)
        let sizeK = p.far ? 0.35 + 0.25 * z : 0.8 + 0.45 * z
        let speedK = p.far ? 0.5 + 0.2 * z : 0.85 + 0.3 * z
        p.x = fx + Double.random(in: -60...(fw + 60)) + (initial ? 0 : shift)
        p.y = initial ? fy + Double.random(in: -20...fh) : fy + Double.random(in: -80...(-10))
        p.py = p.y
        p.s = Double.random(in: S.size) * sizeK
        p.vy = Double.random(in: S.vy) * speedK
        p.vx = 0
        p.alpha = p.far ? 0.3 + 0.35 * z : 0.85 + 0.15 * z
        p.ph = Double.random(in: 0...(2 * Double.pi))
        p.rot = Double.random(in: 0...(2 * Double.pi))
        p.spin = S.spin > 0 ? Double.random(in: -S.spin...S.spin) : 0
        p.fl = Double.random(in: 0...(2 * Double.pi))
        p.tw = Double.random(in: 0...(2 * Double.pi))
        p.sprite = p.far ? spriteNear + Int.random(in: 0..<max(1, spriteFar)) : Int.random(in: 0..<spriteNear)
        p.streak = S.kind == .rain
    }

    private func stepFalling(_ sc: ScreenSim, _ dt: Double) {
        let nearWant = target(for: sc)
        let farWant = spriteFar > 0 ? Int(Double(nearWant) * season.farFrac / (1 - season.farFrac)) : 0
        let want = nearWant + farWant
        let f = sc.frame
        var farCount = 0
        for p in sc.particles where p.far { farCount += 1 }
        while sc.particles.count < want {
            var p = Particle()
            let far = farCount < farWant
            spawn(&p, in: f, initial: sc.refill, far: far)
            if far { farCount += 1 }
            sc.particles.append(p)
        }
        if sc.particles.count > want {
            for p in sc.particles[want...] where p.far { farCount -= 1 }
            sc.particles.removeLast(sc.particles.count - want)
        }
        sc.refill = false

        let S = season, wx = windPx
        let lim = Double(f.width) * 0.6 + 120
        let minX = Double(f.minX) - lim, maxX = Double(f.maxX) + lim, maxY = Double(f.maxY) + 30
        let swirling = swirlT > 0
        let sw = min(1, swirlT / 1.2)
        for i in sc.particles.indices {
            var p = sc.particles[i]
            p.py = p.y
            let depthK = p.far ? 0.55 : 1
            var dx = (wx * depthK + sin(t * S.swayF + p.ph) * S.sway * depthK) * dt
            var dy = p.vy * dt
            if swirling {
                // Snow-globe vortex around where the mouse was shaken.
                let rx = p.x - swirlX, ry = p.y - swirlY
                let d = max(40, (rx * rx + ry * ry).squareRoot())
                let k = sw * 900 * min(1, 260 / d)
                dx += (-ry / d * k + rx / d * 120 * sw) * dt
                dy += (rx / d * k - 160 * sw) * dt
            }
            p.x += dx
            p.y += dy
            p.vx = dx / max(dt, 0.001)
            p.rot += p.spin * dt
            p.fl += S.flipF * dt
            if p.y > maxY || p.x < minX || p.x > maxX || p.y < Double(f.minY) - 400 {
                spawn(&p, in: f, initial: false, far: p.far)
                sc.particles[i] = p
                continue
            }
            if !p.far && dy > 0 {
                for s in surfaces {
                    if s.h.isEmpty || p.x < s.x || p.x >= s.x + s.w { continue }
                    let c = min(s.h.count - 1, Int((p.x - s.x) / s.cw))
                    if !s.visible[c] { continue }
                    let top = s.y - s.h[c]
                    if p.py <= top && p.y >= top {
                        land(s, c, p, sc)
                        spawn(&p, in: f, initial: false, far: false)
                        break
                    }
                }
            }
            sc.particles[i] = p
        }
    }

    private func stepFlings(_ sc: ScreenSim, _ dt: Double) {
        if sc.flings.isEmpty { return }
        let maxY = Double(sc.frame.maxY) + 20
        var j = 0
        for i in sc.flings.indices {
            var f = sc.flings[i]
            f.vy += 520 * dt
            f.x += f.vx * dt
            f.y += f.vy * dt
            f.rot += f.spin * dt
            f.life -= dt
            if f.life > 0 && f.y < maxY { sc.flings[j] = f; j += 1 }
        }
        sc.flings.removeLast(sc.flings.count - j)
    }

    private func stepDrops(_ sc: ScreenSim, _ dt: Double) {
        let f = sc.frame
        let cap = Int(36 * density * powerScale)
        if sc.drops.count < cap && Double.random(in: 0..<1) < dt * 1.6 * density {
            var d = GlassDrop()
            d.x = Double.random(in: Double(f.minX)...Double(f.maxX))
            d.y = Double.random(in: Double(f.minY)...(Double(f.minY) + Double(f.height) * 0.85))
            d.r = Double.random(in: 1.6...4.2)
            d.wait = Double.random(in: 2...12)
            d.wob = Double.random(in: 0...6.28)
            sc.drops.append(d)
        }
        let maxY = Double(f.maxY) + 10
        var j = 0
        for i in sc.drops.indices {
            var d = sc.drops[i]
            if d.wait > 0 {
                d.wait -= dt
                d.trail = max(0, d.trail - dt * 20)
            } else {
                d.vy = min(40 + d.r * 30, d.vy + (20 + d.r * 25) * dt)
                d.y += d.vy * dt
                d.x += sin(t * 3 + d.wob) * 6 * dt
                d.trail = min(60 + d.r * 10, d.trail + d.vy * dt)
                if Double.random(in: 0..<1) < dt * 0.6 { d.wait = Double.random(in: 0.2...1.2); d.vy = 0 }
            }
            if d.y < maxY { sc.drops[j] = d; j += 1 }
        }
        sc.drops.removeLast(sc.drops.count - j)
        // A sliding drop swallows the small ones it runs into.
        if sc.drops.count > 1 {
            for a in sc.drops.indices where sc.drops[a].wait <= 0 && sc.drops[a].r > 0 {
                for b in sc.drops.indices where b != a && sc.drops[b].r > 0 {
                    let dx = sc.drops[a].x - sc.drops[b].x, dy = sc.drops[a].y - sc.drops[b].y
                    if dx * dx + dy * dy < pow(sc.drops[a].r + sc.drops[b].r, 2) {
                        sc.drops[a].r = min(6, (sc.drops[a].r * sc.drops[a].r + sc.drops[b].r * sc.drops[b].r).squareRoot())
                        sc.drops[b].r = 0
                    }
                }
            }
            sc.drops.removeAll { $0.r <= 0 }
        }
    }

    private func stepMeteors(_ sc: ScreenSim, _ dt: Double) {
        sc.nextMeteor -= dt
        let f = sc.frame
        if sc.nextMeteor <= 0 {
            sc.nextMeteor = Double.random(in: 7...18)
            var m = Meteor()
            let dir = Bool.random() ? 1.0 : -1.0
            m.x = Double(f.midX) + Double.random(in: -0.4...0.4) * Double(f.width)
            m.y = Double(f.minY) + Double.random(in: 40...(Double(f.height) * 0.35))
            let sp = Double.random(in: 900...1400)
            m.vx = dir * sp * 0.85; m.vy = sp * 0.45
            m.maxLife = Double.random(in: 0.6...1.1); m.life = m.maxLife
            sc.meteors.append(m)
        }
        for i in sc.meteors.indices {
            sc.meteors[i].x += sc.meteors[i].vx * dt
            sc.meteors[i].y += sc.meteors[i].vy * dt
            sc.meteors[i].life -= dt
        }
        sc.meteors.removeAll { $0.life <= 0 }
    }

    // MARK: drifts

    private func land(_ s: Surface, _ c: Int, _ p: Particle, _ sc: ScreenSim) {
        let S = season
        let half = max(0, Int(p.s * S.dm / s.cw / 2.5))
        let lo = max(0, c - half), hi = min(s.h.count - 1, c + half)
        let add = S.grain * (p.s / S.sizeAvg) / Double(hi - lo + 1)
        let cap = S.maxH * s.maxScale
        for i in lo...hi { s.h[i] = min(cap, s.h[i] + add) }
        settle(s, c, half + 10)
        if S.decalP > 0 && Double.random(in: 0..<1) < S.decalP {
            s.decals.append(Decal(c: c, y: max(0, s.h[c] - Double.random(in: 0..<1) * S.maxH * 0.15),
                                  sprite: p.sprite, rot: p.rot, size: p.s * S.dm * 0.85))
            if s.decals.count > S.decMax { s.decals.removeFirst(s.decals.count - S.decMax) }
        }
        if S.kind == .rain && sc.flings.count < 160 {
            for _ in 0..<2 {
                var f = Particle()
                f.x = p.x; f.y = s.y - s.h[c]
                f.vx = Double.random(in: -60...60); f.vy = Double.random(in: -140...(-60))
                f.life = 0.35; f.d = 1.6
                sc.flings.append(f)
            }
        }
        s.version += 1
    }

    private func settle(_ s: Surface, _ c: Int, _ r: Int) {
        let n = s.h.count, sl = season.slope
        let a = max(0, c - r), b = min(n - 1, c + r)
        if a > b { return }
        for _ in 0..<4 {
            for i in a...b {
                let L = i > 0 ? s.h[i - 1] : 0
                if s.h[i] - L > sl {
                    let m = (s.h[i] - L - sl) / 2
                    s.h[i] -= m
                    if i > 0 { s.h[i - 1] += m }
                }
                let R = i < n - 1 ? s.h[i + 1] : 0
                if s.h[i] - R > sl {
                    let m = (s.h[i] - R - sl) / 2
                    s.h[i] -= m
                    if i < n - 1 { s.h[i + 1] += m }
                }
            }
        }
    }

    private func stepIcicles(_ dt: Double) {
        for s in surfaces where s.kind == .window && !s.h.isEmpty {
            var changed = false
            // new icicles where the drift is deep
            let cap = max(1, Int(s.w / 55))
            if s.icicles.count < cap && Double.random(in: 0..<1) < dt * 0.5 {
                let c = Int.random(in: 0..<s.h.count)
                let edgeGap = Int(14 / s.cw)
                if s.h[c] > 12 && s.visible[c] && c > edgeGap && c < s.h.count - edgeGap
                    && !s.icicles.contains(where: { abs($0.c - c) < 6 }) {
                    s.icicles.append(Icicle(c: c, len: 1, maxLen: Double.random(in: 6...24), drip: Double.random(in: 3...10),
                                            width: Double.random(in: 2.2...4.2)))
                    changed = true
                }
            }
            var keep: [Icicle] = []
            for var ic in s.icicles {
                if s.h[ic.c] < 2 || !s.visible[ic.c] {
                    // drift gone: the icicle breaks off
                    fling(x: s.x + (Double(ic.c) + 0.5) * s.cw, y: s.y + ic.len * 0.5, vx: 0, count: 2, life: 0.8...1.4)
                    changed = true
                    continue
                }
                if ic.len < ic.maxLen && s.h[ic.c] > 6 { ic.len = min(ic.maxLen, ic.len + dt * 0.35); changed = true }
                ic.drip -= dt
                if ic.drip <= 0 && ic.len > 4 {
                    ic.drip = Double.random(in: 4...14)
                    drip(x: s.x + (Double(ic.c) + 0.5) * s.cw, y: s.y + ic.len)
                }
                keep.append(ic)
            }
            s.icicles = keep
            if changed { s.version += 1 }
        }
    }

    private func drip(x: Double, y: Double) {
        let pt = CGPoint(x: x, y: y)
        guard let sc = screens.first(where: { $0.frame.contains(pt) }) else { return }
        var f = Particle()
        f.x = x; f.y = y; f.vx = 0; f.vy = 20
        f.life = 1.6; f.d = 2.2; f.streak = true; f.sprite = 0
        sc.flings.append(f)
    }

    /// Pieces that fly off when brushed, shaken or when a window closes.
    func fling(x: Double, y: Double, vx: Double, count: Int, life: ClosedRange<Double> = 0.5...1.1) {
        let pt = CGPoint(x: x, y: y)
        guard let sc = screens.first(where: { $0.frame.contains(pt) }) ?? screens.first else { return }
        let S = season
        for _ in 0..<count where sc.flings.count < 300 {
            var f = Particle()
            f.x = x + Double.random(in: -4...4)
            f.y = y - Double.random(in: 0...4)
            f.vx = vx * 0.6 + Double.random(in: -70...70)
            f.vy = Double.random(in: -260...(-90))
            f.life = Double.random(in: life)
            f.d = S.kind == .rain ? 1.8 : Double.random(in: S.size) * S.dm * (S.kind == .snow ? 1.1 : 1)
            f.sprite = Int.random(in: 0..<spriteNear)
            f.rot = Double.random(in: 0...(2 * Double.pi))
            f.spin = Double.random(in: -6...6)
            sc.flings.append(f)
        }
    }

    /// The cursor brush: pushes drifts down out of a circle around the pointer.
    func sweep(x: Double, y: Double, vx: Double, radius R: Double = 20) {
        for s in surfaces {
            if s.h.isEmpty || x < s.x - R || x > s.x + s.w + R { continue }
            if y > s.y + R || y < s.y - season.maxH * s.maxScale - R { continue }
            let n = s.h.count
            let c0 = max(0, Int(floor((x - R - s.x) / s.cw)))
            let c1 = min(n - 1, Int(ceil((x + R - s.x) / s.cw)))
            if c0 > c1 { continue }
            var removed = 0.0, ry = s.y
            for c in c0...c1 where s.visible[c] {
                let dx = s.x + (Double(c) + 0.5) * s.cw - x
                if abs(dx) > R { continue }
                let lim = max(0, s.y - (y + (R * R - dx * dx).squareRoot()))
                if s.h[c] > lim { removed += s.h[c] - lim; ry = s.y - s.h[c]; s.h[c] = lim }
            }
            if removed > 0.5 {
                s.decals.removeAll { $0.c < n && $0.y > s.h[$0.c] + 0.5 }
                fling(x: x, y: ry, vx: vx, count: min(10, 1 + Int(removed * 0.35)))
                s.version += 1
            }
        }
    }

    /// Knock a fraction of a drift off its surface (window dragged, closed, or "Shake off").
    func spill(_ s: Surface, fraction: Double, maxCount: Int = 40) {
        guard !s.h.isEmpty else { return }
        let f = min(1, max(0, fraction))
        var total = 0.0
        for i in s.h.indices { let a = s.h[i] * f; total += a; s.h[i] -= a }
        if f >= 0.999 { s.decals.removeAll() } else { s.decals.removeAll { $0.c < s.h.count && $0.y > s.h[$0.c] + 0.5 } }
        let count = min(maxCount, Int(total / 6))
        for _ in 0..<count {
            let c = Int.random(in: 0..<s.h.count)
            fling(x: s.x + (Double(c) + 0.5) * s.cw, y: s.y - 2, vx: Double.random(in: -80...80), count: 1, life: 1.2...2.2)
        }
        if f > 0.5 && !s.balls.isEmpty {
            for b in s.balls { let p = ballPos(s, b); fling(x: p.x, y: p.y, vx: 0, count: 10, life: 1...1.8) }
            s.balls.removeAll()
            if rolling?.s === s { rolling = nil }
        }
        if f > 0.5 && !s.icicles.isEmpty {
            for ic in s.icicles { fling(x: s.x + (Double(ic.c) + 0.5) * s.cw, y: s.y + ic.len / 2, vx: 0, count: 2, life: 0.8...1.4) }
            s.icicles.removeAll()
        }
        s.version += 1
    }

    func shakeOffAll() { for s in surfaces where s.hasContent { spill(s, fraction: 1, maxCount: 40) } }

    func clearAll() {
        for s in surfaces {
            s.h = [Double](repeating: 0, count: s.h.count)
            s.decals.removeAll(); s.balls.removeAll(); s.icicles.removeAll(); s.version += 1
        }
        rolling = nil
    }

    /// Snow-globe moment: everything near the point swirls up and drifts nearby are blown loose.
    func snowGlobe(x: Double, y: Double) {
        swirlT = 2.4; swirlX = x; swirlY = y
        for s in surfaces where s.hasContent {
            let cx = min(max(x, s.x), s.x + s.w)
            let d = hypot(cx - x, s.y - y)
            if d < 500 { spill(s, fraction: 0.45 * (1 - d / 500), maxCount: 16) }
        }
        if !paused {
            for _ in 0..<3 { fling(x: x, y: y, vx: Double.random(in: -300...300), count: 8, life: 0.8...1.6) }
        }
    }

    // MARK: window tracking

    /// `list` is ordered front-to-back, like CGWindowListCopyWindowInfo.
    func updateSurfaces(_ list: [SurfaceInput]) {
        gen += 1
        let dt = max(0.001, t - lastUpdateT)
        lastUpdateT = t
        var order: [Surface] = []
        var fronts: [CGRect] = []
        for inp in list {
            let r = inp.rect
            if inp.isSurface {
                let nx = Double(r.minX), ny = Double(r.minY), nw = Double(r.width)
                let s: Surface
                if let old = byId[inp.id] {
                    s = old
                    let dx = nx - s.x, dy = ny - s.y
                    s.layout(x: nx, y: ny, w: nw)
                    s.vx = dx / dt; s.vy = dy / dt
                    let moved = (dx * dx + dy * dy).squareRoot()
                    if moved > 0.5 { s.version += 1 }
                    if moved > 4 && s.hasContent { spill(s, fraction: moved / 90, maxCount: 14) }
                } else {
                    s = Surface(id: inp.id)
                    s.layout(x: nx, y: ny, w: nw)
                    byId[inp.id] = s
                }
                s.kind = inp.kind
                s.gen = gen
                s.maxScale = inp.maxScale
                order.append(s)

                // Hide columns covered by windows in front of this one.
                let ey = CGFloat(s.y + 1)
                let cands = fronts.filter { $0.minY <= ey && $0.maxY > ey && $0.maxX > r.minX && $0.minX < r.maxX }
                var changed = false
                for c in 0..<s.h.count {
                    let px = CGFloat(s.x + (Double(c) + 0.5) * s.cw)
                    let v = !cands.contains { px >= $0.minX && px < $0.maxX }
                    if s.visible[c] != v { s.visible[c] = v; changed = true }
                }
                if changed { s.version += 1 }
            }
            if inp.occludes { fronts.append(r) }
        }
        for s in surfaces where s.gen != gen {
            if s.hasContent { spill(s, fraction: 1, maxCount: 30) }
            byId[s.id] = nil
            if rolling?.s === s { rolling = nil }
        }
        surfaces = order
    }

    // MARK: snowballs

    func ballPos(_ s: Surface, _ b: Ball) -> (x: Double, y: Double) {
        if let o = b.on { let p = ballPos(s, o); return (p.x, p.y - o.r * 0.8 - b.r) }
        let x = s.x + min(max(b.r, b.x), max(b.r, s.w - b.r))
        return (x, s.y - b.r * 0.92)
    }

    /// Height above the surface edge that its drawing needs.
    func contentHeight(_ s: Surface) -> Double {
        var top = (s.h.max() ?? 0)
        for b in s.balls { let p = ballPos(s, b); top = max(top, s.y - (p.y - b.r)) }
        if !s.decals.isEmpty { top += 14 }
        return top
    }

    private func surfaceNear(x: Double, y: Double, below: Double) -> Surface? {
        var best: Surface? = nil
        var bd = Double.infinity
        for s in surfaces {
            if s.h.isEmpty || x < s.x - 6 || x > s.x + s.w + 6 { continue }
            let c = s.col(x)
            if !s.visible[c] { continue }
            let dy = y - s.y
            if dy < -(season.maxH * s.maxScale + 50) || dy > below { continue }
            if abs(dy) < bd { bd = abs(dy); best = s }
        }
        return best
    }

    /// Call every frame. `active` = the roll modifier is held.
    func rollUpdate(x: Double, y: Double, active: Bool) {
        if active {
            if let r = rolling { roll(r.s, r.b, toX: x) }
            else if let s = surfaceNear(x: x, y: y, below: 26) {
                let b = Ball(x: min(max(4, x - s.x), max(4, s.w - 4)), r: 4, seed: Double.random(in: 0...6.28))
                s.balls.append(b)
                rolling = (s, b)
                consume(s, b)
                s.version += 1
            }
        } else if let r = rolling {
            release(r.s, r.b)
            rolling = nil
        }
    }

    /// Packs the drift under a ball into it. Returns the snow area taken.
    @discardableResult
    func consume(_ s: Surface, _ b: Ball, reach: Double = 0.9) -> Double {
        let n = s.h.count
        let c0 = max(0, Int(floor((b.x - b.r * reach) / s.cw)))
        let c1 = min(n - 1, Int(ceil((b.x + b.r * reach) / s.cw)))
        guard c0 <= c1 else { return 0 }
        var area = 0.0
        for c in c0...c1 where s.visible[c] { area += s.h[c] * s.cw; s.h[c] = 0 }
        if area > 0 {
            b.r = min(48, (b.r * b.r + area * 0.9 / Double.pi).squareRoot())
            s.decals.removeAll { $0.c >= c0 && $0.c <= c1 }
            s.version += 1
        }
        return area
    }

    private func roll(_ s: Surface, _ b: Ball, toX x: Double) {
        let nx = min(max(b.r, x - s.x), max(b.r, s.w - b.r))
        if abs(nx - b.x) < 0.01 { return }
        b.rot += (nx - b.x) / max(4, b.r)
        b.x = nx
        consume(s, b)
        s.version += 1
    }

    private func release(_ s: Surface, _ b: Ball) {
        if b.r < 6 { s.balls.removeAll { $0 === b }; s.version += 1; return }
        func depth(_ o: Ball) -> Int { o.on.map { 1 + depth($0) } ?? 1 }
        let bp = ballPos(s, b)
        for o in s.balls where o !== b && !s.balls.contains(where: { $0.on === o }) {
            let op = ballPos(s, o)
            if abs(op.x - bp.x) < o.r * 0.9 && depth(o) < 3 { b.on = o; b.x = o.x; break }
        }
        if s.balls.count > 12 { s.balls.removeFirst() }
        s.version += 1
    }

    // MARK: helpers for Pip

    /// Removes one falling near-layer particle around a point (Pip catching a flake). Returns true if caught.
    func catchParticle(x: Double, y: Double, radius: Double) -> Bool {
        for sc in screens {
            for i in sc.particles.indices where !sc.particles[i].far {
                let p = sc.particles[i]
                if abs(p.x - x) < radius && abs(p.y - y) < radius {
                    sc.particles[i].y = Double(sc.frame.maxY) + 100   // respawns next frame
                    return true
                }
            }
        }
        return false
    }

    /// Footprint: presses the drift down a little under (gx).
    func press(_ s: Surface, at gx: Double) {
        guard !s.h.isEmpty else { return }
        let c = s.col(gx)
        var hit = false
        for i in max(0, c - 1)...min(s.h.count - 1, c + 1) where s.h[i] > 2.5 {
            s.h[i] = max(1.5, s.h[i] * 0.72); hit = true
        }
        if hit { s.version += 1 }
    }
}
