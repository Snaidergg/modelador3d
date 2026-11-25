import Geometry
import MetalKit
import Rendering
import SwiftUI

/// Puente entre SwiftUI y el render en Metal.
/// Gestos: 1 dedo = girar · 2 dedos = desplazar · pellizcar = zoom · doble toque = encuadrar.
struct MetalViewport: UIViewRepresentable {
    let mesh: Mesh
    let version: Int
    let smoothShading: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        guard let renderer = MeshRenderer(view: view) else { return view }
        renderer.smoothShading = smoothShading
        renderer.setMesh(mesh, frameCamera: true)
        view.delegate = renderer

        let coordinator = context.coordinator
        coordinator.renderer = renderer
        coordinator.lastVersion = version
        coordinator.mesh = mesh
        coordinator.attachGestures(to: view)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        let coordinator = context.coordinator
        guard let renderer = coordinator.renderer else { return }
        coordinator.mesh = mesh

        let shadingChanged = renderer.smoothShading != smoothShading
        renderer.smoothShading = smoothShading

        if coordinator.lastVersion != version {
            coordinator.lastVersion = version
            renderer.setMesh(mesh, frameCamera: true)
        } else if shadingChanged {
            renderer.setMesh(mesh, frameCamera: false)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var renderer: MeshRenderer?
        var lastVersion = -1
        var mesh = Mesh()

        func attachGestures(to view: UIView) {
            let orbit = UIPanGestureRecognizer(target: self, action: #selector(handleOrbit(_:)))
            orbit.maximumNumberOfTouches = 1

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.minimumNumberOfTouches = 2

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
            doubleTap.numberOfTapsRequired = 2

            for recognizer in [orbit, pan, pinch, doubleTap] as [UIGestureRecognizer] {
                recognizer.delegate = self
                view.addGestureRecognizer(recognizer)
            }
        }

        @objc func handleOrbit(_ g: UIPanGestureRecognizer) {
            guard let view = g.view else { return }
            let t = g.translation(in: view)
            renderer?.camera.orbit(dx: Float(t.x), dy: Float(t.y))
            g.setTranslation(.zero, in: view)
        }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard let view = g.view else { return }
            let t = g.translation(in: view)
            renderer?.camera.pan(dx: Float(t.x), dy: Float(t.y))
            g.setTranslation(.zero, in: view)
        }

        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            renderer?.camera.zoom(by: Float(g.scale))
            g.scale = 1
        }

        @objc func handleDoubleTap() {
            renderer?.camera.frame(mesh.bounds)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
