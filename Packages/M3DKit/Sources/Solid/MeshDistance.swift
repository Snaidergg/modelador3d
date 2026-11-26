import Geometry
import simd

/// Distancia con signo de una malla, muestreada en una rejilla dispersa.
enum MeshDistance {
    /// Escribe en `field.values` la distancia a la malla (exacta hasta `band`, ±`band` más lejos).
    /// Los bloques deben estar ya reservados. El signo sale de contar cruces de rayos en los
    /// 3 ejes y votar, así que un agujero pequeño o un rayo que roza una arista no lo estropean.
    /// Con `unsigned` todo queda positivo (para dar grosor a superficies abiertas).
    static func fill(_ field: SparseField, from mesh: Mesh, band: Float, unsigned: Bool = false) {
        let band2 = band * band
        field.values.withUnsafeMutableBufferPointer { v in
            for i in v.indices { v[i] = band2 }
        }

        for t in mesh.triangles.indices {
            let (a, b, c) = mesh.corners(of: t)
            guard let range = field.pointRange(simd_min(a, simd_min(b, c)) - band,
                                               simd_max(a, simd_max(b, c)) + band) else { continue }
            field.values.withUnsafeMutableBufferPointer { v in
                field.forEachPoint(in: range) { idx, i, j, k in
                    let p = field.point(i, j, k)
                    let d = simd_length_squared(p - closestPoint(p, a, b, c))
                    if d < v[idx] { v[idx] = d }
                }
            }
        }

        if unsigned {
            field.values.withUnsafeMutableBufferPointer { v in
                for i in v.indices { v[i] = v[i].squareRoot() }
            }
            return
        }

        var votes = [UInt8](repeating: 0, count: field.pointCount)
        for axis in 0..<3 { addInsideVotes(mesh, field: field, axis: axis, votes: &votes) }
        field.values.withUnsafeMutableBufferPointer { v in
            for i in v.indices {
                let d = v[i].squareRoot()
                v[i] = votes[i] >= 2 ? -d : d
            }
        }
    }

    /// Lanza un rayo por cada columna de la rejilla a lo largo de `axis` y suma un voto a los puntos
    /// guardados que quedan tras un número impar de cruces con la malla (dentro).
    static func addInsideVotes(_ mesh: Mesh, field: SparseField, axis: Int, votes: inout [UInt8]) {
        let u = (axis + 1) % 3, v = (axis + 2) % 3
        let n = SIMD3<Int>(field.nx, field.ny, field.nz)
        let nu = n[u], nv = n[v]
        var columns: [Int: [Float]] = [:]

        for t in mesh.triangles.indices {
            let (pa, pb, pc) = mesh.corners(of: t)
            let a = field.gridCoordinates(pa), b = field.gridCoordinates(pb), c = field.gridCoordinates(pc)
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
                    columns[iu + iv * nu, default: []].append(w0 * a[axis] + w1 * b[axis] + w2 * c[axis])
                }
            }
        }
        for key in Array(columns.keys) { columns[key]?.sort() }

        for (s, brick) in field.brickCoords.enumerated() {
            let base = s * SparseField.brickPoints
            let origin = SIMD3<Int>(Int(brick.x) * 8, Int(brick.y) * 8, Int(brick.z) * 8)
            for lv in 0..<8 {
                let gv = origin[v] + lv
                if gv >= nv { continue }
                for lu in 0..<8 {
                    let gu = origin[u] + lu
                    if gu >= nu { continue }
                    guard let crossings = columns[gu + gv * nu] else { continue }
                    for la in 0..<8 {
                        let ga = origin[axis] + la
                        if lowerBound(crossings, Float(ga)) % 2 == 1 {
                            var l = SIMD3<Int>(0, 0, 0)
                            l[axis] = la
                            l[u] = lu
                            l[v] = lv
                            votes[base + SparseField.local(l.x, l.y, l.z)] += 1
                        }
                    }
                }
            }
        }
    }

    /// Cuántos elementos de `sorted` son menores que `x`.
    @inline(__always) static func lowerBound(_ sorted: [Float], _ x: Float) -> Int {
        var lo = 0, hi = sorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid] < x { lo = mid + 1 } else { hi = mid }
        }
        return lo
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
