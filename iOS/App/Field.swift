import CoreMotion
import SwiftUI

/// Falling weather for the app screen. Tilt the phone and it falls "down"; shake it for a snow-globe swirl.
/// Flakes that land build a drift along the bottom of the screen.
final class Field: ObservableObject {
    struct Particle {
        var x: Double, y: Double
        var vx: Double, vy: Double
        var size: Double
        var depth: Double      // 0.35 (far) ... 1 (near)
        var angle: Double, spin: Double
        var phase: Double
        var colour: Int
    }

    private(set) var particles: [Particle] = []
    private var pile: [Double] = []           // drift height per column
    private let column = 6.0
    private var last: Date?
    private(set) var gx = 0.0, gy = 1.0
    private var swirl = 0.0
    private let motion = CMMotionManager()
    var onShake: (() -> Void)?
    private var lastShake = Date.distantPast

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates()
    }

    func shake() {
        swirl = 1.0
        for i in particles.indices {
            particles[i].vx += Double.random(in: -260...260)
            particles[i].vy -= Double.random(in: 80...320)
        }
        for i in pile.indices { pile[i] *= 0.15 }
    }

    func step(now: Date, size: CGSize, season: PipSeason) {
        let dt = min(1.0 / 20.0, last.map { now.timeIntervalSince($0) } ?? 0)
        last = now
        let w = Double(size.width), h = Double(size.height)
        guard w > 0, h > 0 else { return }
        let cols = Int(w / column) + 1
        if pile.count != cols { pile = Array(repeating: 0, count: cols) }

        if let m = motion.deviceMotion {
            let tx = m.gravity.x, ty = -m.gravity.y
            gx += (tx - gx) * 0.12
            gy += (ty - gy) * 0.12
            let a = m.userAcceleration
            if (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot() > 1.5, now.timeIntervalSince(lastShake) > 1.2 {
                lastShake = now
                shake()
                onShake?()
            }
        }
        let target = season == .stardust ? 70 : (season == .snow ? 160 : 70)
        while particles.count < target { particles.append(spawn(w: w, h: h, season: season, anywhere: particles.count < target / 2 && last != nil)) }
        if particles.count > target { particles.removeLast(particles.count - target) }

        swirl = max(0, swirl - dt * 0.4)
        let fall = season == .snow ? 46.0 : (season == .stardust ? 0 : 38.0)
        let t = now.timeIntervalSinceReferenceDate
        for i in particles.indices {
            var p = particles[i]
            let sway = sin(t * 1.3 + p.phase) * 18 * p.depth
            let ax = gx * fall * p.depth + sway
            let ay = gy * fall * p.depth
            if swirl > 0 {
                let cx = w / 2, cy = h / 2
                p.vx += (-(p.y - cy) * 0.9) * swirl * dt
                p.vy += ((p.x - cx) * 0.9) * swirl * dt
            }
            p.vx += (ax - p.vx) * min(1, dt * 1.6)
            p.vy += (ay - p.vy) * min(1, dt * 1.6)
            p.x += p.vx * dt
            p.y += p.vy * dt
            p.angle += p.spin * dt
            // land on the drift (front flakes only)
            if season != .stardust, p.depth > 0.8, gy > 0.5, swirl < 0.1 {
                let c = max(0, min(cols - 1, Int(p.x / column)))
                if p.y >= h - pile[c] {
                    if season == .snow {
                        addToPile(c, p.size * 0.35)
                    }
                    p = spawn(w: w, h: h, season: season, anywhere: false)
                }
            }
            if p.y > h + 30 || p.y < -120 || p.x < -60 || p.x > w + 60 {
                p = spawn(w: w, h: h, season: season, anywhere: false)
                if gy < -0.3 { p.y = h + 20 }
                if gx > 0.6 { p.x = -20; p.y = Double.random(in: 0...h) }
                if gx < -0.6 { p.x = w + 20; p.y = Double.random(in: 0...h) }
            }
            particles[i] = p
        }
        if season != .snow { for c in pile.indices { pile[c] = max(0, pile[c] - dt * 4) } }
    }

    private func addToPile(_ c: Int, _ amount: Double) {
        let cap = 46.0
        pile[c] = min(cap, pile[c] + amount)
        // let it slump so the drift stays soft
        for _ in 0..<2 {
            for j in 1..<pile.count {
                let d = pile[j] - pile[j - 1]
                if abs(d) > 2.2 { pile[j] -= d * 0.25; pile[j - 1] += d * 0.25 }
            }
        }
    }

    private func spawn(w: Double, h: Double, season: PipSeason, anywhere: Bool) -> Particle {
        let depth = Double.random(in: 0.35...1)
        let size: Double
        switch season {
        case .snow: size = Double.random(in: 2...5.5) * depth
        case .stardust: size = Double.random(in: 1...3)
        default: size = Double.random(in: 7...13) * depth
        }
        return Particle(x: Double.random(in: 0...w), y: anywhere ? Double.random(in: 0...h) : -Double.random(in: 10...80),
                        vx: 0, vy: 30 * depth, size: size, depth: depth,
                        angle: Double.random(in: 0...(2 * .pi)), spin: Double.random(in: -2...2),
                        phase: Double.random(in: 0...(2 * .pi)), colour: Int.random(in: 0..<4))
    }

    // MARK: drawing

    func draw(_ ctx: inout GraphicsContext, size: CGSize, season: PipSeason, time: Double) {
        if season == .snow { drawPile(&ctx, size: size) }
        for p in particles {
            let alpha = 0.35 + 0.65 * p.depth
            switch season {
            case .snow:
                let r = p.size
                let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
                    Gradient(colors: [.white.opacity(alpha), .white.opacity(alpha * 0.55), .white.opacity(0)]),
                    center: CGPoint(x: p.x, y: p.y), startRadius: 0, endRadius: r))
            case .stardust:
                let tw = 0.4 + 0.6 * abs(sin(time * 1.7 + p.phase))
                let r = p.size * tw
                var star = Path()
                star.move(to: CGPoint(x: p.x, y: p.y - r * 2.4))
                star.addQuadCurve(to: CGPoint(x: p.x + r * 2.4, y: p.y), control: CGPoint(x: p.x, y: p.y))
                star.addQuadCurve(to: CGPoint(x: p.x, y: p.y + r * 2.4), control: CGPoint(x: p.x, y: p.y))
                star.addQuadCurve(to: CGPoint(x: p.x - r * 2.4, y: p.y), control: CGPoint(x: p.x, y: p.y))
                star.addQuadCurve(to: CGPoint(x: p.x, y: p.y - r * 2.4), control: CGPoint(x: p.x, y: p.y))
                ctx.fill(star, with: .color(Color(red: 1, green: 0.95, blue: 0.8).opacity(tw)))
            default:
                var c = ctx
                c.translateBy(x: p.x, y: p.y)
                c.rotate(by: .radians(p.angle))
                // a little 3D flutter: squash the shape as it turns
                c.scaleBy(x: 0.35 + 0.65 * abs(cos(time * 2 + p.phase)), y: 1)
                c.opacity = alpha
                c.fill(shape(season, p.size), with: .linearGradient(
                    Gradient(colors: colours(season, p.colour)),
                    startPoint: CGPoint(x: 0, y: -p.size), endPoint: CGPoint(x: 0, y: p.size)))
                if season == .autumn {
                    var vein = Path()
                    vein.move(to: CGPoint(x: 0, y: -p.size * 0.9)); vein.addLine(to: CGPoint(x: 0, y: p.size * 1.1))
                    c.stroke(vein, with: .color(.black.opacity(0.25)), lineWidth: 0.7)
                }
            }
        }
    }

    private func drawPile(_ ctx: inout GraphicsContext, size: CGSize) {
        guard pile.contains(where: { $0 > 0.5 }) else { return }
        let h = Double(size.height)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: h))
        for (i, v) in pile.enumerated() {
            path.addLine(to: CGPoint(x: Double(i) * column, y: h - v))
        }
        path.addLine(to: CGPoint(x: Double(size.width), y: h))
        path.closeSubpath()
        let top = h - (pile.max() ?? 0)
        ctx.fill(path, with: .linearGradient(
            Gradient(colors: [.white, Color(red: 0.80, green: 0.88, blue: 1.0)]),
            startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: h)))
    }

    private func shape(_ season: PipSeason, _ s: Double) -> Path {
        var p = Path()
        switch season {
        case .autumn:
            // maple-ish leaf: pointed oval with two side lobes
            p.move(to: CGPoint(x: 0, y: -s))
            p.addQuadCurve(to: CGPoint(x: s * 0.9, y: -s * 0.2), control: CGPoint(x: s * 0.4, y: -s * 0.9))
            p.addQuadCurve(to: CGPoint(x: s * 0.35, y: s * 0.2), control: CGPoint(x: s * 0.5, y: 0))
            p.addQuadCurve(to: CGPoint(x: 0, y: s), control: CGPoint(x: s * 0.4, y: s * 0.8))
            p.addQuadCurve(to: CGPoint(x: -s * 0.35, y: s * 0.2), control: CGPoint(x: -s * 0.4, y: s * 0.8))
            p.addQuadCurve(to: CGPoint(x: -s * 0.9, y: -s * 0.2), control: CGPoint(x: -s * 0.5, y: 0))
            p.addQuadCurve(to: CGPoint(x: 0, y: -s), control: CGPoint(x: -s * 0.4, y: -s * 0.9))
        case .spring:
            // dandelion seed: a stalk with a fluffy top
            p.addEllipse(in: CGRect(x: -s * 0.55, y: -s, width: s * 1.1, height: s * 0.7))
            p.addRect(CGRect(x: -0.4, y: -s * 0.4, width: 0.8, height: s * 1.3))
        default:
            // sakura / flower petal with a little notch at the tip
            p.move(to: CGPoint(x: 0, y: s))
            p.addCurve(to: CGPoint(x: -s * 0.12, y: -s), control1: CGPoint(x: -s * 0.9, y: s * 0.3), control2: CGPoint(x: -s * 0.7, y: -s))
            p.addLine(to: CGPoint(x: 0, y: -s * 0.75))
            p.addLine(to: CGPoint(x: s * 0.12, y: -s))
            p.addCurve(to: CGPoint(x: 0, y: s), control1: CGPoint(x: s * 0.7, y: -s), control2: CGPoint(x: s * 0.9, y: s * 0.3))
        }
        return p
    }

    private func colours(_ season: PipSeason, _ i: Int) -> [Color] {
        switch season {
        case .autumn:
            let set: [(Double, Double, Double)] = [(0.93, 0.42, 0.13), (0.85, 0.22, 0.12), (0.96, 0.66, 0.18), (0.70, 0.30, 0.10)]
            let c = set[i % set.count]
            return [Color(red: c.0, green: c.1, blue: c.2), Color(red: c.0 * 0.75, green: c.1 * 0.7, blue: c.2 * 0.7)]
        case .sakura:
            return [Color(red: 1.0, green: 0.86, blue: 0.91), Color(red: 0.98, green: 0.62, blue: 0.75)]
        case .flowers:
            let set: [(Double, Double, Double)] = [(1.0, 0.82, 0.40), (1.0, 0.56, 0.64), (0.72, 0.61, 1.0), (0.50, 0.82, 1.0)]
            let c = set[i % set.count]
            return [Color(red: c.0, green: c.1, blue: c.2), Color(red: c.0 * 0.85, green: c.1 * 0.8, blue: c.2 * 0.85)]
        default:
            return [.white, Color(white: 0.85)]
        }
    }
}
