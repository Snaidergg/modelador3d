import Geometry
import simd

/// Rejilla regular de muestras: el punto (i, j, k) está en `origin + (i, j, k) · spacing`.
struct VoxelGrid {
    let origin: SIMD3<Float>
    let spacing: Float
    let nx: Int, ny: Int, nz: Int

    var count: Int { nx * ny * nz }
    var dims: SIMD3<Int> { SIMD3(nx, ny, nz) }

    @inline(__always) func index(_ i: Int, _ j: Int, _ k: Int) -> Int { (k * ny + j) * nx + i }

    @inline(__always) func point(_ i: Int, _ j: Int, _ k: Int) -> SIMD3<Float> {
        origin + SIMD3<Float>(Float(i), Float(j), Float(k)) * spacing
    }

    /// Rejilla que cubre `bounds` con `padding` celdas de margen y celdas de lado `spacing`.
    /// El origen se desplaza una fracción "irracional" de celda (distinta para cada malla) para que
    /// los rayos de la prueba dentro/fuera casi nunca pasen justo por un vértice o una arista.
    init(covering bounds: BoundingBox, spacing: Float, padding: Int = 3, jitterSeed: Int = 0) {
        let seed = Float(jitterSeed % 9973)
        let golden: Float = 0.618_034
        let jitter = SIMD3<Float>(
            (seed * golden + 0.137).truncatingRemainder(dividingBy: 1),
            (seed * golden * 1.414 + 0.371).truncatingRemainder(dividingBy: 1),
            (seed * golden * 1.732 + 0.719).truncatingRemainder(dividingBy: 1)
        ) * 0.5 + 0.25
        let pad = Float(padding) * spacing
        origin = bounds.min - pad - jitter * spacing
        let extent = bounds.max + pad - origin
        nx = Int((extent.x / spacing).rounded(.up)) + 1
        ny = Int((extent.y / spacing).rounded(.up)) + 1
        nz = Int((extent.z / spacing).rounded(.up)) + 1
        self.spacing = spacing
    }
}

/// Distancia con signo de una malla muestreada en una rejilla.
enum MeshDistance {
    /// Distancia exacta cerca de la superficie (hasta `band` mm) y ±`band` más lejos.
    /// El signo (dentro/fuera) sale de contar cruces de rayos en los 3 ejes y votar:
    /// así un agujero pequeño o un rayo que roza una arista no estropean el resultado.
    /// Con `unsigned` todo se devuelve positivo (para dar grosor a superficies abiertas).
    static func sample(_ mesh: Mesh, on grid: VoxelGrid, band: Float, unsigned: Bool = false) -> [Float] {
        var dist2 = [Float](repeating: band * band, count: grid.count)
        let h = grid.spacing
        let n = grid.dims

        dist2.withUnsafeMutableBufferPointer { d in
            for t in mesh.triangles.indices {
                let (a, b, c) = mesh.corners(of: t)
                let lo = (simd_min(a, simd_min(b, c)) - band - grid.origin) / h
                let hi = (simd_max(a, simd_max(b, c)) + band - grid.origin) / h
                let i0 = Swift.max(0, Int(lo.x.rounded(.up))), i1 = Swift.min(n.x - 1, Int(hi.x.rounded(.down)))
                let j0 = Swift.max(0, Int(lo.y.rounded(.up))), j1 = Swift.min(n.y - 1, Int(hi.y.rounded(.down)))
                let k0 = Swift.max(0, Int(lo.z.rounded(.up))), k1 = Swift.min(n.z - 1, Int(hi.z.rounded(.down)))
                if i0 > i1 || j0 > j1 || k0 > k1 { continue }
                for k in k0...k1 {
                    for j in j0...j1 {
                        for i in i0...i1 {
                            let p = grid.point(i, j, k)
                            let q = closestPoint(p, a, b, c)
                            let dd = simd_length_squared(p - q)
                            let idx = grid.index(i, j, k)
                            if dd < d[idx] { d[idx] = dd }
                        }
                    }
                }
            }
        }

        if unsigned { return dist2.map { $0.squareRoot() } }

        var votes = [UInt8](repeating: 0, count: grid.count)
        for axis in 0..<3 { addInsideVotes(mesh, grid: grid, axis: axis, votes: &votes) }
        var result = [Float](repeating: 0, count: grid.count)
        for i in result.indices {
            let d = dist2[i].squareRoot()
            result[i] = votes[i] >= 2 ? -d : d
        }
        return result
    }

