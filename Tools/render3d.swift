// Renders a 3D character (USDZ, e.g. a Meshy export) into the Mac app's sprite format:
// one whole-body image, feet at y = 0, 3/4 view facing left, transparent background.
//   swiftc -O Tools/render3d.swift -o build/render3d
//   build/render3d iOS/App/Pip3D.usdz Resources/Characters/penguin/model3d.png [height=34] [ortho=60] [centerY=28]
import AppKit
import SceneKit

let a = CommandLine.arguments
guard a.count >= 3 else { print("usage: render3d <model.usdz> <out.png> [height] [ortho] [centerY]"); exit(1) }
let height = a.count > 3 ? CGFloat(Double(a[3]) ?? 34) : 34
let ortho = a.count > 4 ? CGFloat(Double(a[4]) ?? 60) : 60
let centerY = a.count > 5 ? CGFloat(Double(a[5]) ?? 28) : 28
let px = 600

let loaded = try SCNScene(url: URL(fileURLWithPath: a[1]), options: [.checkConsistency: false])
let scene = SCNScene()
let model = SCNNode()
for c in loaded.rootNode.childNodes { model.addChildNode(c) }
model.enumerateHierarchy { n, _ in
    for m in n.geometry?.materials ?? [] { m.lightingModel = .physicallyBased; m.metalness.contents = 0.0 }
}
let (lo, hi) = model.boundingBox
let s = height / CGFloat(hi.y - lo.y)
model.scale = SCNVector3(s, s, s)
model.position = SCNVector3(-(lo.x + hi.x) / 2 * s, -lo.y * s, -(lo.z + hi.z) / 2 * s)
let turn = SCNNode()
turn.addChildNode(model)
turn.eulerAngles.y = -0.55          // three-quarter view, looking left
scene.rootNode.addChildNode(turn)

func light(_ type: SCNLight.LightType, _ i: CGFloat, _ c: NSColor, _ e: SCNVector3) {
    let l = SCNLight(); l.type = type; l.intensity = i; l.color = c
    let n = SCNNode(); n.light = l; n.eulerAngles = e; scene.rootNode.addChildNode(n)
}
light(.directional, 1500, NSColor(red: 1, green: 0.96, blue: 0.9, alpha: 1), SCNVector3(-0.9, 0.5, 0))
light(.directional, 300, NSColor(red: 0.8, green: 0.88, blue: 1, alpha: 1), SCNVector3(-0.3, -1.0, 0))
light(.directional, 700, .white, SCNVector3(-0.2, .pi, 0))
light(.ambient, 220, .white, SCNVector3(0, 0, 0))

let cam = SCNCamera()
cam.usesOrthographicProjection = true
cam.orthographicScale = Double(ortho / 2)
cam.zNear = 1; cam.zFar = 1000
let camNode = SCNNode(); camNode.camera = cam
camNode.position = SCNVector3(0, centerY, 200)
scene.rootNode.addChildNode(camNode)
scene.background.contents = NSColor.clear

let r = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
r.scene = scene
r.pointOfView = camNode
let img = r.snapshot(atTime: 0, with: CGSize(width: px, height: px), antialiasingMode: .multisampling4X)
guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(2) }
try png.write(to: URL(fileURLWithPath: a[2]))
print("wrote \(a[2])")
