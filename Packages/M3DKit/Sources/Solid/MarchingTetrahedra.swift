import Geometry
import simd

/// Extrae la superficie f = 0 de una rejilla de distancias.
/// Cada celda se divide en 6 tetraedros que comparten la diagonal principal (subdivisión de Kuhn),
/// coherente entre celdas vecinas: el resultado es siempre una malla cerrada y sin aristas
/// compartidas por más de dos caras (a diferencia de los "marching cubes" clásicos).
enum MarchingTetrahedra {
    /// Esquinas de la celda: bit 0 = +X, bit 1 = +Y, bit 2 = +Z.
    private static let tetrahedra: [(Int, Int, Int, Int)] = [
        (0, 1, 3, 7), (0, 1, 5, 7), (0, 2, 3, 7),
        (0, 2, 6, 7), (0, 4, 5, 7), (0, 4, 6, 7),
    ]

    static func extract(_ values: [Float], grid: VoxelGrid) -> Mesh {
        var positions: [SIMD3<Float>] = []
        var triangles: [SIMD3<UInt32>] = []
        // Vértice ya creado en cada arista de la rejilla (clave: punto bajo · 8 + dirección).
        var edgeVertex: [Int: UInt32] = [:]

        let nx = grid.nx, ny = grid.ny, nz = grid.nz
        let cornerOffsets: [Int] = (0..<8).map { c in
            grid.index(c & 1, (c >> 1) & 1, (c >> 2) & 1)
        }

        func vertex(_ ga: Int, _ ca: Int, _ gb: Int, _ cb: Int, base: SIMD3<Int>) -> UInt32 {
            // La arista va de la esquina con menos bits a la que tiene más (siempre es así en Kuhn).
            let (lowG, lowC, highG, highC) = ca < cb ? (ga, ca, gb, cb) : (gb, cb, ga, ca)
            let key = lowG &* 8 &+ (highC ^ lowC)
            if let existing = edgeVertex[key] { return existing }
            let fl = values[lowG], fh = values[highG]
            let t = fl / (fl - fh)
            let pl = grid.point(base.x + (lowC & 1), base.y + ((lowC >> 1) & 1), base.z + ((lowC >> 2) & 1))
            let ph = grid.point(base.x + (highC & 1), base.y + ((highC >> 1) & 1), base.z + ((highC >> 2) & 1))
            let index = UInt32(positions.count)
            positions.append(pl + (ph - pl) * t)
            edgeVertex[key] = index
            return index
        }

        func emit(_ a: UInt32, _ b: UInt32, _ c: UInt32, outward: SIMD3<Float>) {
            let n = simd_cross(positions[Int(b)] - positions[Int(a)], positions[Int(c)] - positions[Int(a)])
            triangles.append(simd_dot(n, outward) >= 0 ? SIMD3(a, b, c) : SIMD3(a, c, b))
        }

        for k in 0..<(nz - 1) {
            for j in 0..<(ny - 1) {
                for i in 0..<(nx - 1) {
                    let base = grid.index(i, j, k)
                    var f = [Float](repeating: 0, count: 8)
                    var insideCount = 0
                    for c in 0..<8 {
                        f[c] = values[base + cornerOffsets[c]]
                        if f[c] < 0 { insideCount += 1 }
                    }
                    if insideCount == 0 || insideCount == 8 { continue }
                    let cell = SIMD3<Int>(i, j, k)

                    for tet in tetrahedra {
                        let corners = [tet.0, tet.1, tet.2, tet.3]
                        let inside = corners.filter { f[$0] < 0 }
                        let outside = corners.filter { f[$0] >= 0 }
                        if inside.isEmpty || outside.isEmpty { continue }

                        func p(_ c: Int) -> SIMD3<Float> {
                            grid.point(i + (c & 1), j + ((c >> 1) & 1), k + ((c >> 2) & 1))
                        }
                        func centroid(_ cs: [Int]) -> SIMD3<Float> {
                            cs.reduce(SIMD3<Float>.zero) { $0 + p($1) } / Float(cs.count)
                        }
                        // La normal debe apuntar de dentro hacia fuera.
                        let outward = centroid(outside) - centroid(inside)
                        func v(_ a: Int, _ b: Int) -> UInt32 {
                            vertex(base + cornerOffsets[a], a, base + cornerOffsets[b], b, base: cell)
                        }

                        if inside.count == 1 || inside.count == 3 {
                            let lone = inside.count == 1 ? inside[0] : outside[0]
                            let others = inside.count == 1 ? outside : inside
                            emit(v(lone, others[0]), v(lone, others[1]), v(lone, others[2]), outward: outward)
                        } else {
                            let (a, b) = (inside[0], inside[1])
                            let (c, d) = (outside[0], outside[1])
                            let ac = v(a, c), ad = v(a, d), bd = v(b, d), bc = v(b, c)
                            emit(ac, ad, bd, outward: outward)
                            emit(ac, bd, bc, outward: outward)
                        }
                    }
                }
            }
        }
        return Mesh(positions: positions, triangles: triangles)
    }
}
