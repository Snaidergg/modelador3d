import simd

public extension Mesh {
    /// Tronco de cono alrededor del eje Y, centrado en el origen: radio `bottomRadius` abajo y
    /// `topRadius` arriba. Con radios iguales es un cilindro; con `topRadius` = 0, un cono.
    static func frustum(bottomRadius: Float, topRadius: Float, height: Float, segments: Int = 64) -> Mesh {
        let n = Swift.max(3, segments)
        let r1 = Swift.max(bottomRadius, 0), r2 = Swift.max(topRadius, 0)
        let y0 = -height / 2, y1 = height / 2
        var positions: [SIMD3<Float>] = [SIMD3<Float>(0, y0, 0)]
        func ring(_ r: Float, _ y: Float) {
            for i in 0..<n {
                let a = Float(i) / Float(n) * 2 * .pi
                positions.append(SIMD3<Float>(r * cos(a), y, r * sin(a)))
            }
        }
        ring(r1, y0)
        let bottom = { (i: Int) -> UInt32 in UInt32(1 + i % n) }
        var triangles: [SIMD3<UInt32>] = []

        for i in 0..<n {
            triangles.append(SIMD3(0, bottom(i), bottom(i + 1)))
        }
        if r2 > 0 {
            ring(r2, y1)
            let top = { (i: Int) -> UInt32 in UInt32(1 + n + i % n) }
            let topCenter = UInt32(positions.count)
            positions.append(SIMD3<Float>(0, y1, 0))
            for i in 0..<n {
                triangles.append(SIMD3(bottom(i), bottom(i + 1), top(i + 1)))
                triangles.append(SIMD3(bottom(i), top(i + 1), top(i)))
                triangles.append(SIMD3(topCenter, top(i), top(i + 1)))
            }
        } else {
            let apex = UInt32(positions.count)
            positions.append(SIMD3<Float>(0, y1, 0))
            for i in 0..<n {
                triangles.append(SIMD3(bottom(i), bottom(i + 1), apex))
            }
        }
        return Mesh(positions: positions, triangles: triangles).orientedOutwardConvex()
    }

    static func cylinder(radius: Float, height: Float, segments: Int = 64) -> Mesh {
        frustum(bottomRadius: radius, topRadius: radius, height: height, segments: segments)
    }
}
