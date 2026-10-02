// Renders the app logo: a 3D N≡N molecule on a macOS-style rounded tile. Usage: make_logo <out.png>
import AppKit
import SceneKit
import Metal

let out = CommandLine.arguments[1]
let size = 1024

// MARK: scene
let scene = SCNScene()
func mat(_ c: NSColor, shiny: Bool = true) -> SCNMaterial {
    let m = SCNMaterial(); m.lightingModel = .physicallyBased
    m.diffuse.contents = c; m.metalness.contents = 0.0; m.roughness.contents = shiny ? 0.22 : 0.4
    return m
}
let blue = NSColor(red: 0.10, green: 0.30, blue: 0.95, alpha: 1)
let mol = SCNNode()
for x in [-1.0, 1.0] {
    let s = SCNNode(geometry: SCNSphere(radius: 0.72)); s.geometry?.firstMaterial = mat(blue)
    (s.geometry as? SCNSphere)?.segmentCount = 96
    s.position = SCNVector3(x * 1.45, 0, 0); mol.addChildNode(s)
}
// triple bond: three parallel cylinders side by side
for k in 0..<3 {
    let c = SCNCylinder(radius: 0.1, height: 2.5); c.radialSegmentCount = 48
    c.firstMaterial = mat(NSColor(white: 0.93, alpha: 1))
    let n = SCNNode(geometry: c)
    n.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
    n.position = SCNVector3(0, 0.3 * Double(k - 1), 0)
    mol.addChildNode(n)
}
mol.eulerAngles = SCNVector3(0.12, -0.35, 0.38)
scene.rootNode.addChildNode(mol)

func light(_ type: SCNLight.LightType, _ intensity: CGFloat, _ pos: SCNVector3) {
    let l = SCNLight(); l.type = type; l.intensity = intensity; l.castsShadow = false
    let n = SCNNode(); n.light = l; n.position = pos; n.look(at: SCNVector3Zero); scene.rootNode.addChildNode(n)
}
light(.omni, 900, SCNVector3(-4, 5, 7)); light(.omni, 250, SCNVector3(5, -3, 4)); light(.ambient, 120, SCNVector3Zero)
let env = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { r in
    NSGradient(colors: [NSColor(white: 0.95, alpha: 1), NSColor(white: 0.25, alpha: 1)])!.draw(in: r, angle: -90); return true }
scene.lightingEnvironment.contents = env; scene.lightingEnvironment.intensity = 0.35

let cam = SCNNode(); cam.camera = SCNCamera(); cam.camera!.fieldOfView = 26
cam.position = SCNVector3(0, 0, 11); scene.rootNode.addChildNode(cam)

let device = MTLCreateSystemDefaultDevice()!
let renderer = SCNRenderer(device: device, options: nil)
renderer.scene = scene; renderer.pointOfView = cam
let molImage = renderer.snapshot(atTime: 0, with: CGSize(width: size, height: size), antialiasingMode: .multisampling4X)

// MARK: tile
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow(); shadow.shadowColor = NSColor(white: 0, alpha: 0.4); shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width: 0, height: -10); shadow.set()
NSColor.black.setFill(); path.fill()
NSGraphicsContext.current?.restoreGraphicsState()
NSGradient(colors: [NSColor(red: 0.10, green: 0.13, blue: 0.27, alpha: 1), NSColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 1)])!.draw(in: path, angle: -90)
path.addClip()
NSGradient(colors: [NSColor(red: 0.3, green: 0.5, blue: 1, alpha: 0.35), .clear])!
    .draw(fromCenter: NSPoint(x: 512, y: 540), radius: 0, toCenter: NSPoint(x: 512, y: 540), radius: 420, options: [])
molImage.draw(in: tile.insetBy(dx: 10, dy: 10))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
