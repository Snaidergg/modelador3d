import Geometry
import MetalKit
import Rendering
import Sculpt
import simd
import SwiftUI

/// Puente entre SwiftUI y el render en Metal.
/// Modo ver: 1 dedo = girar · 2 dedos = desplazar · pellizcar = zoom · doble toque = encuadrar.
/// Modo esculpir: 1 dedo sobre el modelo = pincel; 1 dedo fuera del modelo = girar.
struct MetalViewport: UIViewRepresentable {
    let mesh: Mesh
    let version: Int
    let frameVersion: Int
    let smoothShading: Bool
    let mode: EditorMode
    let sculptSettings: SculptSettings
    /// Altura del plano de corte a dibujar (solo en modo recorte).
    let cutPlaneY: Float?
    let onStrokeEnded: @MainActor (Mesh, BrushKind) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        guard let renderer = MeshRenderer(view: view) else { return view }
        renderer.smoothShading = smoothShading
        renderer.setMesh(mesh)
        renderer.frame(mesh.bounds)
        view.delegate = renderer

        let coordinator = context.coordinator
        coordinator.renderer = renderer
        coordinator.lastVersion = version
        coordinator.lastFrameVersion = frameVersion
        coordinator.mesh = mesh
        coordinator.attachGestures(to: view)
        apply(to: coordinator)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        let coordinator = context.coordinator
        apply(to: coordinator)
        guard let renderer = coordinator.renderer else { return }

        let shadingChanged = renderer.smoothShading != smoothShading
        renderer.smoothShading = smoothShading

        if coordinator.lastVersion != version {
            coordinator.lastVersion = version
            coordinator.mesh = mesh
            coordinator.engine = nil // se recrea con la malla nueva al empezar el próximo trazo
            renderer.setMesh(mesh)
        } else if shadingChanged {
            renderer.setMesh(coordinator.engine?.mesh ?? mesh)
        }

