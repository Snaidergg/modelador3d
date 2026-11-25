import simd

/// Malla de triángulos indexada. Unidad interna: milímetros. Eje vertical: +Y.
public struct Mesh: Equatable, Sendable {
    public var positions: [SIMD3<Float>]
    public var triangles: [SIMD3<UInt32>]

    public init(positions: [SIMD3<Float>] = [], triangles: [SIMD3<UInt32>] = []) {
        self.positions = positions
        self.triangles = triangles
    }

    public var vertexCount: Int { positions.count }
    public var triangleCount: Int { triangles.count }
    public var isEmpty: Bool { triangles.isEmpty }

    public func corners(of t: Int) -> (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        let tri = triangles[t]
        return (positions[Int(tri.x)], positions[Int(tri.y)], positions[Int(tri.z)])
    }

    /// Normal unitaria de un triángulo (regla de la mano derecha, orden antihorario = cara exterior).
    public func faceNormal(_ t: Int) -> SIMD3<Float> {
        let (a, b, c) = corners(of: t)
        let n = simd_cross(b - a, c - a)
        let len = simd_length(n)
        return len > 0 ? n / len : SIMD3<Float>(0, 1, 0)
    }

    /// Normales por vértice ponderadas por área (sombreado suave).
    public func vertexNormals() -> [SIMD3<Float>] {
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        for t in triangles.indices {
            let tri = triangles[t]
            let (a, b, c) = corners(of: t)
            let n = simd_cross(b - a, c - a)
            normals[Int(tri.x)] += n
            normals[Int(tri.y)] += n
            normals[Int(tri.z)] += n
        }
        return normals.map { n in
            let len = simd_length(n)
            return len > 0 ? n / len : SIMD3<Float>(0, 1, 0)
        }
    }

    public var bounds: BoundingBox { BoundingBox(points: positions) }

    // MARK: Transformaciones

    public func translated(by offset: SIMD3<Float>) -> Mesh {
        var m = self
        m.positions = positions.map { $0 + offset }
        return m
    }

    public func scaled(by factor: SIMD3<Float>) -> Mesh {
        var m = self
        m.positions = positions.map { $0 * factor }
        // Una escala con número impar de ejes negativos invierte la orientación.
        let negatives = (factor.x < 0 ? 1 : 0) + (factor.y < 0 ? 1 : 0) + (factor.z < 0 ? 1 : 0)
        if negatives % 2 == 1 { m.flipWinding() }
        return m
    }

    public func scaled(by factor: Float) -> Mesh {
        scaled(by: SIMD3<Float>(repeating: factor))
    }

    /// Gira el modelo alrededor del origen.
    public func rotated(degrees: Float, axis: SIMD3<Float>) -> Mesh {
        let q = simd_quatf(angle: degrees * .pi / 180, axis: simd_normalize(axis))
        var m = self
        m.positions = positions.map { q.act($0) }
        return m
    }

    /// Centra el modelo en X/Z y lo apoya sobre la cama de impresión (Y mínimo = 0).
    public func recentered() -> Mesh {
        guard !positions.isEmpty else { return self }
        let b = bounds
        return translated(by: SIMD3<Float>(-b.center.x, -b.min.y, -b.center.z))
    }

    /// Invierte el sentido de todos los triángulos (voltea normales).
    public mutating func flipWinding() {
        triangles = triangles.map { SIMD3<UInt32>($0.x, $0.z, $0.y) }
    }

    public func flipped() -> Mesh {
        var m = self
        m.flipWinding()
        return m
    }

    /// Une vértices duplicados que estén a menos de `tolerance` mm y elimina triángulos degenerados.
    /// Imprescindible tras importar STL, donde cada triángulo trae sus propios vértices.
    public func welded(tolerance: Float = 1e-4) -> Mesh {
        struct Key: Hashable { let x: Int64, y: Int64, z: Int64 }
        let inv = 1 / max(tolerance, Float.leastNormalMagnitude)
        func quantize(_ v: Float) -> Int64 {
            let r = (v * inv).rounded()
            guard r.isFinite, abs(r) < 9e18 else { return 0 }
            return Int64(r)
        }

        var lookup: [Key: UInt32] = [:]
        lookup.reserveCapacity(positions.count)
        var newPositions: [SIMD3<Float>] = []
        var remap = [UInt32](repeating: 0, count: positions.count)

        for (i, p) in positions.enumerated() {
            let key = Key(x: quantize(p.x), y: quantize(p.y), z: quantize(p.z))
            if let existing = lookup[key] {
                remap[i] = existing
            } else {
                let index = UInt32(newPositions.count)
                lookup[key] = index
                newPositions.append(p)
                remap[i] = index
            }
        }

        var newTriangles: [SIMD3<UInt32>] = []
        newTriangles.reserveCapacity(triangles.count)
        for t in triangles {
            let a = remap[Int(t.x)], b = remap[Int(t.y)], c = remap[Int(t.z)]
            if a != b, b != c, a != c {
                newTriangles.append(SIMD3<UInt32>(a, b, c))
            }
        }
        return Mesh(positions: newPositions, triangles: newTriangles)
    }
}
