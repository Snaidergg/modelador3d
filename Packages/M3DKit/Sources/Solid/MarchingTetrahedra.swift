import Geometry
import simd

/// Extrae la superficie f = 0 de una rejilla dispersa.
/// Cada celda se divide en 6 tetraedros que comparten la diagonal principal (subdivisión de Kuhn),
/// coherente entre celdas vecinas: el resultado es siempre una malla cerrada y sin aristas
/// compartidas por más de dos caras (a diferencia de los "marching cubes" clásicos).
enum MarchingTetrahedra {
    /// Esquinas de la celda: bit 0 = +X, bit 1 = +Y, bit 2 = +Z.
    private static let tetrahedra: [(Int, Int, Int, Int)] = [
        (0, 1, 3, 7), (0, 1, 5, 7), (0, 2, 3, 7),
        (0, 2, 6, 7), (0, 4, 5, 7), (0, 4, 6, 7),
    ]

    static func extract(_ field: SparseField) -> Mesh {
        var positions: [SIMD3<Float>] = []
        var triangles: [SIMD3<UInt32>] = []
        // Vértice ya creado en cada arista de la rejilla (clave: índice global del punto bajo · 8 + dirección).
        var edgeVertex: [Int: UInt32] = [:]
        let nx = field.nx, ny = field.ny, nz = field.nz
        let values = field.values

        @inline(__always) func global(_ i: Int, _ j: Int, _ k: Int) -> Int { (k * ny + j) * nx + i }

        for (s, brick) in field.brickCoords.enumerated() {
            let bx = Int(brick.x), by = Int(brick.y), bz = Int(brick.z)
            // Bloque propio y los 7 vecinos en +X/+Y/+Z (las celdas del borde los necesitan).
            var neighbor = [Int?](repeating: nil, count: 8)
            neighbor[0] = s
            for c in 1..<8 {
                neighbor[c] = field.slot(bx + (c & 1), by + ((c >> 1) & 1), bz + ((c >> 2) & 1))
            }

            for lk in 0..<8 {
                let k = bz * 8 + lk
                if k >= nz - 1 { break }
                for lj in 0..<8 {
                    let j = by * 8 + lj
                    if j >= ny - 1 { break }
                    for li in 0..<8 {
                        let i = bx * 8 + li
                        if i >= nx - 1 { break }

                        var f = SIMD8<Float>()
                        var missing = false
                        var insideCount = 0
                        for c in 0..<8 {
                            let ci = li + (c & 1), cj = lj + ((c >> 1) & 1), ck = lk + ((c >> 2) & 1)
                            let which = (ci >> 3) | ((cj >> 3) << 1) | ((ck >> 3) << 2)
                            guard let slot = neighbor[which] else { missing = true; break }
                            let value = values[slot * SparseField.brickPoints + SparseField.local(ci & 7, cj & 7, ck & 7)]
                            f[c] = value
                            if value < 0 { insideCount += 1 }
                        }
                        // Sin bloque vecino = lejos de toda superficie: aquí no hay cruce.
                        if missing || insideCount == 0 || insideCount == 8 { continue }

                        func p(_ c: Int) -> SIMD3<Float> {
                            field.point(i + (c & 1), j + ((c >> 1) & 1), k + ((c >> 2) & 1))
                        }
                        func vertex(_ a: Int, _ b: Int) -> UInt32 {
                            // En Kuhn, cada arista va de una esquina a otra que contiene sus bits.
                            let (low, high) = a < b ? (a, b) : (b, a)
                            let key = global(i + (low & 1), j + ((low >> 1) & 1), k + ((low >> 2) & 1)) &* 8 &+ (high ^ low)
                            if let existing = edgeVertex[key] { return existing }
                            let fl = f[low], fh = f[high]
                            let t = fl / (fl - fh)
                            let pl = p(low), ph = p(high)
                            let index = UInt32(positions.count)
                            positions.append(pl + (ph - pl) * t)
                            edgeVertex[key] = index
                            return index
                        }
                        func emit(_ a: UInt32, _ b: UInt32, _ c: UInt32, outward: SIMD3<Float>) {
                            let n = simd_cross(positions[Int(b)] - positions[Int(a)], positions[Int(c)] - positions[Int(a)])
                            triangles.append(simd_dot(n, outward) >= 0 ? SIMD3(a, b, c) : SIMD3(a, c, b))
                        }

                        for tet in tetrahedra {
                            let corners = [tet.0, tet.1, tet.2, tet.3]
                            let inside = corners.filter { f[$0] < 0 }
                            if inside.isEmpty || inside.count == 4 { continue }
                            let outside = corners.filter { f[$0] >= 0 }
                            // La normal debe apuntar de dentro hacia fuera.
                            var cin = SIMD3<Float>.zero, cout = SIMD3<Float>.zero
                            for c in inside { cin += p(c) }
                            for c in outside { cout += p(c) }
                            let outward = cout / Float(outside.count) - cin / Float(inside.count)

                            if inside.count == 1 || inside.count == 3 {
                                let lone = inside.count == 1 ? inside[0] : outside[0]
                                let others = inside.count == 1 ? outside : inside
                                emit(vertex(lone, others[0]), vertex(lone, others[1]), vertex(lone, others[2]), outward: outward)
                            } else {
                                let (a, b) = (inside[0], inside[1])
                                let (c, d) = (outside[0], outside[1])
                                let ac = vertex(a, c), ad = vertex(a, d), bd = vertex(b, d), bc = vertex(b, c)
                                emit(ac, ad, bd, outward: outward)
                                emit(ac, bd, bc, outward: outward)
                            }
                        }
                    }
                }
            }
        }
        return Mesh(positions: positions, triangles: triangles)
    }
}
