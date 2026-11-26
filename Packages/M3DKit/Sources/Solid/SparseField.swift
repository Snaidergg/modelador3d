import Geometry
import simd

/// Campo de distancias con signo (negativo dentro) de una forma cualquiera.
public protocol DistanceShape: Sendable {
    func signedDistance(_ p: SIMD3<Float>) -> Float
    var bounds: BoundingBox { get }
}

extension ShapeSpec: DistanceShape {}

/// Rejilla dispersa: solo guarda bloques de 8×8×8 puntos cerca de las superficies.
/// Un modelo de 20 cm con vóxeles de 0,5 mm ocuparía 64 millones de puntos en una rejilla completa;
/// así solo se guardan los pocos millones que rodean la superficie.
final class SparseField {
    static let side = 8
    static let brickPoints = 512

    let origin: SIMD3<Float>
    let spacing: Float
    /// Puntos por eje del dominio.
    let nx: Int, ny: Int, nz: Int
    /// Bloques por eje.
    let bx: Int, by: Int, bz: Int

    private(set) var slotOfBrick: [Int: Int] = [:]
    private(set) var brickCoords: [SIMD3<Int32>] = []
    var values: [Float] = []

    var pointCount: Int { values.count }

    init(covering bounds: BoundingBox, spacing: Float, padding: Int = 3, jitterSeed: Int) {
        // El origen se desplaza una fracción "irracional" de celda, distinta para cada malla, para que los
        // rayos de la prueba dentro/fuera casi nunca pasen justo por un vértice o una arista.
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
        bx = (nx + 7) / 8
        by = (ny + 7) / 8
        bz = (nz + 7) / 8
        self.spacing = spacing
    }

    @inline(__always) func brickKey(_ x: Int, _ y: Int, _ z: Int) -> Int { (z * by + y) * bx + x }

    @inline(__always) func slot(_ x: Int, _ y: Int, _ z: Int) -> Int? {
        guard x >= 0, y >= 0, z >= 0, x < bx, y < by, z < bz else { return nil }
        return slotOfBrick[brickKey(x, y, z)]
    }

    @inline(__always) static func local(_ i: Int, _ j: Int, _ k: Int) -> Int { i + j * 8 + k * 64 }

    @inline(__always) func point(_ i: Int, _ j: Int, _ k: Int) -> SIMD3<Float> {
        origin + SIMD3<Float>(Float(i), Float(j), Float(k)) * spacing
    }

    /// Coordenadas de rejilla (reales) de un punto del espacio.
    @inline(__always) func gridCoordinates(_ p: SIMD3<Float>) -> SIMD3<Float> { (p - origin) / spacing }

    /// Rango de puntos de rejilla dentro de [lo, hi] (en mm), recortado al dominio. nil si está vacío.
    func pointRange(_ lo: SIMD3<Float>, _ hi: SIMD3<Float>) -> (i: ClosedRange<Int>, j: ClosedRange<Int>, k: ClosedRange<Int>)? {
        let a = gridCoordinates(lo), b = gridCoordinates(hi)
        let i0 = Swift.max(0, Int(a.x.rounded(.up))), i1 = Swift.min(nx - 1, Int(b.x.rounded(.down)))
        let j0 = Swift.max(0, Int(a.y.rounded(.up))), j1 = Swift.min(ny - 1, Int(b.y.rounded(.down)))
        let k0 = Swift.max(0, Int(a.z.rounded(.up))), k1 = Swift.min(nz - 1, Int(b.z.rounded(.down)))
        guard i0 <= i1, j0 <= j1, k0 <= k1 else { return nil }
        return (i0...i1, j0...j1, k0...k1)
    }

    /// Reserva los bloques que contienen algún punto del rango.
    func allocate(_ range: (i: ClosedRange<Int>, j: ClosedRange<Int>, k: ClosedRange<Int>), fill: Float) {
        for z in (range.k.lowerBound / 8)...(range.k.upperBound / 8) {
            for y in (range.j.lowerBound / 8)...(range.j.upperBound / 8) {
                for x in (range.i.lowerBound / 8)...(range.i.upperBound / 8) {
                    allocateBrick(x, y, z, fill: fill)
                }
            }
        }
    }

