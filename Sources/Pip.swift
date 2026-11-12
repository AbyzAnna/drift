// Pip.swift — the little creature that lives on your windows.
// Pure Foundation: behaviour only. Drawing is in Art.swift.
// Coordinates are global Quartz points (y grows downward). Pip's (x, y) is the point between its feet.

import Foundation

struct PipInput {
    var cursorX = 0.0, cursorY = 0.0
    var cursorSpeed = 0.0       // pt/s
    var userIdle = 0.0          // seconds since the last mouse or key event
    var frontId: Int? = nil     // window the user is working in
}

final class Pip {
    enum State { case fall, idle, walk, jump, sleep, wake, pet, dizzy, build, catching }
    enum Face { case normal, happy, sleep, surprised, dizzy, eat }
    enum FX { case heart, z, bang, sparkle }

    struct Effect {
        var kind: FX
        var x: Double, y: Double        // offset from Pip's feet (y down)
        var vx: Double, vy: Double
        var life: Double, maxLife: Double
        var spin: Double
    }

    // What the renderer reads
    private(set) var x = 0.0, y = 0.0
    private(set) var state: State = .fall
    private(set) var face: Face = .normal
    private(set) var facing = 1.0
    private(set) var walkPhase = 0.0
    private(set) var squash = 0.0           // > 0 squashed, < 0 stretched
    private(set) var blink = 0.0            // 0 open … 1 closed
    private(set) var lookX = 0.0, lookY = 0.0
    private(set) var effects: [Effect] = []
    private(set) var bubble: String? = nil
    private(set) var bubbleAlpha = 0.0
    private(set) var hop = 0.0              // in-place hop height, pt
    private(set) var time = 0.0
    var enabled = true

    // Internal
    private var vx = 0.0, vy = 0.0
    private var surfaceId: Int? = nil
    private var localX = 0.0
    private var stateT = 0.0, stateDur = 1.5
    private var targetX = 0.0
    private var jFromX = 0.0, jFromY = 0.0, jTo: Int? = nil, jLocal = 0.0, jDur = 0.6, jArc = 60.0
    private var blinkT = 2.5
    private var faceT = 0.0
    private var stepDist = 0.0
    private var petT = 0.0
    private var bubbleT = 0.0
    private var fxT = 0.0
    private var lastFront: Int? = nil
    private var visitT = -1.0
    private var hopV = 0.0
    private var buildBase: Ball? = nil
    private var buildHead: Ball? = nil
    private var placed = false
    private var lastMeteors = 0
    private var chatterT = 20.0

    var isOnWindow: Bool { surfaceId != nil && state != .fall && state != .jump }

    // MARK: - Public actions

    func reset(_ e: Engine) {
        guard let sc = e.screens.first else { return }
        x = Double(sc.frame.midX) + Double.random(in: -200...200)
        y = Double(sc.frame.minY) + 30
        vx = 0; vy = 0
        surfaceId = nil
        state = .fall
        placed = true
        say("hi! I'm Pip", 3)
    }

    /// "Call Pip": come to the window the user is working in.
    func call(_ e: Engine, to id: Int?) {
        guard enabled else { return }
        if let s = e.surface(id), let local = visibleLocal(s, near: s.x + s.w / 2) {
            let tx = s.x + local, ty = standY(s, local)
            if hypot(tx - x, ty - y) < 1100 && state != .fall {
                startJump(to: s, local: local)
            } else {
                // Too far to jump: drop in from above.
                x = tx; y = max(ty - 400, Double((screenAt(tx, ty, e)?.frame.minY ?? 0)) - 20)
                vx = 0; vy = 0; surfaceId = nil; state = .fall
            }
            say(["coming!", "I'm here!", "hi!"].randomElement()!, 2)
        } else {
            reset(e)
        }
    }

    /// The mouse was shaken (snow globe).
    func snowGlobe(_ e: Engine, x gx: Double, y gy: Double) {
        guard enabled else { return }
        let d = hypot(gx - x, gy - (y - 26))
        if d < 320 && state != .fall {
            startFall(vx: (x - gx) * 2 + Double.random(in: -200...200), vy: -520)
            say("wheee!", 1.8)
            faceSet(.dizzy, 2.5)
        } else if state != .fall && state != .jump {
            state = .dizzy; stateT = 0; stateDur = 2.6
            faceSet(.dizzy, 2.6)
            say(["whoa…", "so dizzy", "@_@"].randomElement()!, 2)
        }
    }

