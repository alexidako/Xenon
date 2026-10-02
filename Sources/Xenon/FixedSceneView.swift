import SwiftUI
import SceneKit
import simd

/// Camera state for a molecule viewer: the model rotates about its own centre and the camera only moves in and out,
/// within limits, so the model can never be dragged out of view. Kept separate from the view so it can be tested.
struct TrackballState: Equatable {
    var orientation: simd_quatf
    var distance: Float
    let base: Float
    let initial: simd_quatf

    init(distance: Float, tilt: (x: Float, y: Float) = (0, 0)) {
        let q = simd_quatf(angle: tilt.x, axis: SIMD3<Float>(1, 0, 0)) * simd_quatf(angle: tilt.y, axis: SIMD3<Float>(0, 1, 0))
        self.orientation = q; self.initial = q
        self.distance = distance; self.base = distance
    }

    var minDistance: Float { base * 0.3 }
    var maxDistance: Float { base * 2.0 }

    /// Drag by (dx, dy) screen points: horizontal drag spins about the vertical axis, vertical drag about the horizontal axis.
    mutating func rotate(dx: Float, dy: Float) {
        let qy = simd_quatf(angle: dx * 0.01, axis: SIMD3<Float>(0, 1, 0))
        let qx = simd_quatf(angle: dy * 0.01, axis: SIMD3<Float>(1, 0, 0))
        orientation = simd_normalize(qx * qy * orientation)
    }

    /// Positive amount = zoom in.
    mutating func zoom(_ amount: Float) {
        distance = min(maxDistance, max(minDistance, distance * exp(-amount)))
    }

    mutating func reset() { orientation = initial; distance = base }
}

/// A SceneKit view with a fixed camera and trackball rotation. Drag to rotate, scroll or pinch to zoom,
/// double-click to reset. Increase `resetToken` to reset from outside (e.g. a button).
struct FixedSceneView: NSViewRepresentable {
    let scene: SCNScene
    let distance: CGFloat
    var tilt: (x: CGFloat, y: CGFloat) = (0, 0)
    var resetToken = 0
    /// When this changes the scene is swapped in place (camera angle and zoom are kept) instead of rebuilding the view.
    var sceneKey = ""

    func makeNSView(context: Context) -> TrackballSCNView {
        let v = TrackballSCNView()
        v.configure(scene: scene, distance: Float(distance), tilt: (Float(tilt.x), Float(tilt.y)))
        v.lastResetToken = resetToken; v.sceneKey = sceneKey
        return v
    }

    func updateNSView(_ v: TrackballSCNView, context: Context) {
        if v.sceneKey != sceneKey { v.sceneKey = sceneKey; v.swap(scene: scene) }
        if v.lastResetToken != resetToken { v.lastResetToken = resetToken; v.resetView() }
    }
}

final class TrackballSCNView: SCNView {
    private var state = TrackballState(distance: 8)
    private let pivot = SCNNode()
    private let cameraNode = SCNNode()
    var lastResetToken = 0
    var sceneKey = ""

    /// Replace the contents but keep the user's rotation and zoom.
    func swap(scene newScene: SCNScene) {
        let keep = state
        configure(scene: newScene, distance: keep.base, tilt: (0, 0))
        state.orientation = keep.orientation; state.distance = keep.distance
        apply()
    }

    func configure(scene: SCNScene, distance: Float, tilt: (x: Float, y: Float)) {
        // Everything in the scene hangs off one pivot; any camera the caller added is replaced by ours.
        let root = scene.rootNode
        pivot.childNodes.forEach { $0.removeFromParentNode() }     // drop whatever the previous scene left on the pivot
        pivot.removeFromParentNode(); cameraNode.removeFromParentNode()
        for child in root.childNodes {
            if child.camera != nil { child.removeFromParentNode(); continue }
            child.removeFromParentNode(); pivot.addChildNode(child)
        }
        root.addChildNode(pivot)
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.1; cameraNode.camera?.zFar = 500
        root.addChildNode(cameraNode)
        self.scene = scene
        self.pointOfView = cameraNode
        self.autoenablesDefaultLighting = true
        self.allowsCameraControl = false
        self.backgroundColor = NSColor(white: 0.1, alpha: 1)
        self.antialiasingMode = .multisampling4X
        state = TrackballState(distance: distance, tilt: tilt)
        apply()
    }

    private func apply() {
        pivot.simdOrientation = state.orientation
        cameraNode.simdPosition = SIMD3<Float>(0, 0, state.distance)
    }

