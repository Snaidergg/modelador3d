import simd

extension Mesh {
    /// Esfera UV cerrada (estanca), con normales hacia afuera.
    public static func uvSphere(radius: Float, segments: Int = 48, rings: Int = 24) -> Mesh {
        let segments = Swift.max(segments, 3)
        let rings = Swift.max(rings, 2)
        var positions: [SIMD3<Float>] = [SIMD3<Float>(0, radius, 0)]

        for i in 1..<rings {
            let phi = Float.pi * Float(i) / Float(rings)
            let y = radius * cos(phi)
            let ringRadius = radius * sin(phi)
            for j in 0..<segments {
                let theta = 2 * Float.pi * Float(j) / Float(segments)
                positions.append(SIMD3<Float>(ringRadius * cos(theta), y, ringRadius * sin(theta)))
            }
        }
        positions.append(SIMD3<Float>(0, -radius, 0))

        let north: UInt32 = 0
        let south = UInt32(positions.count - 1)
        func idx(_ ring: Int, _ seg: Int) -> UInt32 {
            UInt32(1 + (ring - 1) * segments + (seg % segments))
        }

        var triangles: [SIMD3<UInt32>] = []
        for j in 0..<segments {
            triangles.append(SIMD3(north, idx(1, j + 1), idx(1, j)))
        }
        if rings > 2 {
            for i in 1..<(rings - 1) {
                for j in 0..<segments {
                    let a = idx(i, j), b = idx(i, j + 1)
                    let c = idx(i + 1, j), d = idx(i + 1, j + 1)
                    triangles.append(SIMD3(a, d, c))
                    triangles.append(SIMD3(a, b, d))
                }
            }
        }
        for j in 0..<segments {
            triangles.append(SIMD3(idx(rings - 1, j), idx(rings - 1, j + 1), south))
        }
        return Mesh(positions: positions, triangles: triangles)
    }

    /// Caja centrada en el origen.
    public static func box(size: SIMD3<Float>) -> Mesh {
        var positions: [SIMD3<Float>] = []
        for i in 0..<8 {
            let x: Float = (i & 1) == 0 ? -0.5 : 0.5
            let y: Float = (i & 2) == 0 ? -0.5 : 0.5
            let z: Float = (i & 4) == 0 ? -0.5 : 0.5
            positions.append(SIMD3<Float>(x, y, z) * size)
        }
        let quads: [[UInt32]] = [
            [0, 1, 3, 2], [4, 5, 7, 6],   // -Z, +Z
            [0, 1, 5, 4], [2, 3, 7, 6],   // -Y, +Y
            [0, 2, 6, 4], [1, 3, 7, 5],   // -X, +X
        ]
        var triangles: [SIMD3<UInt32>] = []
        for q in quads {
            triangles.append(SIMD3(q[0], q[1], q[2]))
            triangles.append(SIMD3(q[0], q[2], q[3]))
        }
        return Mesh(positions: positions, triangles: triangles).orientedOutwardConvex()
    }

    /// Orienta cada triángulo hacia afuera respecto al centro. Solo válido para formas convexas.
    func orientedOutwardConvex() -> Mesh {
        let center = bounds.center
        var m = self
        for t in triangles.indices {
            let (a, b, c) = corners(of: t)
            let n = simd_cross(b - a, c - a)
            let centroid = (a + b + c) / 3
            if simd_dot(n, centroid - center) < 0 {
                let tri = m.triangles[t]
                m.triangles[t] = SIMD3(tri.x, tri.z, tri.y)
            }
        }
        return m
    }
}