    // MARK: - Frame update

    func update(_ dt: Double, _ e: Engine, _ inp: PipInput) {
        guard enabled else { return }
        if !placed { reset(e) }
        time += dt
        stateT += dt

        tickBlink(dt)
        tickEffects(dt)
        tickBubble(dt)
        if faceT > 0 { faceT -= dt; if faceT <= 0 { face = baseFace() } }
        squash += (0 - squash) * min(1, dt * 9)
        if hop > 0 || hopV > 0 {
            hop += hopV * dt; hopV -= 1000 * dt
            if hop <= 0 { hop = 0; hopV = 0; squash = max(squash, 0.18) }
        }

        // The window the user switched to: go and say hi after a moment.
        if inp.frontId != lastFront {
            lastFront = inp.frontId
            if inp.frontId != nil && inp.frontId != surfaceId { visitT = Double.random(in: 0.8...2.8) }
        }
        // Shooting star seen.
        let meteors = e.screens.reduce(0) { $0 + $1.meteors.count }
        if meteors > lastMeteors && state != .sleep && Double.random(in: 0..<1) < 0.3 {
            say(["a shooting star!", "make a wish!", "ooh!"].randomElement()!, 2.2)
            lookY = -1
        }
        lastMeteors = meteors

        switch state {
        case .fall: stepFall(dt, e)
        case .jump: stepJump(dt, e)
        default:
            if !ground(e) { break }   // may have started falling or jumping
            react(dt, e, inp)
            think(dt, e, inp)
        }
    }

    // MARK: - States

    private func ground(_ e: Engine) -> Bool {
        if let id = surfaceId {
            guard let s = e.surface(id) else {
                startFall(vx: 0, vy: 0)
                say(["whoa!", "eep!", "hey!"].randomElement()!, 1.6)
                return false
            }
            if hypot(s.vx, s.vy) > 1100 {
                startFall(vx: s.vx * 0.35, vy: min(0, s.vy * 0.3) - 260)
                say(["wheee!", "whoa!"].randomElement()!, 1.6)
                return false
            }
            localX = min(max(8, localX), max(8, s.w - 8))
            if !s.visible[s.col(s.x + localX)] {
                // A window was moved over us: hop somewhere visible.
                if let t = visibleLocal(s, near: s.x + localX), abs(t - localX) < 160 {
                    startJump(to: s, local: t)
                } else if let (ts, tl) = pickJumpTarget(e, prefer: nil) {
                    startJump(to: ts, local: tl)
                } else {
                    startFall(vx: 0, vy: 0)
                }
                return false
            }
            x = s.x + localX
            y = standY(s, localX)
        } else {
            let f = screenAt(x, y, e)?.frame ?? e.screens.first?.frame ?? .zero
            x = min(max(Double(f.minX) + 12, x), Double(f.maxX) - 12)
            y = Double(f.maxY)
        }
        return true
    }