    func resetView() { state.reset(); apply() }

    private var lastPoint = CGPoint.zero
    private var lastClick = Date.distantPast

    override func mouseDown(with event: NSEvent) {
        lastPoint = event.locationInWindow
        // Double-click: use the system's click count, or two clicks close together in time.
        let now = Date()
        if event.clickCount >= 2 || now.timeIntervalSince(lastClick) < 0.35 { resetView(); lastClick = .distantPast } else { lastClick = now }
    }

    /// Movement is taken from the cursor position rather than the event's delta fields, so it works for every kind of pointer.
    override func mouseDragged(with event: NSEvent) {
        let p = event.locationInWindow
        state.rotate(dx: Float(p.x - lastPoint.x), dy: Float(lastPoint.y - p.y))       // window y points up, screen y points down
        lastPoint = p; apply()
    }
    override func rightMouseDragged(with event: NSEvent) {
        let p = event.locationInWindow
        state.zoom(Float(p.y - lastPoint.y) * 0.01); lastPoint = p; apply()
    }
    override func scrollWheel(with event: NSEvent) { state.zoom(Float(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 0.01 : 0.05)); apply() }
    override func magnify(with event: NSEvent) { state.zoom(Float(event.magnification) * 1.6); apply() }
    override var acceptsFirstResponder: Bool { true }
}

@MainActor enum TrackballSelfTest {
    static func run() {
        func scene(_ n: Int) -> SCNScene {
            let sc = SCNScene()
            for _ in 0..<n { sc.rootNode.addChildNode(SCNNode(geometry: SCNSphere(radius: 1))) }
            return sc
        }
        func count(_ v: TrackballSCNView) -> Int { v.scene!.rootNode.childNodes.flatMap { $0.childNodes }.count }
        let view = TrackballSCNView()
        view.configure(scene: scene(3), distance: 8, tilt: (0, 0))
        view.swap(scene: scene(1))
        view.swap(scene: scene(2))
        let sizes = view.scene!.rootNode.childNodes.map { $0.childNodes.count }
        SelfTest.check(sizes.sorted() == [0, 2], "viewer: swapping scenes shows only the new content (no leftovers from earlier ones)", "\(sizes)")
        view.swap(scene: scene(1))
        SelfTest.check(count(view) == 1 && view.scene!.rootNode.childNodes.count == 2, "viewer: after several swaps there is exactly one pivot and one camera", "\(view.scene!.rootNode.childNodes.count)")

        var s = TrackballState(distance: 10)
        var seed: UInt64 = 99
        func rnd() -> Float { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Float((seed >> 33) % 2000) / 1000 - 1 }
        for _ in 0..<2000 { s.rotate(dx: rnd() * 80, dy: rnd() * 80); s.zoom(rnd() * 3) }
        SelfTest.check(s.distance >= s.minDistance - 1e-4 && s.distance <= s.maxDistance + 1e-4, "viewer: no amount of zooming can push the camera outside its limits", "\(s.distance) in \(s.minDistance)…\(s.maxDistance)")
        SelfTest.check(abs(simd_length(s.orientation.vector) - 1) < 1e-3, "viewer: rotation stays a valid rotation after 2000 random drags", "\(simd_length(s.orientation.vector))")
        s.reset()
        SelfTest.check(s.orientation == s.initial && s.distance == 10, "viewer: reset restores the original view")
        var z = TrackballState(distance: 10)
        for _ in 0..<50 { z.zoom(5) }
        let closest = z.distance
        for _ in 0..<50 { z.zoom(-5) }
        SelfTest.check(abs(closest - 3) < 1e-3 && abs(z.distance - 20) < 1e-3, "viewer: zoom stops at 30% and 200% of the starting distance", "\(closest) \(z.distance)")
        // the model stays centred: the camera only ever moves along its own axis, the model only rotates
        var r = TrackballState(distance: 10)
        r.rotate(dx: 100, dy: 0)
        let spun = r.orientation.act(SIMD3<Float>(0, 0, 1))
        SelfTest.check(simd_dot(spun, SIMD3<Float>(1, 0, 0)) > 0.5, "viewer: dragging right turns the front of the molecule to the right", "\(spun)")
        var d = TrackballState(distance: 10)
        d.rotate(dx: 0, dy: 100)
        let tipped = d.orientation.act(SIMD3<Float>(0, 1, 0))
        SelfTest.check(tipped.z > 0.5, "viewer: dragging down brings the top of the molecule toward you", "\(tipped)")
    }
}
