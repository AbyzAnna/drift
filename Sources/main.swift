// main.swift — Drift's macOS side: transparent click-through overlays on every display,
// the menu bar item, window tracking, cursor input and the frame loop.

import Cocoa
import ServiceManagement
import ApplicationServices
import Carbon.HIToolbox

let noActions: [String: CAAction] = [
    "contents": NSNull(), "position": NSNull(), "bounds": NSNull(), "frame": NSNull(),
    "hidden": NSNull(), "transform": NSNull(), "opacity": NSNull(), "sublayers": NSNull(), "zPosition": NSNull(),
]

// MARK: - Layer pool

final class LayerPool {
    private(set) var layers: [CALayer] = []
    private var sprite: [Int] = []
    private var shown = 0
    unowned let parent: CALayer
    let scale: CGFloat
    let z: CGFloat

    init(parent: CALayer, scale: CGFloat, z: CGFloat) { self.parent = parent; self.scale = scale; self.z = z }

    func resize(_ n: Int) {
        while layers.count < n {
            let l = CALayer()
            l.actions = noActions
            l.contentsScale = scale
            l.zPosition = z
            parent.addSublayer(l)
            layers.append(l)
            sprite.append(-1)
        }
        if n != shown {
            for i in 0..<layers.count { layers[i].isHidden = i >= n }
            shown = n
        }
    }

    func setSprite(_ i: Int, _ s: Int, _ image: CGImage?) {
        if sprite[i] != s { layers[i].contents = image; sprite[i] = s }
    }

    func reset() {
        for i in layers.indices {
            sprite[i] = -1
            layers[i].transform = CATransform3DIdentity
            layers[i].opacity = 1
        }
    }
}

// MARK: - One transparent overlay per display

final class Overlay {
    let window: NSWindow
    let root: CALayer
    let sim: ScreenSim
    let qFrame: CGRect
    let scale: CGFloat
    let far: LayerPool
    let near: LayerPool
    let flings: LayerPool
    let glints: LayerPool
    let trails: LayerPool
    let drops: LayerPool
    let meteors: LayerPool
    let pipLayer = PipLayer()
    var frost: [CALayer] = []
    var piles: [Int: PileLayer] = [:]

    init(screen: NSScreen, qFrame: CGRect, sim: ScreenSim) {
        self.qFrame = qFrame
        self.sim = sim
        scale = screen.backingScaleFactor
        let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.setFrame(screen.frame, display: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        w.isReleasedWhenClosed = false
        let v = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        v.wantsLayer = true
        w.contentView = v
        let layer = v.layer ?? CALayer()
        layer.actions = noActions
        root = layer
        meteors = LayerPool(parent: layer, scale: scale, z: -3)
        far = LayerPool(parent: layer, scale: scale, z: -2)
        glints = LayerPool(parent: layer, scale: scale, z: 1)
        near = LayerPool(parent: layer, scale: scale, z: 2)
        flings = LayerPool(parent: layer, scale: scale, z: 2)
        trails = LayerPool(parent: layer, scale: scale, z: 4)
        drops = LayerPool(parent: layer, scale: scale, z: 4)
        window = w

        pipLayer.contentsScale = scale
        pipLayer.zPosition = 3
        pipLayer.bounds = CGRect(origin: .zero, size: PipLayer.size)
        pipLayer.anchorPoint = CGPoint(x: PipLayer.feet.x / PipLayer.size.width, y: PipLayer.feet.y / PipLayer.size.height)
        pipLayer.isHidden = true
        layer.addSublayer(pipLayer)

        // frost in the four corners (hidden until you step away)
        let fs: CGFloat = min(420, min(qFrame.width, qFrame.height) * 0.42)
        let img = Sprites.frostCorner(size: fs, scale: scale, seed: 7)
        let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (fs / 2, fs / 2, 1, 1),                                        // bottom-left
            (qFrame.width - fs / 2, fs / 2, -1, 1),                        // bottom-right
            (fs / 2, qFrame.height - fs / 2, 1, -1),                       // top-left
            (qFrame.width - fs / 2, qFrame.height - fs / 2, -1, -1),       // top-right
        ]
        for (x, y, sx, sy) in corners {
            let l = CALayer()
            l.actions = noActions
            l.contents = img
            l.contentsScale = scale
            l.bounds = CGRect(x: 0, y: 0, width: fs, height: fs)
            l.position = CGPoint(x: x, y: y)
            l.transform = CATransform3DMakeScale(sx, sy, 1)
            l.zPosition = 5
            l.opacity = 0
            l.isHidden = true
            layer.addSublayer(l)
            frost.append(l)
        }
        w.orderFrontRegardless()
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }

