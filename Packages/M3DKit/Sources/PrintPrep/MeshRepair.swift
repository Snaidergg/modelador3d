import Geometry
import simd

/// Herramientas para dejar una captura lista para imprimir.
public enum MeshRepair {
    private struct EdgeKey: Hashable {
        let a: UInt32, b: UInt32
        init(_ u: UInt32, _ v: UInt32) {
            a = Swift.min(u, v)
            b = Swift.max(u, v)
        }
    }

    // MARK: Recortar con un plano horizontal

    /// Corta el modelo con el plano Y = `planeY` y conserva la parte de arriba o la de abajo.
    /// Los triángulos que cruzan el plano se dividen, así el borde del corte queda exacto.
    public static func cut(_ mesh: Mesh, planeY: Float, keepAbove: Bool) -> Mesh {
        let sign: Float = keepAbove ? 1 : -1
        let distance = mesh.positions.map { ($0.y - planeY) * sign }
        var positions = mesh.positions
        var triangles: [SIMD3<UInt32>] = []
        triangles.reserveCapacity(mesh.triangleCount)
        var cache: [EdgeKey: UInt32] = [:]

        /// Punto donde la arista (dentro → fuera) cruza el plano.
        func crossing(_ inside: UInt32, _ outside: UInt32) -> UInt32 {
            let di = distance[Int(inside)]
            if di == 0 { return inside }
            let key = EdgeKey(inside, outside)
            if let existing = cache[key] { return existing }
            let t = di / (di - distance[Int(outside)])
            var p = positions[Int(inside)] + (positions[Int(outside)] - positions[Int(inside)]) * t
            p.y = planeY
            let index = UInt32(positions.count)
            positions.append(p)
            cache[key] = index
            return index
        }

        func add(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
            if a != b, b != c, a != c { triangles.append(SIMD3<UInt32>(a, b, c)) }
        }

        for tri in mesh.triangles {
            let v = [tri.x, tri.y, tri.z]
            let inside = v.map { distance[Int($0)] >= 0 }
            switch inside.filter({ $0 }).count {
            case 3:
                triangles.append(tri)
            case 1:
                let k = inside.firstIndex(of: true)!
                let a = v[k], b = v[(k + 1) % 3], c = v[(k + 2) % 3]
                add(a, crossing(a, b), crossing(a, c))
            case 2:
                let k = inside.firstIndex(of: false)!
                let c = v[k], a = v[(k + 1) % 3], b = v[(k + 2) % 3]
                let cb = crossing(b, c)
                let ca = crossing(a, c)
                add(a, b, cb)
                add(a, cb, ca)
            default:
                break
            }
        }
        return Mesh(positions: positions, triangles: triangles).compacted()
    }

    // MARK: Cerrar agujeros

    /// Contornos de los agujeros, en el sentido de las aristas de borde.
    static func boundaryLoops(_ mesh: Mesh) -> [[UInt32]] {
        var uses: [EdgeKey: Int] = [:]
        for t in mesh.triangles {
            uses[EdgeKey(t.x, t.y), default: 0] += 1
            uses[EdgeKey(t.y, t.z), default: 0] += 1
            uses[EdgeKey(t.z, t.x), default: 0] += 1
        }
        var outgoing: [UInt32: [UInt32]] = [:]
        var boundary: [(UInt32, UInt32)] = []
        for t in mesh.triangles {
            for (u, v) in [(t.x, t.y), (t.y, t.z), (t.z, t.x)] where uses[EdgeKey(u, v)] == 1 {
                boundary.append((u, v))
                outgoing[u, default: []].append(v)
            }
        }

        struct Directed: Hashable { let u: UInt32, v: UInt32 }
        var used = Set<Directed>()
        var loops: [[UInt32]] = []
        for (start, firstNext) in boundary where !used.contains(Directed(u: start, v: firstNext)) {
            used.insert(Directed(u: start, v: firstNext))
            var loop = [start]
            var current = firstNext
            var steps = 0
            var closed = false
            while steps <= boundary.count {
                if current == start { closed = true; break }
                loop.append(current)
                guard let next = outgoing[current]?.first(where: { !used.contains(Directed(u: current, v: $0)) }) else { break }
                used.insert(Directed(u: current, v: next))
                current = next
                steps += 1
            }
            if closed, loop.count >= 3 { loops.append(loop) }
        }
        return loops
    }

