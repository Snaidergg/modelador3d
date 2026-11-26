import simd

public extension Mesh {
    /// Gira el modelo con un cuaternión (alrededor del origen).
    func rotated(by rotation: simd_quatf) -> Mesh {
        var m = self
        m.positions = positions.map { rotation.act($0) }
        return m
    }

    /// Normal media (ponderada por área) de la zona alrededor de `point`.
    /// Siempre incluye el triángulo `triangle`, así funciona también en caras grandes y planas
    /// (por ejemplo, la tapa de un recorte).
    func averageNormal(around point: SIMD3<Float>, radius: Float, including triangle: Int) -> SIMD3<Float>? {
        var sum = SIMD3<Float>.zero
        let r2 = radius * radius
        for t in triangles.indices {
            let (a, b, c) = corners(of: t)
            let centroid = (a + b + c) / 3
            if t == triangle || simd_length_squared(centroid - point) <= r2 {
                sum += simd_cross(b - a, c - a) // longitud = 2 × área
            }
        }
        let length = simd_length(sum)
        return length > 0 ? sum / length : nil
    }

    /// Gira el modelo para que la cara con normal `normal` mire hacia abajo (−Y) y lo apoya en la cama.
    func laidFlat(onFaceWithNormal normal: SIMD3<Float>) -> Mesh {
        rotated(by: Mesh.rotationAligning(normal, to: SIMD3<Float>(0, -1, 0))).recentered()
    }

    /// Rotación mínima que lleva la dirección `from` a la dirección `to`.
    static func rotationAligning(_ from: SIMD3<Float>, to: SIMD3<Float>) -> simd_quatf {
        let f = simd_normalize(from), t = simd_normalize(to)
        let d = simd_dot(f, t)
        if d > 0.999_999 { return simd_quatf(angle: 0, axis: SIMD3<Float>(1, 0, 0)) }
        if d < -0.999_999 {
            // Opuestos: media vuelta alrededor de cualquier eje perpendicular.
            let helper = abs(f.x) < 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 0, 1)
            return simd_quatf(angle: .pi, axis: simd_normalize(simd_cross(f, helper)))
        }
        return simd_quatf(angle: acos(Swift.min(1, Swift.max(-1, d))), axis: simd_normalize(simd_cross(f, t)))
    }
}
