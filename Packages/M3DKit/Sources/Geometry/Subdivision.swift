import simd

extension Mesh {
    /// Divide cada triángulo en 4 (punto medio de cada arista). Conserva la forma y la orientación,
    /// y multiplica por 4 la cantidad de triángulos: más detalle disponible para esculpir.
    public func subdivided() -> Mesh {
        struct EdgeKey: Hashable { let a: UInt32, b: UInt32 }

        var newPositions = positions
        newPositions.reserveCapacity(positions.count + triangles.count * 3 / 2)
        var cache: [EdgeKey: UInt32] = [:]
        cache.reserveCapacity(triangles.count * 3 / 2)

        func midpoint(_ i: UInt32, _ j: UInt32) -> UInt32 {
            let key = i < j ? EdgeKey(a: i, b: j) : EdgeKey(a: j, b: i)
            if let existing = cache[key] { return existing }
            let index = UInt32(newPositions.count)
            newPositions.append((positions[Int(i)] + positions[Int(j)]) * 0.5)
            cache[key] = index
            return index
        }

        var newTriangles: [SIMD3<UInt32>] = []
        newTriangles.reserveCapacity(triangles.count * 4)
        for t in triangles {
            let a = t.x, b = t.y, c = t.z
            let ab = midpoint(a, b)
            let bc = midpoint(b, c)
            let ca = midpoint(c, a)
            newTriangles.append(SIMD3(a, ab, ca))
            newTriangles.append(SIMD3(b, bc, ab))
            newTriangles.append(SIMD3(c, ca, bc))
            newTriangles.append(SIMD3(ab, bc, ca))
        }
        return Mesh(positions: newPositions, triangles: newTriangles)
    }

    /// Esfera geodésica: triángulos casi iguales en toda la superficie (sin polos),
    /// la mejor base para esculpir. Triángulos = 20 × 4^subdivisions.
    public static func icosphere(radius: Float, subdivisions: Int) -> Mesh {
        let t: Float = (1 + Float(5).squareRoot()) / 2
        let raw: [SIMD3<Float>] = [
            SIMD3(-1, t, 0), SIMD3(1, t, 0), SIMD3(-1, -t, 0), SIMD3(1, -t, 0),
            SIMD3(0, -1, t), SIMD3(0, 1, t), SIMD3(0, -1, -t), SIMD3(0, 1, -t),
            SIMD3(t, 0, -1), SIMD3(t, 0, 1), SIMD3(-t, 0, -1), SIMD3(-t, 0, 1),
        ]
        let faces: [SIMD3<UInt32>] = [
            SIMD3(0, 11, 5), SIMD3(0, 5, 1), SIMD3(0, 1, 7), SIMD3(0, 7, 10), SIMD3(0, 10, 11),
            SIMD3(1, 5, 9), SIMD3(5, 11, 4), SIMD3(11, 10, 2), SIMD3(10, 7, 6), SIMD3(7, 1, 8),
            SIMD3(3, 9, 4), SIMD3(3, 4, 2), SIMD3(3, 2, 6), SIMD3(3, 6, 8), SIMD3(3, 8, 9),
            SIMD3(4, 9, 5), SIMD3(2, 4, 11), SIMD3(6, 2, 10), SIMD3(8, 6, 7), SIMD3(9, 8, 1),
        ]
        var mesh = Mesh(positions: raw.map { simd_normalize($0) * radius }, triangles: faces)
            .orientedOutwardConvex()
        for _ in 0..<Swift.max(0, subdivisions) {
            mesh = mesh.subdivided()
            mesh.positions = mesh.positions.map { simd_normalize($0) * radius }
        }
        return mesh
    }
}