    /// Tapa todos los agujeros. Cada tapa se triangula con "recorte de orejas" sobre su plano medio,
    /// lo que respeta contornos cóncavos (como la base de una figura).
    public static func fillHoles(_ mesh: Mesh) -> Mesh {
        var result = mesh
        for loop in boundaryLoops(mesh) {
            // La tapa debe recorrer las aristas en sentido contrario al borde existente.
            let polygon = Array(loop.reversed())
            if let caps = earClip(polygon, positions: result.positions) {
                result.triangles.append(contentsOf: caps)
            } else {
                // Alternativa: abanico desde el centro del agujero.
                var center = SIMD3<Float>.zero
                for i in polygon { center += result.positions[Int(i)] }
                center /= Float(polygon.count)
                let c = UInt32(result.positions.count)
                result.positions.append(center)
                for i in polygon.indices {
                    result.triangles.append(SIMD3<UInt32>(polygon[i], polygon[(i + 1) % polygon.count], c))
                }
            }
        }
        return result
    }

    static func earClip(_ polygon: [UInt32], positions: [SIMD3<Float>]) -> [SIMD3<UInt32>]? {
        let n = polygon.count
        guard n >= 3 else { return nil }
        if n == 3 { return [SIMD3<UInt32>(polygon[0], polygon[1], polygon[2])] }

        // Normal de Newell: perpendicular al plano medio, orientada según el sentido del contorno.
        var normal = SIMD3<Float>.zero
        for i in 0..<n {
            let p = positions[Int(polygon[i])], q = positions[Int(polygon[(i + 1) % n])]
            normal.x += (p.y - q.y) * (p.z + q.z)
            normal.y += (p.z - q.z) * (p.x + q.x)
            normal.z += (p.x - q.x) * (p.y + q.y)
        }
        guard simd_length(normal) > 0 else { return nil }
        normal = simd_normalize(normal)
        let helper = abs(normal.x) < 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
        let u = simd_normalize(simd_cross(normal, helper))
        let v = simd_cross(normal, u)
        let points = polygon.map { i -> SIMD2<Float> in
            let p = positions[Int(i)]
            return SIMD2<Float>(simd_dot(p, u), simd_dot(p, v))
        }

        func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.y - a.y * b.x }
        func strictlyInside(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Bool {
            cross(b - a, p - a) > 0 && cross(c - b, p - b) > 0 && cross(a - c, p - c) > 0
        }

        var remaining = Array(0..<n)
        var result: [SIMD3<UInt32>] = []
        result.reserveCapacity(n - 2)
        var attempts = 0
        while remaining.count > 3 {
            attempts += 1
            if attempts > n * 4 { return nil }
            let m = remaining.count
            var clipped = false
            for k in 0..<m {
                let i0 = remaining[(k + m - 1) % m], i1 = remaining[k], i2 = remaining[(k + 1) % m]
                let a = points[i0], b = points[i1], c = points[i2]
                if cross(b - a, c - b) <= 0 { continue } // vértice cóncavo o alineado
                var blocked = false
                for j in remaining where j != i0 && j != i1 && j != i2 {
                    if strictlyInside(points[j], a, b, c) { blocked = true; break }
                }
                if blocked { continue }
                result.append(SIMD3<UInt32>(polygon[i0], polygon[i1], polygon[i2]))
                remaining.remove(at: k)
                clipped = true
                break
            }
            if !clipped { return nil }
        }
        result.append(SIMD3<UInt32>(polygon[remaining[0]], polygon[remaining[1]], polygon[remaining[2]]))
        return result
    }

    // MARK: Quitar piezas sueltas

    /// Elimina las piezas desconectadas que tengan menos de `minFraction` de los triángulos de la pieza mayor.
    public static func removeSmallPieces(_ mesh: Mesh, minFraction: Float = 0.1) -> Mesh {
        guard !mesh.isEmpty else { return mesh }
        var parent = Array(0..<mesh.vertexCount)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }
        func union(_ a: UInt32, _ b: UInt32) {
            let ra = find(Int(a)), rb = find(Int(b))
            if ra != rb { parent[ra] = rb }
        }
        for t in mesh.triangles {
            union(t.x, t.y)
            union(t.y, t.z)
        }

        var sizes: [Int: Int] = [:]
        let roots = mesh.triangles.map { find(Int($0.x)) }
        for r in roots { sizes[r, default: 0] += 1 }
        let largest = sizes.values.max() ?? 0
        let threshold = Int((Float(largest) * minFraction).rounded(.up))

        var kept = Mesh(positions: mesh.positions, triangles: [])
        for (t, root) in zip(mesh.triangles, roots) where sizes[root, default: 0] >= threshold {
            kept.triangles.append(t)
        }
        return kept.compacted()
    }

    /// Número de piezas desconectadas.
    public static func pieceCount(_ mesh: Mesh) -> Int {
        guard !mesh.isEmpty else { return 0 }
        var parent = Array(0..<mesh.vertexCount)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }
        for t in mesh.triangles {
            for (a, b) in [(t.x, t.y), (t.y, t.z)] {
                let ra = find(Int(a)), rb = find(Int(b))
                if ra != rb { parent[ra] = rb }
            }
        }
        return Set(mesh.triangles.map { find(Int($0.x)) }).count
    }
}