    private func think(_ dt: Double, _ e: Engine, _ inp: PipInput) {
        // visiting the front window
        if visitT > 0 {
            visitT -= dt
            if visitT <= 0, state == .idle || state == .walk, let s = e.surface(inp.frontId), s.id != surfaceId,
               let local = visibleLocal(s, near: x) {
                if hypot(s.x + local - x, standY(s, local) - y) < 1000 {
                    startJump(to: s, local: local)
                    if Double.random(in: 0..<1) < 0.4 { say(["whatcha doing?", "ooh, this one", "hi!"].randomElement()!, 2) }
                    return
                }
            }
        }

        switch state {
        case .walk:
            let dir: Double = targetX > localX ? 1 : -1
            let speed = 46.0
            let step = min(abs(targetX - localX), speed * dt)
            localX += dir * step
            facing = dir
            walkPhase += dt * 11
            stepDist += step
            if stepDist > 9, let s = e.surface(surfaceId) {
                stepDist = 0
                e.press(s, at: s.x + localX)
            }
            if abs(targetX - localX) < 0.5 || stateT > 7 { toIdle(Double.random(in: 1...3)) }

        case .sleep:
            fxT -= dt
            if fxT <= 0 { fxT = 1.3; emit(.z, 1) }
            if inp.userIdle < 1.5 {
                state = .wake; stateT = 0; stateDur = 1.8
                faceSet(.happy, 1.8)
                hopV = 170
                say(["hi again!", "you're back!", "*yawn*"].randomElement()!, 2.2)
            }

        case .wake:
            walkPhase += dt * 14
            if stateT > stateDur { toIdle(1) }

        case .pet:
            fxT -= dt
            if fxT <= 0 { fxT = 0.45; emit(.heart, 1) }
            squash = 0.05 * sin(time * 9)

        case .dizzy:
            if stateT > stateDur { toIdle(1) }

        case .catching:
            lookY = -1
            if hop == 0 && Double.random(in: 0..<1) < dt * 1.6 { hopV = 150; squash = -0.15 }
            if hop > 4 && e.catchParticle(x: x, y: y - 40 - hop, radius: 16) {
                faceSet(.eat, 0.6)
                emit(.sparkle, 2)
                if Double.random(in: 0..<1) < 0.25 { say(["nom", "mmm", "got one!"].randomElement()!, 1.3) }
            }
            if stateT > stateDur { toIdle(Double.random(in: 1...3)) }

        case .build:
            stepBuild(dt, e)

        case .idle:
            if stateT > stateDur { decide(e, inp) }

        case .fall, .jump:
            break
        }

        chatterT -= dt
        if chatterT <= 0 {
            chatterT = Double.random(in: 25...60)
            if state == .idle || state == .walk { say(chatter(e.season.kind).randomElement()!, 2.4) }
        }
    }

    private func decide(_ e: Engine, _ inp: PipInput) {
        if inp.userIdle > 75 {
            state = .sleep; stateT = 0; fxT = 0.5
            face = .sleep
            return
        }
        let onBottom = surfaceId == nil || e.surface(surfaceId)?.kind == .ground
        if onBottom && Double.random(in: 0..<1) < 0.55, let (ts, tl) = pickJumpTarget(e, prefer: inp.frontId), ts.kind != .ground {
            startJump(to: ts, local: tl)
            return
        }
        let r = Double.random(in: 0..<1)
        let snowy = e.season.kind == .snow
        if r < 0.36, let s = e.surface(surfaceId) {
            targetX = min(max(10, localX + Double.random(in: -220...220)), max(10, s.w - 10))
            state = .walk; stateT = 0
        } else if r < 0.36 {
            // on the floor: wander a little
            state = .idle; stateT = 0; stateDur = Double.random(in: 1...2)
            if let (ts, tl) = pickJumpTarget(e, prefer: inp.frontId) { startJump(to: ts, local: tl) }
        } else if r < 0.52 {
            toIdle(Double.random(in: 2...4))
            lookX = Double.random(in: -1...1); lookY = Double.random(in: -1...0.3)
        } else if r < 0.70 {
            if let (ts, tl) = pickJumpTarget(e, prefer: inp.frontId) { startJump(to: ts, local: tl) } else { toIdle(2) }
        } else if r < 0.82 && !e.paused && e.season.kind != .rain {
            state = .catching; stateT = 0; stateDur = Double.random(in: 3...5)
        } else if r < 0.92 && snowy, let s = e.surface(surfaceId), canBuild(s) {
            startBuild(s)
        } else {
            toIdle(Double.random(in: 3...6))
        }
    }

