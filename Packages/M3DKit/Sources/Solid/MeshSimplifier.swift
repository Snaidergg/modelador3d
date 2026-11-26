import Geometry
import simd

/// Reduce el número de triángulos conservando la forma (método de Garland y Heckbert:
/// se colapsan primero las aristas cuya eliminación menos se nota).
/// Los bordes de mallas abiertas no se mueven y nunca se invierte la orientación de una cara.
public enum MeshSimplifier {
    public static func simplify(_ mesh: Mesh, targetTriangles: Int) -> Mesh {
        let target = Swift.max(targetTriangles, 8)
        guard mesh.triangleCount > target else { return mesh }

        var pos = mesh.positions
        var faces = mesh.triangles.map { SIMD3<Int32>(Int32($0.x), Int32($0.y), Int32($0.z)) }
        var faceAlive = [Bool](repeating: true, count: faces.count)
        var aliveFaces = faces.count
        var vertexFaces = [[Int32]](repeating: [], count: pos.count)
        var quadrics = [Quadric](repeating: Quadric(), count: pos.count)
        var version = [UInt32](repeating: 0, count: pos.count)
        var vertexAlive = [Bool](repeating: true, count: pos.count)

        // Adyacencia, cuádricas (ponderadas por área) y vértices de borde.
        var edgeUse: [Int: Int] = [:]
        @inline(__always) func edgeKey(_ a: Int32, _ b: Int32) -> Int {
            Int(Swift.min(a, b)) << 32 | Int(Swift.max(a, b))
        }
        for (f, t) in faces.enumerated() {
            let a = SIMD3<Double>(pos[Int(t.x)]), b = SIMD3<Double>(pos[Int(t.y)]), c = SIMD3<Double>(pos[Int(t.z)])
            let cr = simd_cross(b - a, c - a)
            let len = simd_length(cr)
            for v in [t.x, t.y, t.z] { vertexFaces[Int(v)].append(Int32(f)) }
            for (u, v) in [(t.x, t.y), (t.y, t.z), (t.z, t.x)] { edgeUse[edgeKey(u, v), default: 0] += 1 }
            guard len > 0 else { continue }
            let n = cr / len
            let q = Quadric(normal: n, d: -simd_dot(n, a), weight: len / 2)
            for v in [t.x, t.y, t.z] { quadrics[Int(v)] += q }
        }
        var locked = [Bool](repeating: false, count: pos.count)
        for (key, count) in edgeUse where count != 2 {
            locked[key >> 32] = true
            locked[key & 0xFFFF_FFFF] = true
        }

        func candidate(_ u: Int32, _ v: Int32) -> Candidate {
            let q = quadrics[Int(u)] + quadrics[Int(v)]
            let pu = SIMD3<Double>(pos[Int(u)]), pv = SIMD3<Double>(pos[Int(v)])
            let mid = (pu + pv) / 2
            var best = mid
            var cost = q.evaluate(mid)
            if let opt = q.optimum(), simd_distance(opt, mid) <= simd_distance(pu, pv) {
                let c = q.evaluate(opt)
                if c < cost { best = opt; cost = c }
            }
            for p in [pu, pv] {
                let c = q.evaluate(p)
                if c < cost { best = p; cost = c }
            }
            return Candidate(cost: Swift.max(cost, 0), u: u, v: v,
                             versionU: version[Int(u)], versionV: version[Int(v)],
                             position: SIMD3<Float>(best))
        }

        var heap = Heap()
        for t in faces {
            for (u, v) in [(t.x, t.y), (t.y, t.z), (t.z, t.x)] where u < v {
                if !locked[Int(u)] && !locked[Int(v)] { heap.push(candidate(u, v)) }
            }
        }

        var neighborsU = Set<Int32>(), neighborsV = Set<Int32>()
        while aliveFaces > target, let c = heap.pop() {
            let u = Int(c.u), v = Int(c.v)
            guard vertexAlive[u], vertexAlive[v],
                  version[u] == c.versionU, version[v] == c.versionV else { continue }

            // Condición de enlace: exactamente 2 vecinos comunes (si no, se crearían aristas no-manifold).
            neighborsU.removeAll(keepingCapacity: true)
            neighborsV.removeAll(keepingCapacity: true)
            for f in vertexFaces[u] where faceAlive[Int(f)] {
                let t = faces[Int(f)]
                for w in [t.x, t.y, t.z] where Int(w) != u { neighborsU.insert(w) }
            }
            for f in vertexFaces[v] where faceAlive[Int(f)] {
                let t = faces[Int(f)]
                for w in [t.x, t.y, t.z] where Int(w) != v { neighborsV.insert(w) }
            }
            guard neighborsU.contains(c.v), neighborsU.intersection(neighborsV).count == 2,
                  neighborsU.count > 2, neighborsV.count > 2 else { continue }

            // Ninguna cara puede darse la vuelta ni quedar aplastada.
            let p = c.position
            var flips = false
            for (moving, list) in [(u, vertexFaces[u]), (v, vertexFaces[v])] {
                for f in list where faceAlive[Int(f)] {
                    let t = faces[Int(f)]
                    let ids = [Int(t.x), Int(t.y), Int(t.z)]
                    if ids.contains(u) && ids.contains(v) { continue }
                    let old = ids.map { pos[$0] }
                    let new = ids.map { $0 == moving ? p : pos[$0] }
                    let n0 = simd_cross(old[1] - old[0], old[2] - old[0])
                    let n1 = simd_cross(new[1] - new[0], new[2] - new[0])
                    let l0 = simd_length(n0), l1 = simd_length(n1)
                    if l1 <= l0 * 1e-4 || simd_dot(n0, n1) < 0.2 * l0 * l1 { flips = true; break }
                }
                if flips { break }
            }
            if flips { continue }

            // Colapsar v en u.
            pos[u] = p
            quadrics[u] += quadrics[v]
            vertexAlive[v] = false
            version[u] &+= 1
            version[v] &+= 1
            for f in vertexFaces[v] where faceAlive[Int(f)] {
                var t = faces[Int(f)]
                if t.x == Int32(u) || t.y == Int32(u) || t.z == Int32(u) {
                    faceAlive[Int(f)] = false
                    aliveFaces -= 1
                } else {
                    if t.x == Int32(v) { t.x = Int32(u) }
                    if t.y == Int32(v) { t.y = Int32(u) }
                    if t.z == Int32(v) { t.z = Int32(u) }
                    faces[Int(f)] = t
                    vertexFaces[u].append(f)
                }
            }
            vertexFaces[v] = []
            vertexFaces[u].removeAll { !faceAlive[Int($0)] }

            var pushed = Set<Int32>()
            for f in vertexFaces[u] {
                let t = faces[Int(f)]
                for w in [t.x, t.y, t.z] where Int(w) != u && !locked[Int(w)] && pushed.insert(w).inserted {
                    heap.push(candidate(Int32(u), w))
                }
            }
        }

        var result = Mesh(positions: pos, triangles: [])
        result.triangles.reserveCapacity(aliveFaces)
        for (f, t) in faces.enumerated() where faceAlive[f] {
            result.triangles.append(SIMD3<UInt32>(UInt32(t.x), UInt32(t.y), UInt32(t.z)))
        }
        return result.compacted()
    }