    /// Global Quartz point → this overlay's layer coordinates (y up).
    func local(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: CGFloat(x) - qFrame.minX, y: qFrame.height - (CGFloat(y) - qFrame.minY))
    }

    func seasonChanged() {
        for p in [far, near, flings, glints, trails, drops, meteors] { p.reset() }
        for (_, p) in piles { p.removeFromSuperlayer() }
        piles.removeAll()
    }

    func render(_ e: Engine, _ art: Sprites.Set, pip: Pip, critter: CritterArt?, sprite: SpriteCritter?, frostLevel: Double) {
        let S = e.season
        let sprites = art.all
        guard !sprites.isEmpty else { return }
        let wx = e.windPx
        let turns = S.spin > 0 || S.flip

        // falling particles, split into the soft background layer and the sharp foreground layer
        var nNear = 0, nFar = 0
        if !e.paused {
            for p in sim.particles { if p.far { nFar += 1 } else { nNear += 1 } }
        }
        near.resize(nNear)
        far.resize(nFar)
        var iN = 0, iF = 0
        if !e.paused {
            for p in sim.particles {
                let pool = p.far ? far : near
                let i: Int
                if p.far { i = iF; iF += 1 } else { i = iN; iN += 1 }
                let l = pool.layers[i]
                l.position = local(p.x, p.y)
                if p.streak {
                    pool.setSprite(i, -10, art.streak)
                    let len = CGFloat(p.vy * (p.far ? 0.016 : 0.024))
                    l.bounds = CGRect(x: 0, y: 0, width: p.far ? 0.9 : 1.4, height: len)
                    l.transform = CATransform3DMakeRotation(CGFloat(atan2(p.vx, p.vy)), 0, 0, 1)
                    l.opacity = Float(p.alpha * 0.6)
                } else {
                    pool.setSprite(i, p.sprite, sprites[p.sprite % sprites.count])
                    let d = CGFloat(p.s * S.dm)
                    l.bounds = CGRect(x: 0, y: 0, width: d, height: d)
                    if turns && !p.far {
                        var fx = S.flip ? cos(p.fl) : 1
                        if S.flip { fx = fx < 0 ? min(fx, -0.2) : max(fx, 0.2) }
                        l.transform = CATransform3DScale(CATransform3DMakeRotation(CGFloat(p.rot), 0, 0, 1), CGFloat(fx), 1, 1)
                    } else if S.kind == .snow && !p.far {
                        l.transform = CATransform3DMakeRotation(CGFloat(p.rot + e.t * 0.4), 0, 0, 1)
                    }
                    var a = p.alpha
                    if S.twinkle { a *= 0.35 + 0.65 * abs(sin(e.t * 2.2 + p.tw)) }
                    l.opacity = Float(a)
                }
            }
        }

        // pieces flying off, and icicle drips
        let fn = sim.flings.count
        flings.resize(fn)
        for i in 0..<fn {
            let f = sim.flings[i]
            let l = flings.layers[i]
            l.position = local(f.x, f.y)
            if f.streak {
                flings.setSprite(i, -10, art.streak)
                l.bounds = CGRect(x: 0, y: 0, width: 1.6, height: 7)
                l.transform = CATransform3DIdentity
                l.opacity = Float(min(1, f.life * 2))
            } else {
                flings.setSprite(i, f.sprite, sprites[f.sprite % sprites.count])
                let d = CGFloat(f.d)
                l.bounds = CGRect(x: 0, y: 0, width: d, height: d)
                l.transform = CATransform3DMakeRotation(CGFloat(f.rot), 0, 0, 1)
                l.opacity = Float(min(1, f.life * 2.5))
            }
        }

        // drifts
        var seen = Set<Int>()
        let below = PileLayer.below
        for s in e.surfaces {
            let reach = CGRect(x: s.x, y: s.y - 300, width: s.w, height: 300 + Double(below))
            guard reach.intersects(qFrame) else { continue }
            let pl: PileLayer
            if let existing = piles[s.id] {
                pl = existing
            } else {
                guard s.hasContent else { continue }
                pl = PileLayer()
                pl.contentsScale = scale
                pl.surface = s
                pl.engine = e
                pl.season = S
                pl.sprites = art.near
                pl.zPosition = 0
                root.addSublayer(pl)
                piles[s.id] = pl
            }
            seen.insert(s.id)
            if pl.drawnVersion != s.version {
                pl.drawnVersion = s.version
                if !s.hasContent {
                    pl.removeFromSuperlayer()
                    piles[s.id] = nil
                    seen.remove(s.id)
                    continue
                }
                pl.room = CGFloat(ceil((e.contentHeight(s) + 10) / 16) * 16)
                pl.setNeedsDisplay()
            }
            let edge = local(s.x, s.y)
            let f = CGRect(x: edge.x, y: edge.y - below, width: CGFloat(s.w), height: pl.room + below)
            if pl.frame != f { pl.frame = f }
        }
        for (id, pl) in piles where !seen.contains(id) {
            pl.removeFromSuperlayer()
            piles[id] = nil
        }

        // glints: tiny sparkles that wink on the surface of snow
        var gl: [(CGPoint, Float)] = []
        if S.kind == .snow || S.kind == .star {
            for s in e.surfaces where piles[s.id] != nil && s.h.count > 10 {
                let n = s.h.count
                for k in 0..<min(14, n / 18) {
                    let c = Int(hash01(s.id, k) * Double(n))
                    guard c < n, s.visible[c], s.h[c] > 3 else { continue }
                    let ph = hash01(k, s.id) * 6.28, rate = 0.5 + hash01(k &+ 3, s.id) * 0.9
                    let v = sin(e.t * rate * 2 + ph)
                    guard v > 0.75 else { continue }
                    let o = pow((v - 0.75) / 0.25, 2)
                    gl.append((local(s.x + (Double(c) + 0.5) * s.cw, s.y - s.h[c] * (0.55 + 0.4 * hash01(c, k))), Float(o)))
                }
            }
        }
        glints.resize(gl.count)
        for (i, g) in gl.enumerated() {
            let l = glints.layers[i]
            glints.setSprite(i, 0, art.glint)
            l.position = g.0
            l.bounds = CGRect(x: 0, y: 0, width: 9, height: 9)
            l.opacity = g.1
        }

        // raindrops on the glass
        let dn = sim.drops.count
        drops.resize(dn)
        trails.resize(sim.drops.filter { $0.trail > 2 }.count)
        var ti = 0
        for i in 0..<dn {
            let d = sim.drops[i]
            let l = drops.layers[i]
            drops.setSprite(i, 0, art.drop)
            let r = CGFloat(d.r)
            l.position = local(d.x, d.y)
            let stretch: CGFloat = d.wait > 0 ? 1 : 1.25
            l.bounds = CGRect(x: 0, y: 0, width: r * 2.8, height: r * 2.8 * stretch)
            l.opacity = 0.9
            if d.trail > 2 {
                let t = trails.layers[ti]
                trails.setSprite(ti, 0, art.streak)
                t.position = local(d.x, d.y - d.trail / 2)
                t.bounds = CGRect(x: 0, y: 0, width: r * 0.9, height: CGFloat(d.trail))
                t.opacity = 0.28
                ti += 1
            }
        }

        // shooting stars
        let mn = sim.meteors.count
        meteors.resize(mn)
        for i in 0..<mn {
            let m = sim.meteors[i]
            let l = meteors.layers[i]
            meteors.setSprite(i, 0, art.meteor)
            let len: CGFloat = 150
            let ang = atan2(m.vx, m.vy)
            l.position = local(m.x - sin(ang) * Double(len) / 2, m.y - cos(ang) * Double(len) / 2)
            l.bounds = CGRect(x: 0, y: 0, width: 2.2, height: len)
            l.transform = CATransform3DMakeRotation(CGFloat(ang), 0, 0, 1)
            let u = m.life / m.maxLife
            l.opacity = Float(min(1, u * 3) * min(1, (1 - u) * 6))
        }

        // Pip
        let showPip = pip.enabled && qFrame.contains(CGPoint(x: pip.x, y: min(pip.y - 1, Double(qFrame.maxY) - 1)))
        pipLayer.isHidden = !showPip
        if showPip {
            pipLayer.pip = pip
            pipLayer.art = critter
            pipLayer.sprite = sprite
            pipLayer.kind = S.kind
            pipLayer.wind = e.windNow
            pipLayer.position = local(pip.x, pip.y)
            pipLayer.setNeedsDisplay()
        }

        // frost
        let fo = Float(frostLevel)
        for l in frost {
            let hide = fo <= 0.001
            if l.isHidden != hide { l.isHidden = hide }
            if !hide { l.opacity = fo }
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let engine = Engine()
    let pip = Pip()
    let defaults = UserDefaults.standard
    var overlays: [Overlay] = []
    var statusItem: NSStatusItem?
    var timer: Timer?
    var art = Sprites.Set()
    var critter: CritterArt?
    var sprite: SpriteCritter?
    var species: Species = .bunny
    lazy var characterDir: URL? = Bundle.main.resourceURL?.appendingPathComponent("Characters")
    lazy var rendered: [Species] = characterDir.map { SpriteCritter.available(in: $0) } ?? []
    var primaryHeight: CGFloat = 0
    var frameCount = 0
    var lastTime = CACurrentMediaTime()
    var lastMouse = CGPoint(x: -1, y: -1)
    var cursorSpeed = 0.0
    var reversals: [Double] = []
    var lastDirX = 0.0
    var globeCooldown = 0.0
    var dockRect: CGRect?
    var frontId: Int?
    var frostLevel = 0.0
    var activity: NSObjectProtocol?
    var hotKey: EventHotKeyRef?
    var hidden = false

    var seasonChoice = "auto"
    var densityChoice = "steady"
    var brush = true
    var rollEnabled = true
    var ground = true
    var frostEnabled = true
    var globeEnabled = true

    static let densities: [(id: String, label: String, k: Double)] = [
        ("light", "Light", 0.45), ("steady", "Steady", 1), ("storm", "Storm", 2.3),
    ]
    static let winds: [(v: Int, label: String)] = [
        (-4, "Strong, to the left"), (-2, "Breeze, to the left"), (0, "Calm"),
        (2, "Breeze, to the right"), (4, "Strong, to the right"),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep the animation smooth while other apps are in front (no App Nap).
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Drawing the weather")
        loadSettings()
        registerHotKey()
        buildOverlays()
        applySeason()
        refreshPower()
        refreshDock()
        setupStatusItem()

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let t = Timer(timeInterval: 1.0 / 60, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t

        if !defaults.bool(forKey: "welcomed2") {
            defaults.set(true, forKey: "welcomed2")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.showHelp() }
        }
    }

    // MARK: settings

    func flag(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    func loadSettings() {
        seasonChoice = defaults.string(forKey: "season") ?? "auto"
        densityChoice = defaults.string(forKey: "density") ?? "steady"
        brush = flag("brush", true)
        rollEnabled = flag("roll", true)
        ground = flag("ground", true)
        frostEnabled = flag("frost", true)
        globeEnabled = flag("globe", true)
        engine.gusts = flag("gusts", true)
        engine.icicles = flag("icicles", true)
        engine.glassDrops = flag("glassDrops", true)
        pip.enabled = flag("pip", true)
        engine.wind = defaults.integer(forKey: "wind")
        engine.paused = defaults.bool(forKey: "paused")
        engine.density = AppDelegate.densities.first { $0.id == densityChoice }?.k ?? 1
        species = Species(rawValue: defaults.string(forKey: "species") ?? "") ?? .bunny
    }

    func saveSettings() {
        defaults.set(seasonChoice, forKey: "season")
        defaults.set(densityChoice, forKey: "density")
        defaults.set(brush, forKey: "brush")
        defaults.set(rollEnabled, forKey: "roll")
        defaults.set(ground, forKey: "ground")
        defaults.set(frostEnabled, forKey: "frost")
        defaults.set(globeEnabled, forKey: "globe")
        defaults.set(engine.gusts, forKey: "gusts")
        defaults.set(engine.icicles, forKey: "icicles")
        defaults.set(engine.glassDrops, forKey: "glassDrops")
        defaults.set(pip.enabled, forKey: "pip")
        defaults.set(engine.wind, forKey: "wind")
        defaults.set(engine.paused, forKey: "paused")
        defaults.set(species.rawValue, forKey: "species")
    }

    // MARK: displays

    func buildOverlays() {
        overlays.forEach { $0.close() }
        overlays.removeAll()
        guard let primary = NSScreen.screens.first else { return }
        primaryHeight = primary.frame.height
        var sims: [ScreenSim] = []
        for screen in NSScreen.screens {
            let f = screen.frame
            let q = CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
            let sim = ScreenSim(frame: q)
            sims.append(sim)
            overlays.append(Overlay(screen: screen, qFrame: q, sim: sim))
        }
        engine.screens = sims
    }

    @objc func screensChanged() {
        buildOverlays()
        applySeason()
    }

    func currentSeason() -> Season {
        if seasonChoice == "auto" { return Season.forDate(Date()) }
        return Season.all.first { $0.id == seasonChoice } ?? Season.all[0]
    }

    func applySeason() {
        let s = currentSeason()
        let maxScale = NSScreen.screens.map { $0.backingScaleFactor }.max() ?? 2
        art = Sprites.set(for: s.kind, scale: maxScale)
        engine.setSeason(s, near: art.near.count, far: art.far.count)
        if (critter == nil && sprite == nil) || (critter?.species ?? sprite?.species) != species { buildCritter() }
        overlays.forEach { $0.seasonChanged() }
        updateStatusIcon()
    }

    /// Uses the 3D-rendered character when its art is in the app bundle; otherwise draws one in code.
    func buildCritter() {
        if let dir = characterDir, rendered.contains(species), let s = SpriteCritter(species, base: dir) {
            sprite = s
            critter = nil
            return
        }
        sprite = nil
        let maxScale = NSScreen.screens.map { $0.backingScaleFactor }.max() ?? 2
        critter = CritterArt(species, k: 4 * maxScale)
    }

    // MARK: frame loop

    @objc func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.05, now - lastTime)
        lastTime = now
        frameCount += 1

        // Paused with nothing moving and no Pip: run at 15 fps so piles still follow windows.
        let idle = engine.paused && !pip.enabled && engine.rolling == nil && engine.screens.allSatisfy { $0.flings.isEmpty }
        if idle && frameCount % 4 != 0 { return }
        let step = idle ? dt * 4 : dt

        if frameCount % 2 == 0 || idle { refreshSurfaces() }
        if frameCount % 120 == 0 { refreshDock() }
        if frameCount % 600 == 0 { refreshPower(); checkCalendar() }

        let userIdle = idleSeconds()
        handleCursor(step)
        engine.step(step)
        let m = NSEvent.mouseLocation
        pip.update(step, engine, PipInput(cursorX: Double(m.x), cursorY: Double(primaryHeight - m.y),
                                          cursorSpeed: cursorSpeed, userIdle: userIdle, frontId: frontId))

        // frost creeps in while you're away (snow only) and melts when you come back
        if frostEnabled && engine.season.kind == .snow && userIdle > 25 {
            frostLevel = min(1, frostLevel + step / 50)
        } else {
            frostLevel = max(0, frostLevel - step * 0.8)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for o in overlays { o.render(engine, art, pip: pip, critter: critter, sprite: sprite, frostLevel: pow(frostLevel, 1.3) * 0.9) }
        CATransaction.commit()
    }

    func idleSeconds() -> Double {
        let a = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved)
        let b = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        let c = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)
        return min(a, min(b, c))
    }

    func handleCursor(_ dt: Double) {
        let m = NSEvent.mouseLocation
        let q = CGPoint(x: m.x, y: primaryHeight - m.y)
        let option = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)
        engine.rollUpdate(x: Double(q.x), y: Double(q.y), active: option && rollEnabled)
        if lastMouse.x >= 0 {
            let dx = q.x - lastMouse.x, dy = q.y - lastMouse.y
            let dist = Double(hypot(dx, dy))
            cursorSpeed += (dist / max(dt, 0.001) - cursorSpeed) * 0.35

            if brush && !option && dist > 0 {
                let steps = max(1, Int(ceil(dist / 6)))
                if steps < 200 {
                    for i in 1...steps {
                        let f = CGFloat(i) / CGFloat(steps)
                        engine.sweep(x: Double(lastMouse.x + dx * f), y: Double(lastMouse.y + dy * f), vx: Double(dx) * 30)
                    }
                }
            }

            // Snow globe: shake the mouse quickly from side to side.
            globeCooldown = max(0, globeCooldown - dt)
            let vx = Double(dx) / max(dt, 0.001)
            if abs(vx) > 900 {
                let dir: Double = vx > 0 ? 1 : -1
                if dir != lastDirX && lastDirX != 0 { reversals.append(engine.t) }
                lastDirX = dir
            }
            reversals.removeAll { engine.t - $0 > 0.9 }
            if globeEnabled && reversals.count >= 5 && globeCooldown == 0 {
                reversals.removeAll()
                globeCooldown = 3
                engine.snowGlobe(x: Double(q.x), y: Double(q.y))
                pip.snowGlobe(engine, x: Double(q.x), y: Double(q.y))
            }
        }
        lastMouse = q
    }

    // MARK: windows, Dock, power

    func refreshSurfaces() {
        var list: [Engine.SurfaceInput] = []
        let screens = engine.screens.map { $0.frame }
        if let d = dockRect { list.append(Engine.SurfaceInput(id: -1, rect: d, kind: .dock, maxScale: 0.8)) }

        var front: Int? = nil
        let me = ProcessInfo.processInfo.processIdentifier
        if let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for w in info {
                guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
                      let pid = w[kCGWindowOwnerPID as String] as? Int32, pid != me,
                      let num = w[kCGWindowNumber as String] as? Int,
                      let bd = w[kCGWindowBounds as String] as? NSDictionary,
                      let rect = CGRect(dictionaryRepresentation: bd as CFDictionary) else { continue }
                let alpha = (w[kCGWindowAlpha as String] as? Double) ?? 1
                if alpha < 0.1 || rect.width < 80 || rect.height < 40 { continue }
                // Full-screen windows (top edge at the top of a display) hide what's behind but hold no drift.
                let atTop = screens.contains { abs($0.minY - rect.minY) < 2 && rect.minX >= $0.minX - 1 && rect.maxX <= $0.maxX + 1 }
                if front == nil && !atTop { front = num }
                list.append(Engine.SurfaceInput(id: num, rect: rect, isSurface: !atTop))
            }
        }
        frontId = front
        if ground {
            for (i, f) in screens.enumerated() {
                list.append(Engine.SurfaceInput(id: -1000 - i, rect: CGRect(x: f.minX, y: f.maxY, width: f.width, height: 1),
                                                kind: .ground, maxScale: dockRect == nil ? 0.5 : 0.8, occludes: false))
            }
        }
        engine.updateSurfaces(list)
    }

    /// The Dock's icon strip, read through Accessibility (only if the user allowed it).
    func refreshDock() {
        dockRect = nil
        guard AXIsProcessTrusted() else { return }
        guard NSScreen.screens.contains(where: { $0.visibleFrame.minY > $0.frame.minY + 1 }) else { return } // Dock hidden or on the side
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &children) == .success,
              let list = children as? [AXUIElement] else { return }
        for el in list {
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
            guard (role as? String) == (kAXListRole as String) else { continue }
            var posRef: CFTypeRef?, sizeRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
                  AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success,
                  let pv = posRef, let sv = sizeRef,
                  CFGetTypeID(pv) == AXValueGetTypeID(), CFGetTypeID(sv) == AXValueGetTypeID() else { continue }
            var pos = CGPoint.zero, size = CGSize.zero
            AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
            AXValueGetValue(sv as! AXValue, .cgSize, &size)
            if size.width > size.height && size.width > 50 { dockRect = CGRect(origin: pos, size: size) }
            return
        }
    }

    func refreshPower() {
        var k = 1.0
        if ProcessInfo.processInfo.isLowPowerModeEnabled { k *= 0.5 }
        switch ProcessInfo.processInfo.thermalState {
        case .serious: k *= 0.5
        case .critical: k *= 0.25
        default: break
        }
        engine.powerScale = k
    }

    func checkCalendar() {
        if seasonChoice == "auto" && Season.forDate(Date()).id != engine.season.id { applySeason() }
    }

    // MARK: menu bar

    func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateStatusIcon()
    }

    func symbol(_ name: String) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "snowflake", accessibilityDescription: nil)
        img?.isTemplate = true
        return img
    }

    func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        button.image = symbol(engine.season.symbol)
        button.appearsDisabled = engine.paused
        button.toolTip = "Drift · \(engine.season.label)" + (engine.paused ? " (paused)" : "")
    }

    func item(_ title: String, _ action: Selector?, key: String = "", rep: Any? = nil, on: Bool = false) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = self
        it.representedObject = rep
        it.state = on ? .on : .off
        return it
    }

    func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.submenu = menu
        return it
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let head = NSMenuItem(title: "Drift · \(engine.season.label)", action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        menu.addItem(item(engine.paused ? "Resume falling   ⌃⌥⌘D" : "Pause falling   ⌃⌥⌘D", #selector(togglePause), key: "p"))
        menu.addItem(item(hidden ? "Show Drift" : "Hide Drift (leaves, piles and Pip)", #selector(toggleHidden), key: "h"))
        menu.addItem(.separator())

        let seasons = NSMenu()
        seasons.addItem(item("Follow the calendar", #selector(pickSeason(_:)), rep: "auto", on: seasonChoice == "auto"))
        seasons.addItem(.separator())
        for s in Season.all {
            let it = item(s.label, #selector(pickSeason(_:)), rep: s.id, on: seasonChoice == s.id)
            it.image = symbol(s.symbol)
            seasons.addItem(it)
        }
        menu.addItem(submenu("Season", seasons))

        let fall = NSMenu()
        for d in AppDelegate.densities { fall.addItem(item(d.label, #selector(pickDensity(_:)), rep: d.id, on: densityChoice == d.id)) }
        menu.addItem(submenu("Fall", fall))

        let wind = NSMenu()
        for w in AppDelegate.winds { wind.addItem(item(w.label, #selector(pickWind(_:)), rep: w.v, on: engine.wind == w.v)) }
        wind.addItem(.separator())
        wind.addItem(item("Natural gusts", #selector(toggleGusts), on: engine.gusts))
        menu.addItem(submenu("Wind", wind))

        let pipMenu = NSMenu()
        pipMenu.addItem(item("Show Pip", #selector(togglePip), on: pip.enabled))
        pipMenu.addItem(item("Call Pip to this window", #selector(callPip), key: "j"))
        pipMenu.addItem(.separator())
        for sp in Species.allCases {
            pipMenu.addItem(item(sp.label, #selector(pickSpecies(_:)), rep: sp.rawValue, on: species == sp))
        }
        menu.addItem(submenu("Pip", pipMenu))

        let fx = NSMenu()
        fx.addItem(item("Icicles on deep drifts", #selector(toggleIcicles), on: engine.icicles))
        fx.addItem(item("Frost while you're away", #selector(toggleFrost), on: frostEnabled))
        fx.addItem(item("Raindrops on the glass", #selector(toggleDrops), on: engine.glassDrops))
        fx.addItem(item("Snow globe (shake the mouse)", #selector(toggleGlobe), on: globeEnabled))
        fx.addItem(.separator())
        fx.addItem(item("Brush drifts with the cursor", #selector(toggleBrush), on: brush))
        fx.addItem(item("Roll balls while holding ⌥ Option", #selector(toggleRoll), on: rollEnabled))
        fx.addItem(item("Drifts along the bottom of the screen", #selector(toggleGround), on: ground))
        menu.addItem(submenu("Effects", fx))

        menu.addItem(.separator())
        if !AXIsProcessTrusted() { menu.addItem(item("Let drifts settle on the Dock…", #selector(askAccessibility))) }
        menu.addItem(item("Shake off all drifts", #selector(shakeOff), key: "k"))
        menu.addItem(.separator())
        if #available(macOS 13.0, *) {
            menu.addItem(item("Open at login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled))
        }
        menu.addItem(item("How to use Drift", #selector(showHelp)))
        menu.addItem(item("Quit Drift", #selector(quit), key: "q"))
    }

    // MARK: menu actions

    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.togglePause() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x4452_4654), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey | cmdKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }

    @objc func toggleHidden() {
        hidden.toggle()
        for o in overlays {
            if hidden { o.window.orderOut(nil) } else { o.window.orderFrontRegardless() }
        }
        engine.paused = hidden ? true : defaults.bool(forKey: "paused")
        updateStatusIcon()
    }

    @objc func togglePause() {
        if hidden { toggleHidden() }
        engine.paused.toggle()
        if !engine.paused { engine.resume() }
        updateStatusIcon()
        saveSettings()
    }

    @objc func pickSeason(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        seasonChoice = id
        applySeason()
        saveSettings()
    }

    @objc func pickDensity(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let d = AppDelegate.densities.first(where: { $0.id == id }) else { return }
        densityChoice = id
        engine.density = d.k
        saveSettings()
    }

    @objc func pickWind(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? Int else { return }
        engine.wind = v
        saveSettings()
    }

    @objc func togglePip() {
        pip.enabled.toggle()
        if pip.enabled { pip.reset(engine) }
        saveSettings()
    }

    @objc func pickSpecies(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let sp = Species(rawValue: id) else { return }
        species = sp
        buildCritter()
        saveSettings()
    }

    @objc func callPip() {
        if !pip.enabled { pip.enabled = true; saveSettings() }
        pip.call(engine, to: frontId)
    }

    @objc func toggleGusts() { engine.gusts.toggle(); saveSettings() }
    @objc func toggleIcicles() { engine.icicles.toggle(); saveSettings() }
    @objc func toggleFrost() { frostEnabled.toggle(); saveSettings() }
    @objc func toggleDrops() { engine.glassDrops.toggle(); saveSettings() }
    @objc func toggleGlobe() { globeEnabled.toggle(); saveSettings() }
    @objc func toggleBrush() { brush.toggle(); saveSettings() }
    @objc func toggleRoll() { rollEnabled.toggle(); saveSettings() }
    @objc func toggleGround() { ground.toggle(); saveSettings() }
    @objc func shakeOff() { engine.shakeOffAll() }

    @objc func askAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    @objc func toggleLogin() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
                else { try SMAppService.mainApp.register() }
            } catch {
                NSLog("Drift: could not change login item: \(error.localizedDescription)")
            }
        }
    }

    @objc func showHelp() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Drift is running"
        a.informativeText = """
        Snow, petals or leaves fall over your desktop and settle on your windows. Clicks pass straight through.

        Meet Pip, a baby lamb, otter, seal pup or hedgehog (your choice in the Pip menu) who lives on your windows. Pip wanders, hops between windows, catches flakes, builds snowmen, \
        and comes over when you switch windows. Rest the cursor on Pip to pet it. Sweep past quickly and it jumps. \
        Leave the Mac alone and Pip falls asleep.

        • Brush: move the cursor over a drift to sweep it away.
        • Roll: hold ⌥ Option and move along a drift to roll a ball. Stack two for a snowman.
        • Snow globe: shake the mouse quickly from side to side.
        • Shake: drag a window fast and its drift (and Pip) falls off.
        • Frost grows in the corners while you're away.

        Season, wind, Pip and effects are in the menu bar icon.
        """
        a.addButton(withTitle: "OK")
        a.runModal()
    }

    @objc func quit() { NSApp.terminate(nil) }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
