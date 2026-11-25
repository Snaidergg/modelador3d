import Geometry
import simd

/// Cámara que gira alrededor de un punto (como en Blender o Nomad Sculpt).
public struct OrbitCamera: Sendable {
    public var target: SIMD3<Float> = .zero
    public var distance: Float = 100
    public var yaw: Float = 0.7
    public var pitch: Float = 0.35
    public var fovY: Float = 45 * .pi / 180

    public init() {}

    public var eye: SIMD3<Float> {
        target + distance * SIMD3<Float>(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
    }

    /// Dirección desde el objetivo hacia la cámara (se usa como luz frontal).
    public var viewDirection: SIMD3<Float> { simd_normalize(eye - target) }

    /// Vector "derecha" de la pantalla, en el mundo.
    public var right: SIMD3<Float> {
        simd_normalize(simd_cross(simd_normalize(target - eye), SIMD3<Float>(0, 1, 0)))
    }

    /// Vector "arriba" de la pantalla, en el mundo.
    public var up: SIMD3<Float> {
        simd_cross(right, simd_normalize(target - eye))
    }

    public func viewMatrix() -> simd_float4x4 {
        Matrices.lookAt(eye: eye, target: target, up: SIMD3<Float>(0, 1, 0))
    }

    public func projectionMatrix(aspect: Float) -> simd_float4x4 {
        Matrices.perspective(fovY: fovY, aspect: max(aspect, 0.01), near: distance * 0.01, far: distance * 20)
    }

    /// Encuadra un modelo completo en pantalla.
    public mutating func frame(_ bounds: BoundingBox) {
        target = bounds.center
        let radius = max(bounds.radius, 0.001)
        distance = radius / sin(fovY * 0.5) * 1.15
    }

    public mutating func orbit(dx: Float, dy: Float) {
        yaw -= dx * 0.008
        pitch = min(max(pitch + dy * 0.008, -1.5), 1.5)
    }

    public mutating func zoom(by scale: Float) {
        guard scale > 0 else { return }
        distance = min(max(distance / scale, 0.01), 100_000)
    }

    public mutating func pan(dx: Float, dy: Float) {
        let forward = simd_normalize(target - eye)
        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = simd_cross(right, forward)
        let k = distance * 0.0015
        target -= right * dx * k
        target += up * dy * k
    }
}