    private func react(_ dt: Double, _ e: Engine, _ inp: PipInput) {
        let hx = x, hy = y - 26 - hop
        let dx = inp.cursorX - hx, dy = inp.cursorY - hy
        let d = (dx * dx + dy * dy).squareRoot()
        if state != .sleep {
            if d < 600 {
                lookX += (max(-1, min(1, dx / 160)) - lookX) * min(1, dt * 8)
                lookY += (max(-1, min(1, dy / 160)) - lookY) * min(1, dt * 8)
                if state == .idle && abs(dx) > 20 { facing = dx > 0 ? 1 : -1 }
            } else if state != .catching {
                lookX *= 1 - min(1, dt * 2); lookY *= 1 - min(1, dt * 2)
            }
        }
        let canReact = state == .idle || state == .walk || state == .catching || state == .pet || state == .sleep
        if d < 36 && inp.cursorSpeed > 450 && canReact {
            // swept past: startled hop away
            emit(.bang, 1)
            faceSet(.surprised, 0.9)
            if state == .sleep { say("huh?!", 1.4) } else if Double.random(in: 0..<1) < 0.5 { say(["eek!", "hey!", "careful!"].randomElement()!, 1.4) }
            if let s = e.surface(surfaceId) {
                let away = min(max(10, localX + (dx > 0 ? -70 : 70)), max(10, s.w - 10))
                startJump(to: s, local: away)
            } else {
                hopV = 260
                toIdle(1)
            }
            petT = 0
            return
        }
        if d < 44 && inp.cursorSpeed < 90 && canReact {
            petT += dt
            if petT > 0.7 && state != .pet && state != .sleep {
                state = .pet; stateT = 0; fxT = 0
                face = .happy
                say(["hehe", "purr…", "♥", "that tickles"].randomElement()!, 1.8)
            } else if petT > 0.7 && state == .sleep {
                fxT -= dt
                if fxT <= 0 { fxT = 0.8; emit(.heart, 1) }
            }
        } else {
            petT = 0
            if state == .pet && d > 70 { toIdle(1.2); faceSet(.happy, 1) }
        }
    }

    // MARK: falling & jumping

    private func startFall(vx: Double, vy: Double) {
        self.vx = vx; self.vy = vy
        surfaceId = nil
        state = .fall; stateT = 0
        buildBase = nil; buildHead = nil
    }

    private func stepFall(_ dt: Double, _ e: Engine) {
        vy += 1100 * dt
        vx *= 1 - min(1, 0.6 * dt)
        let py = y
        x += vx * dt
        y += vy * dt
        squash = max(-0.25, -vy / 3000)
        if vy > 0 {
            for s in e.surfaces where !s.h.isEmpty && x >= s.x + 4 && x <= s.x + s.w - 4 {
                let c = s.col(x)
                if !s.visible[c] { continue }
                let top = standY(s, x - s.x)
                if py <= top && y >= top {
                    surfaceId = s.id
                    localX = x - s.x
                    y = top
                    land(e)
                    return
                }
            }
        }
        let f = screenAt(x, py, e)?.frame ?? e.screens.first?.frame ?? .zero
        if y >= Double(f.maxY) {
            y = Double(f.maxY)
            surfaceId = nil
            land(e)
        } else if x < Double(f.minX) + 10 || x > Double(f.maxX) - 10 {
            // bounce off the screen edge
            if screenAt(x, y, e) == nil { vx = -vx * 0.5; x = min(max(Double(f.minX) + 10, x), Double(f.maxX) - 10) }
        }
    }

    private func land(_ e: Engine) {
        let impact = vy
        squash = min(0.5, 0.12 + impact / 2200)
        vx = 0; vy = 0
        if impact > 950 { say(["oof!", "ow…", "made it!"].randomElement()!, 1.5) }
        if e.season.kind == .snow, let s = e.surface(surfaceId), s.h[s.col(x)] > 3 {
            e.fling(x: x, y: y, vx: 0, count: 4, life: 0.3...0.6)
        }
        if face != .dizzy { faceSet(.normal, 0) }
        toIdle(Double.random(in: 0.5...1.5))
    }

    private func startJump(to s: Surface, local: Double) {
        jFromX = x; jFromY = y - hop
        jTo = s.id
        jLocal = min(max(8, local), max(8, s.w - 8))
        let tx = s.x + jLocal, ty = standY(s, jLocal)
        let dist = hypot(tx - x, ty - y)
        jDur = min(1.3, 0.32 + dist / 1100)
        jArc = 26 + max(0, y - ty) * 0.6 + dist * 0.12
        facing = tx >= x ? 1 : -1
        state = .jump; stateT = 0
        squash = 0.3
        hop = 0; hopV = 0
        buildBase = nil; buildHead = nil
    }