    /// Lanza un rayo por cada columna de la rejilla a lo largo de `axis` y marca los puntos que
    /// quedan tras un número impar de cruces con la malla (dentro).
    static func addInsideVotes(_ mesh: Mesh, grid: VoxelGrid, axis: Int, votes: inout [UInt8]) {
        let u = (axis + 1) % 3, v = (axis + 2) % 3
        let n = grid.dims
        let nu = n[u], nv = n[v], na = n[axis]
        var hits: [(column: Int, along: Float)] = []
        hits.reserveCapacity(mesh.triangleCount * 2)

        for t in mesh.triangles.indices {
            let (pa, pb, pc) = mesh.corners(of: t)
            let a = (pa - grid.origin) / grid.spacing
            let b = (pb - grid.origin) / grid.spacing
            let c = (pc - grid.origin) / grid.spacing
            let a2 = SIMD2<Float>(a[u], a[v]), b2 = SIMD2<Float>(b[u], b[v]), c2 = SIMD2<Float>(c[u], c[v])
            let area = cross2(b2 - a2, c2 - a2)
            if area == 0 { continue }
            let lo = simd_min(a2, simd_min(b2, c2)), hi = simd_max(a2, simd_max(b2, c2))
            let iu0 = Swift.max(0, Int(lo.x.rounded(.up))), iu1 = Swift.min(nu - 1, Int(hi.x.rounded(.down)))
            let iv0 = Swift.max(0, Int(lo.y.rounded(.up))), iv1 = Swift.min(nv - 1, Int(hi.y.rounded(.down)))
            if iu0 > iu1 || iv0 > iv1 { continue }
            for iv in iv0...iv1 {
                for iu in iu0...iu1 {
                    let p = SIMD2<Float>(Float(iu), Float(iv))
                    let w0 = cross2(b2 - p, c2 - p) / area
                    let w1 = cross2(c2 - p, a2 - p) / area
                    let w2 = 1 - w0 - w1
                    if w0 < 0 || w1 < 0 || w2 < 0 { continue }
                    hits.append((iu + iv * nu, w0 * a[axis] + w1 * b[axis] + w2 * c[axis]))
                }
            }
        }

        hits.sort { $0.column != $1.column ? $0.column < $1.column : $0.along < $1.along }

        var start = 0
        while start < hits.count {
            let column = hits[start].column
            var end = start
            while end < hits.count && hits[end].column == column { end += 1 }
            let iu = column % nu, iv = column / nu
            var crossed = 0
            var next = start
            for ia in 0..<na {
                while next < end && hits[next].along < Float(ia) {
                    crossed += 1
                    next += 1
                }
                if crossed % 2 == 1 {
                    var idx = SIMD3<Int>(0, 0, 0)
                    idx[axis] = ia
                    idx[u] = iu
                    idx[v] = iv
                    votes[grid.index(idx.x, idx.y, idx.z)] += 1
                }
            }
            start = end
        }
        _ = nv
    }

    @inline(__always) static func cross2(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.y - a.y * b.x }

    /// Punto del triángulo abc más cercano a p (Ericson, "Real-Time Collision Detection").
    @inline(__always)
    static func closestPoint(_ p: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> SIMD3<Float> {
        let ab = b - a, ac = c - a, ap = p - a
        let d1 = simd_dot(ab, ap), d2 = simd_dot(ac, ap)
        if d1 <= 0 && d2 <= 0 { return a }
        let bp = p - b
        let d3 = simd_dot(ab, bp), d4 = simd_dot(ac, bp)
        if d3 >= 0 && d4 <= d3 { return b }
        let vc = d1 * d4 - d3 * d2
        if vc <= 0 && d1 >= 0 && d3 <= 0 { return a + ab * (d1 / (d1 - d3)) }
        let cp = p - c
        let d5 = simd_dot(ab, cp), d6 = simd_dot(ac, cp)
        if d6 >= 0 && d5 <= d6 { return c }
        let vb = d5 * d2 - d1 * d6
        if vb <= 0 && d2 >= 0 && d6 <= 0 { return a + ac * (d2 / (d2 - d6)) }
        let va = d3 * d6 - d5 * d4
        if va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0 {
            return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
        }
        let sum = va + vb + vc
        guard sum != 0 else { return a }
        return a + ab * (vb / sum) + ac * (vc / sum)
    }
}
