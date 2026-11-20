import SceneKit
import SwiftUI
import UIKit

/// Drives the 3D Pip. Each species with a Meshy model has a Pip3D_<species>.usdz in the app. The models have no rig,
/// so every motion is procedural: breathing, waddling, leaning with the phone's tilt,
/// hopping when petted, a dizzy spin on shake and a spin you can flick with a finger.
final class Pip3DController: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    private let pivot = SCNNode()   // sits at Pip's feet: lean, hop, squash
    private let spinner = SCNNode() // turns around the vertical axis
    private let rim = SCNLight()
    private var model = SCNNode()
    private(set) var species: PipSpecies?

    static func hasModel(_ s: PipSpecies) -> Bool {
        Bundle.main.url(forResource: "Pip3D_\(s.rawValue)", withExtension: "usdz") != nil
    }

    /// Gravity in screen space, (0, 1) when the phone is upright.
    var tilt: () -> (Double, Double) = { (0, 1) }

    private let lock = NSLock()
    private var hopAt = -10.0, spinAt = -10.0
    private var yaw = 0.0, yawVel = 0.0, dragging = false

    override init() {
        super.init()
        scene.background.contents = UIColor.clear

        pivot.addChildNode(spinner)
        scene.rootNode.addChildNode(pivot)

        // Lights: warm key with soft shadow, cool fill, seasonal rim from behind.
        let key = SCNLight()
        key.type = .directional
        key.intensity = 1500
        key.color = UIColor(red: 1, green: 0.96, blue: 0.9, alpha: 1)
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowRadius = 8
        key.shadowSampleCount = 8
        key.shadowColor = UIColor.black.withAlphaComponent(0.45)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.9, 0.5, 0)
        scene.rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 280
        fill.color = UIColor(red: 0.8, green: 0.88, blue: 1, alpha: 1)
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(-0.3, -1.0, 0)
        scene.rootNode.addChildNode(fillNode)

        rim.type = .directional
        rim.intensity = 900
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.eulerAngles = SCNVector3(-0.2, .pi, 0)
        scene.rootNode.addChildNode(rimNode)

        let amb = SCNLight()
        amb.type = .ambient
        amb.intensity = 180
        let ambNode = SCNNode()
        ambNode.light = amb
        scene.rootNode.addChildNode(ambNode)

        // Invisible floor that only catches Pip's shadow.
        let floor = SCNFloor()
        floor.reflectivity = 0
        let shadowOnly = SCNMaterial()
        shadowOnly.lightingModel = .shadowOnly
        floor.materials = [shadowOnly]
        scene.rootNode.addChildNode(SCNNode(geometry: floor))

        let cam = SCNCamera()
        cam.fieldOfView = 30
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(0, 1.5, 5.6)
        camNode.look(at: SCNVector3(0, 1.0, 0))
        camNode.name = "camera"
        scene.rootNode.addChildNode(camNode)
    }

    /// Swaps in this species' model (about 2 units tall, feet on the pivot).
    func show(_ s: PipSpecies) {
        guard s != species else { return }
        species = s
        model.removeFromParentNode()
        let m = SCNNode()
        if let url = Bundle.main.url(forResource: "Pip3D_\(s.rawValue)", withExtension: "usdz"),
           let loaded = try? SCNScene(url: url, options: [.checkConsistency: false]) {
            for child in loaded.rootNode.childNodes { m.addChildNode(child) }
        }
        let plush = SCNMaterial()
        plush.lightingModel = .physicallyBased
        plush.diffuse.contents = UIColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1)
        plush.roughness.contents = 0.9
        plush.metalness.contents = 0.0
        m.enumerateHierarchy { n, _ in
            guard let g = n.geometry else { return }
            n.castsShadow = true
            // Textured models (Meshy exports) keep their own colours; a bare mesh gets soft white plush.
            if g.materials.contains(where: { $0.diffuse.contents is UIImage || $0.diffuse.contents is URL || $0.diffuse.contents is String }) {
                for mat in g.materials { mat.lightingModel = .physicallyBased; mat.metalness.contents = 0.0 }
            } else {
                g.materials = [plush]
            }
        }
        let (lo, hi) = m.boundingBox
        let k = 2.0 / max(0.001, hi.y - lo.y)
        m.scale = SCNVector3(k, k, k)
        m.position = SCNVector3(-(lo.x + hi.x) / 2 * k, -lo.y * k, -(lo.z + hi.z) / 2 * k)
        model = m
        spinner.addChildNode(m)
    }

    var cameraNode: SCNNode? { scene.rootNode.childNode(withName: "camera", recursively: false) }

    func setRim(_ color: Color) { rim.color = UIColor(color) }

    func hop() { lock.lock(); hopAt = CACurrentMediaTime(); lock.unlock() }
    func spin() { lock.lock(); spinAt = CACurrentMediaTime(); lock.unlock() }
    func drag(_ dx: Double) { lock.lock(); dragging = true; yaw += dx * 0.012; yawVel = dx * 0.012 * 60; lock.unlock() }
    func endDrag(_ vx: Double) { lock.lock(); dragging = false; yawVel = vx * 0.012; lock.unlock() }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime _: TimeInterval) {
        let t = CACurrentMediaTime()
        lock.lock()
        let hopP = (t - hopAt) / 0.55
        let spinP = (t - spinAt) / 1.3
        if !dragging {
            yaw += yawVel / 60
            yawVel *= 0.95
            if abs(yawVel) < 0.3 { yaw *= 0.97 } // drift back to face the camera
        }
        let yawNow = yaw
        lock.unlock()

        let (gx, _) = tilt()
        let breathe = 1 + 0.018 * sin(t * 2.3)
        var lean = 0.07 * sin(t * 2.8) - gx * 0.35
        var lift = 0.03 * abs(sin(t * 2.8))
        var sx = 1.0 / breathe.squareRoot(), sy = breathe
        if hopP >= 0, hopP < 1 {
            lift += sin(.pi * hopP) * 0.55
            let squash = hopP < 0.15 ? hopP / 0.15 : (hopP > 0.85 ? (1 - hopP) / 0.15 : 0)
            sy *= 1 - 0.12 * squash
            sx *= 1 + 0.08 * squash
            lean *= 0.3
        }
        var turn = yawNow
        if spinP >= 0, spinP < 1 {
            let e = 1 - pow(1 - spinP, 3)
            turn += e * 4 * .pi
            lean += sin(spinP * 18) * 0.12 * (1 - spinP)
        }
        pivot.position = SCNVector3(0, Float(lift), 0)
        pivot.eulerAngles = SCNVector3(0, 0, Float(lean))
        pivot.scale = SCNVector3(Float(sx), Float(sy), Float(sx))
        spinner.eulerAngles = SCNVector3(0, Float(turn), 0)
    }
}

struct Pip3DView: UIViewRepresentable {
    let controller: Pip3DController

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero)
        v.scene = controller.scene
        v.pointOfView = controller.cameraNode
        v.delegate = controller
        v.backgroundColor = .clear
        v.isOpaque = false
        v.antialiasingMode = .multisampling4X
        v.rendersContinuously = true
        v.preferredFramesPerSecond = 60
        v.isPlaying = true
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {}
}