    // MARK: Tipos auxiliares

    struct Quadric {
        var a2 = 0.0, ab = 0.0, ac = 0.0, ad = 0.0
        var b2 = 0.0, bc = 0.0, bd = 0.0
        var c2 = 0.0, cd = 0.0
        var d2 = 0.0

        init() {}

        init(normal n: SIMD3<Double>, d: Double, weight w: Double) {
            a2 = n.x * n.x * w; ab = n.x * n.y * w; ac = n.x * n.z * w; ad = n.x * d * w
            b2 = n.y * n.y * w; bc = n.y * n.z * w; bd = n.y * d * w
            c2 = n.z * n.z * w; cd = n.z * d * w
            d2 = d * d * w
        }

        static func + (l: Quadric, r: Quadric) -> Quadric {
            var q = l
            q += r
            return q
        }

        static func += (l: inout Quadric, r: Quadric) {
            l.a2 += r.a2; l.ab += r.ab; l.ac += r.ac; l.ad += r.ad
            l.b2 += r.b2; l.bc += r.bc; l.bd += r.bd
            l.c2 += r.c2; l.cd += r.cd
            l.d2 += r.d2
        }

        func evaluate(_ p: SIMD3<Double>) -> Double {
            let x: Double = p.x, y: Double = p.y, z: Double = p.z
            let rowX: Double = a2 * x + 2.0 * (ab * y + ac * z + ad)
            let rowY: Double = b2 * y + 2.0 * (bc * z + bd)
            let rowZ: Double = c2 * z + 2.0 * cd
            return x * rowX + y * rowY + z * rowZ + d2
        }

        /// Punto que minimiza el error, si el sistema no es casi singular (zonas planas o aristas rectas).
        func optimum() -> SIMD3<Double>? {
            let m = simd_double3x3(rows: [SIMD3(a2, ab, ac), SIMD3(ab, b2, bc), SIMD3(ac, bc, c2)])
            let det = m.determinant
            let scale = a2 + b2 + c2
            guard scale > 0, abs(det) > 1e-6 * scale * scale * scale else { return nil }
            return -(m.inverse * SIMD3(ad, bd, cd))
        }
    }

    struct Candidate {
        var cost: Double
        var u: Int32, v: Int32
        var versionU: UInt32, versionV: UInt32
        var position: SIMD3<Float>
    }

    /// Montículo binario de mínimos por coste.
    struct Heap {
        private var items: [Candidate] = []

        mutating func push(_ c: Candidate) {
            items.append(c)
            var i = items.count - 1
            while i > 0 {
                let parent = (i - 1) / 2
                if items[parent].cost <= items[i].cost { break }
                items.swapAt(parent, i)
                i = parent
            }
        }

        mutating func pop() -> Candidate? {
            guard !items.isEmpty else { return nil }
            let top = items[0]
            let last = items.removeLast()
            if !items.isEmpty {
                items[0] = last
                var i = 0
                while true {
                    let l = 2 * i + 1, r = l + 1
                    var smallest = i
                    if l < items.count && items[l].cost < items[smallest].cost { smallest = l }
                    if r < items.count && items[r].cost < items[smallest].cost { smallest = r }
                    if smallest == i { break }
                    items.swapAt(i, smallest)
                    i = smallest
                }
            }
            return top
        }
    }
}