    private func stepJump(_ dt: Double, _ e: Engine) {
        guard let s = e.surface(jTo) else {
            startFall(vx: facing * 120, vy: 0)
            return
        }
        let u = min(1, stateT / jDur)
        let local = min(max(8, jLocal), max(8, s.w - 8))
        let tx = s.x + local, ty = standY(s, local)
        x = jFromX + (tx - jFromX) * u
        y = jFromY + (ty - jFromY) * u - jArc * 4 * u * (1 - u)
        squash = -0.2 * sin(Double.pi * u)
        if u >= 1 {
            surfaceId = s.id
            localX = local
            vy = 400
            land(e)
        }
    }

    // MARK: building a snowman

    private func canBuild(_ s: Surface) -> Bool {
        guard s.kind == .window, s.balls.filter({ $0.byPip }).count < 2 else { return false }
        let c = s.col(s.x + localX)
        let lo = max(0, c - 12), hi = min(s.h.count - 1, c + 12)
        if lo > hi { return false }
        let avg = s.h[lo...hi].reduce(0, +) / Double(hi - lo + 1)
        return avg > 6
    }

    private func startBuild(_ s: Surface) {
        let bx = min(max(14, localX + facing * 22), max(14, s.w - 14))
        let b = Ball(x: bx, r: 3, seed: Double.random(in: 0...6.28))
        b.byPip = true
        s.balls.append(b)
        s.version += 1
        buildBase = b; buildHead = nil
        state = .build; stateT = 0; stateDur = 4.6
        face = .happy
        facing = bx > localX ? 1 : -1
    }

    private func stepBuild(_ dt: Double, _ e: Engine) {
        guard let s = e.surface(surfaceId), let base = buildBase, s.balls.contains(where: { $0 === base }) else {
            buildBase = nil; buildHead = nil
            toIdle(1); return
        }
        walkPhase += dt * 16      // patting animation
        if stateT < 2.4 {
            if base.r < 12 { e.consume(s, base, reach: 2.4) }
            base.r = min(12, max(base.r, 3 + stateT * 3.2))
        } else {
            if buildHead == nil {
                let h = Ball(x: base.x, r: 2, seed: Double.random(in: 0...6.28))
                h.byPip = true
                h.on = base
                s.balls.append(h)
                buildHead = h
            }
            if let h = buildHead {
                if h.r < 8 { e.consume(s, h, reach: 2.6) }
                h.r = min(8, max(h.r, 2 + (stateT - 2.4) * 3.4))
            }
        }
        s.version += 1
        if stateT > stateDur {
            buildBase = nil; buildHead = nil
            emit(.sparkle, 4)
            say(["ta-da!", "meet my friend", "a snowman!"].randomElement()!, 2.4)
            toIdle(Double.random(in: 2...3))
        }
    }

    // MARK: helpers

    private func toIdle(_ dur: Double) {
        state = .idle; stateT = 0; stateDur = dur
        if face == .sleep || face == .eat { face = .normal }
    }

    private func baseFace() -> Face {
        switch state {
        case .sleep: return .sleep
        case .pet, .build, .wake: return .happy
        case .dizzy: return .dizzy
        default: return .normal
        }
    }

    private func faceSet(_ f: Face, _ dur: Double) {
        face = f; faceT = dur
    }

    private func standY(_ s: Surface, _ local: Double) -> Double {
        guard !s.h.isEmpty else { return s.y }
        return s.y - s.h[s.col(s.x + local)] * 0.8
    }

    private func visibleLocal(_ s: Surface, near gx: Double) -> Double? {
        guard !s.h.isEmpty else { return nil }
        let c0 = s.col(min(max(gx, s.x + 10), s.x + s.w - 10))
        let edge = max(1, Int(10 / s.cw))
        for off in 0..<s.h.count {
            for c in [c0 - off, c0 + off] where c >= edge && c < s.h.count - edge && s.visible[c] {
                return (Double(c) + 0.5) * s.cw
            }
        }
        return nil
    }