    func allocateBrick(_ x: Int, _ y: Int, _ z: Int, fill: Float) {
        let key = brickKey(x, y, z)
        guard slotOfBrick[key] == nil else { return }
        slotOfBrick[key] = brickCoords.count
        brickCoords.append(SIMD3<Int32>(Int32(x), Int32(y), Int32(z)))
        values.append(contentsOf: repeatElement(fill, count: SparseField.brickPoints))
    }

    /// Recorre los puntos del rango agrupados por bloque: (índice en `values`, i, j, k).
    @inline(__always)
    func forEachPoint(in range: (i: ClosedRange<Int>, j: ClosedRange<Int>, k: ClosedRange<Int>),
                      _ body: (Int, Int, Int, Int) -> Void) {
        for z in (range.k.lowerBound / 8)...(range.k.upperBound / 8) {
            for y in (range.j.lowerBound / 8)...(range.j.upperBound / 8) {
                for x in (range.i.lowerBound / 8)...(range.i.upperBound / 8) {
                    guard let s = slot(x, y, z) else { continue }
                    let base = s * SparseField.brickPoints
                    let k0 = Swift.max(range.k.lowerBound, z * 8), k1 = Swift.min(range.k.upperBound, z * 8 + 7)
                    let j0 = Swift.max(range.j.lowerBound, y * 8), j1 = Swift.min(range.j.upperBound, y * 8 + 7)
                    let i0 = Swift.max(range.i.lowerBound, x * 8), i1 = Swift.min(range.i.upperBound, x * 8 + 7)
                    for k in k0...k1 {
                        for j in j0...j1 {
                            for i in i0...i1 {
                                body(base + SparseField.local(i & 7, j & 7, k & 7), i, j, k)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Recorre todos los puntos guardados dentro del dominio.
    func forEachStoredPoint(_ body: (Int, Int, Int, Int) -> Void) {
        for (s, b) in brickCoords.enumerated() {
            let base = s * SparseField.brickPoints
            let x0 = Int(b.x) * 8, y0 = Int(b.y) * 8, z0 = Int(b.z) * 8
            for lk in 0..<8 where z0 + lk < nz {
                for lj in 0..<8 where y0 + lj < ny {
                    for li in 0..<8 where x0 + li < nx {
                        body(base + SparseField.local(li, lj, lk), x0 + li, y0 + lj, z0 + lk)
                    }
                }
            }
        }
    }

    // MARK: Reserva alrededor de superficies

    /// Bloques a menos de `band` de algún triángulo.
    func allocateAround(_ mesh: Mesh, band: Float, fill: Float) {
        for t in mesh.triangles.indices {
            let (a, b, c) = mesh.corners(of: t)
            if let range = pointRange(simd_min(a, simd_min(b, c)) - band, simd_max(a, simd_max(b, c)) + band) {
                allocate(range, fill: fill)
            }
        }
    }

    /// Bloques a menos de `band` de la superficie de una forma (usa que la distancia es 1-Lipschitz).
    func allocateAround(_ shape: some DistanceShape, band: Float, fill: Float) {
        let b = shape.bounds
        guard let range = pointRange(b.min - band - 8 * spacing, b.max + band + 8 * spacing) else { return }
        let reach = 3.5 * spacing * Float(3).squareRoot() + band
        for z in (range.k.lowerBound / 8)...(range.k.upperBound / 8) {
            for y in (range.j.lowerBound / 8)...(range.j.upperBound / 8) {
                for x in (range.i.lowerBound / 8)...(range.i.upperBound / 8) {
                    let center = point(x * 8, y * 8, z * 8) + 3.5 * spacing
                    if abs(shape.signedDistance(center)) <= reach { allocateBrick(x, y, z, fill: fill) }
                }
            }
        }
    }
}
