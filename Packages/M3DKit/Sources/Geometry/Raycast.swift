import simd

/// Rayo en el espacio 3D (por ejemplo, desde la cámara a través del dedo).
public struct Ray: Sendable {
    public var origin: SIMD3<Float>
    /// Dirección unitaria.
    public var direction: SIMD3<Float>

    public init(origin: SIMD3<Float>, direction: SIMD3<Float>) {
        self.origin = origin
        let len = simd_length(direction)
        self.direction = len > 0 ? direction / len : SIMD3<Float>(0, 0, -1)
    }
}

public struct RayHit: Sendable {
    public var distance: Float
    public var point: SIMD3<Float>
    public var triangle: Int
}

extension Mesh {
    /// Primer triángulo que toca el rayo (Möller–Trumbore, cuenta ambas caras).
    /// Recorre todos los triángulos: suficiente hasta unos cientos de miles; luego se añadirá un BVH.
    public func raycast(_ ray: Ray) -> RayHit? {
        var bestDistance = Float.infinity
        var bestTriangle = -1
        let epsilon: Float = 1e-10

        for t in triangles.indices {
            let (a, b, c) = corners(of: t)
            let e1 = b - a
            let e2 = c - a
            let pv = simd_cross(ray.direction, e2)
            let det = simd_dot(e1, pv)
            if abs(det) < epsilon { continue }
            let inv = 1 / det
            let tv = ray.origin - a
            let u = simd_dot(tv, pv) * inv
            if u < 0 || u > 1 { continue }
            let qv = simd_cross(tv, e1)
            let v = simd_dot(ray.direction, qv) * inv
            if v < 0 || u + v > 1 { continue }
            let distance = simd_dot(e2, qv) * inv
            if distance > 0, distance < bestDistance {
                bestDistance = distance
                bestTriangle = t
            }
        }

        guard bestTriangle >= 0 else { return nil }
        return RayHit(distance: bestDistance,
                      point: ray.origin + ray.direction * bestDistance,
                      triangle: bestTriangle)
    }
}