    private func screenAt(_ gx: Double, _ gy: Double, _ e: Engine) -> ScreenSim? {
        let p = CGPoint(x: gx, y: gy)
        return e.screens.first { $0.frame.contains(p) }
            ?? e.screens.first { gx >= Double($0.frame.minX) && gx < Double($0.frame.maxX) }
    }

    private func pickJumpTarget(_ e: Engine, prefer: Int?) -> (Surface, Double)? {
        var cands: [(Surface, Double, Double)] = []
        for s in e.surfaces where s.id != surfaceId && !s.h.isEmpty {
            let gx = min(max(x + Double.random(in: -90...90), s.x + 12), s.x + s.w - 12)
            guard let local = visibleLocal(s, near: gx) else { continue }
            let tx = s.x + local, ty = standY(s, local)
            let dx = tx - x, dy = ty - y
            if abs(dx) > 900 || dy < -800 || dy > 900 { continue }
            guard let sc = screenAt(tx, ty - 10, e), Double(sc.frame.minY) + 40 < ty else { continue }
            let ax: Double = abs(dx) / 300
            let ay: Double = abs(dy) / 400
            var score: Double = 1 / (1 + ax + ay)
            if s.id == prefer { score *= 6 }
            if s.kind == .ground { score *= 0.35 }
            if s.kind == .dock { score *= 0.7 }
            cands.append((s, local, score))
        }
        let total = cands.reduce(0) { $0 + $1.2 }
        guard total > 0 else { return nil }
        var r = Double.random(in: 0..<total)
        for c in cands {
            r -= c.2
            if r <= 0 { return (c.0, c.1) }
        }
        return cands.last.map { ($0.0, $0.1) }
    }

    private func tickBlink(_ dt: Double) {
        blinkT -= dt
        if blinkT <= 0 {
            blink = min(1, blink + dt * 14)
            if blinkT < -0.14 { blinkT = Double.random(in: 2...5.5); blink = 0 }
        }
    }

    private func tickEffects(_ dt: Double) {
        guard !effects.isEmpty else { return }
        for i in effects.indices {
            effects[i].x += effects[i].vx * dt
            effects[i].y += effects[i].vy * dt
            effects[i].life -= dt
        }
        effects.removeAll { $0.life <= 0 }
    }

    private func tickBubble(_ dt: Double) {
        if bubble != nil {
            bubbleT -= dt
            if bubbleT > 0 { bubbleAlpha = min(1, bubbleAlpha + dt * 6) }
            else { bubbleAlpha -= dt * 4; if bubbleAlpha <= 0 { bubble = nil; bubbleAlpha = 0 } }
        }
    }

    private func emit(_ kind: FX, _ n: Int) {
        for _ in 0..<n where effects.count < 24 {
            let life: Double
            var vy: Double, vx: Double
            switch kind {
            case .heart: life = 1.4; vy = -38; vx = Double.random(in: -10...10)
            case .z: life = 2.2; vy = -20; vx = 10 * facing
            case .bang: life = 0.9; vy = -10; vx = 0
            case .sparkle: life = 0.8; vy = Double.random(in: -60...(-20)); vx = Double.random(in: -50...50)
            }
            effects.append(Effect(kind: kind, x: Double.random(in: -6...6) + (kind == .z ? 10 * facing : 0),
                                  y: kind == .bang ? -44 : -34, vx: vx, vy: vy, life: life, maxLife: life,
                                  spin: Double.random(in: -1...1)))
        }
    }

    func say(_ text: String, _ dur: Double = 2) {
        bubble = text
        bubbleT = dur
        if bubbleAlpha <= 0 { bubbleAlpha = 0.01 }
    }

    private func chatter(_ k: Kind) -> [String] {
        switch k {
        case .snow: return ["brr…", "snow!", "so fluffy", "let it snow", "my nose is cold"]
        case .petal: return ["so pretty", "petals!", "hanami time"]
        case .spring: return ["achoo!", "fluffy seeds", "spring!"]
        case .flower: return ["smells nice", "la la la", "flowers!"]
        case .leaf: return ["crunchy!", "leaf pile!", "cozy season"]
        case .rain: return ["drip drop", "cozy…", "glad I have this umbrella"]
        case .star: return ["make a wish", "ooh, sparkly", "stardust!"]
        }
    }
}
