import simd

/// Caja envolvente alineada a los ejes.
public struct BoundingBox: Equatable, Sendable {
    public var min: SIMD3<Float>
    public var max: SIMD3<Float>

    public init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.min = min
        self.max = max
    }

    public init(points: [SIMD3<Float>]) {
        guard let first = points.first else {
            self.min = .zero
            self.max = .zero
            return
        }
        var lo = first, hi = first
        for p in points {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        self.min = lo
        self.max = hi
    }

    public var size: SIMD3<Float> { max - min }
    public var center: SIMD3<Float> { (min + max) * 0.5 }
    /// Radio de la esfera que contiene la caja.
    public var radius: Float { simd_length(size) * 0.5 }
}