        if coordinator.lastFrameVersion != frameVersion {
            coordinator.lastFrameVersion = frameVersion
            renderer.frame(mesh.bounds)
        }
    }

    private func apply(to coordinator: Coordinator) {
        coordinator.mode = mode
        coordinator.settings = sculptSettings
        coordinator.onStrokeEnded = onStrokeEnded
        coordinator.renderer?.cutPlaneY = cutPlaneY
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var renderer: MeshRenderer?
        var engine: SculptEngine?
        var mesh = Mesh()
        var lastVersion = -1
        var lastFrameVersion = -1
        var mode: EditorMode = .view
        var settings = SculptSettings()
        var onStrokeEnded: (@MainActor (Mesh, BrushKind) -> Void)?

        // Estado del trazo en curso
        private var stroking = false
        private var strokeBrush: BrushKind = .draw
        private var lastPoint: CGPoint = .zero
        private var lastDabPoint: CGPoint = .zero
        private var grabStart: CGPoint = .zero
        private var grabUnitsPerPoint: Float = 0
        private var grabRight = SIMD3<Float>(1, 0, 0)
        private var grabUp = SIMD3<Float>(0, 1, 0)

        func attachGestures(to view: UIView) {
            let primary = UIPanGestureRecognizer(target: self, action: #selector(handlePrimary(_:)))
            primary.maximumNumberOfTouches = 1

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.minimumNumberOfTouches = 2

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
            doubleTap.numberOfTapsRequired = 2

            for recognizer in [primary, pan, pinch, doubleTap] as [UIGestureRecognizer] {
                recognizer.delegate = self
                view.addGestureRecognizer(recognizer)
            }
        }

        // MARK: Un dedo: esculpir u orbitar

        @objc func handlePrimary(_ g: UIPanGestureRecognizer) {
            guard let view = g.view, let renderer else { return }
            let point = g.location(in: view)

            switch g.state {
            case .began:
                // El gesto se reconoce tras unos puntos de movimiento: el trazo empieza donde se tocó.
                let t = g.translation(in: view)
                let start = CGPoint(x: point.x - t.x, y: point.y - t.y)
                stroking = mode == .sculpt && beginStroke(at: start, in: view, renderer: renderer)
                lastPoint = start
                if stroking { continueStroke(to: point, in: view, renderer: renderer) }
                lastPoint = point

            case .changed:
                if stroking {
                    continueStroke(to: point, in: view, renderer: renderer)
                } else {
                    renderer.camera.orbit(dx: Float(point.x - lastPoint.x), dy: Float(point.y - lastPoint.y))
                }
                lastPoint = point

            case .ended, .cancelled, .failed:
                if stroking { endStroke() }
                stroking = false

            default:
                break
            }
        }

        private func sculptEngine() -> SculptEngine {
            if let engine { return engine }
            let created = SculptEngine(mesh: mesh)
            engine = created
            return created
        }

        private func worldRadius(at hit: SIMD3<Float>, in view: UIView, renderer: MeshRenderer) -> Float {
            let distance = simd_distance(renderer.camera.eye, hit)
            return settings.radius * renderer.worldUnitsPerPoint(atDistance: distance, viewHeight: view.bounds.height)
        }

        private func beginStroke(at point: CGPoint, in view: UIView, renderer: MeshRenderer) -> Bool {
            let engine = sculptEngine()
            guard let hit = engine.hit(renderer.ray(through: point, viewSize: view.bounds.size)) else { return false }
            strokeBrush = settings.brush
            let radius = worldRadius(at: hit, in: view, renderer: renderer)

            if strokeBrush == .grab {
                engine.beginGrab(at: hit, radius: radius, symmetryX: settings.symmetryX)
                grabStart = point
                grabUnitsPerPoint = renderer.worldUnitsPerPoint(atDistance: simd_distance(renderer.camera.eye, hit),
                                                                viewHeight: view.bounds.height)
                grabRight = renderer.camera.right
                grabUp = renderer.camera.up
            } else {
                engine.applyDab(at: hit, radius: radius, settings: settings)
                lastDabPoint = point
            }
            renderer.setMesh(engine.mesh)
            return true
        }

        private func continueStroke(to point: CGPoint, in view: UIView, renderer: MeshRenderer) {
            guard let engine else { return }

            if strokeBrush == .grab {
                let dx = Float(point.x - grabStart.x)
                let dy = Float(point.y - grabStart.y)
                let delta = (grabRight * dx - grabUp * dy) * grabUnitsPerPoint
                engine.updateGrab(delta: delta)
                renderer.setMesh(engine.mesh)
                return
            }

            // Toques espaciados a lo largo del recorrido para que el trazo sea continuo.
            let spacing = max(2, CGFloat(settings.radius) * 0.25)
            let dx = point.x - lastDabPoint.x
            let dy = point.y - lastDabPoint.y
            let length = (dx * dx + dy * dy).squareRoot()
            guard length >= spacing else { return }

            let steps = Int(length / spacing)
            var applied = false
            for step in 1...steps {
                let f = CGFloat(step) / CGFloat(steps)
                let sample = CGPoint(x: lastDabPoint.x + dx * f, y: lastDabPoint.y + dy * f)
                guard let hit = engine.hit(renderer.ray(through: sample, viewSize: view.bounds.size)) else { continue }
                var dabSettings = settings
                dabSettings.brush = strokeBrush
                engine.applyDab(at: hit, radius: worldRadius(at: hit, in: view, renderer: renderer), settings: dabSettings)
                applied = true
            }
            lastDabPoint = point
            if applied { renderer.setMesh(engine.mesh) }
        }

        private func endStroke() {
            guard let engine else { return }
            engine.endStroke()
            onStrokeEnded?(engine.mesh, strokeBrush)
        }

        // MARK: Dos dedos y doble toque: cámara

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
            renderer?.frame((engine?.mesh ?? mesh).bounds)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
