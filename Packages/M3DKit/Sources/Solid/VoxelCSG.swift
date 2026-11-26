import Geometry
import simd

public enum SolidError: Error, Equatable, Sendable {
    /// La rejilla necesaria superaría la memoria razonable del teléfono.
    case tooFine
    /// El resultado no tiene superficie (por ejemplo, se restó todo el modelo).
    case empty
}

/// Operaciones de sólidos mediante una rejilla de distancias (vóxeles).
/// Son robustas incluso con escaneos imperfectos y siempre devuelven una malla cerrada.
/// Precio: las aristas vivas se redondean como mucho medio vóxel.
public enum VoxelCSG {
    /// Máximo de puntos de la rejilla (≈ 260³): unos 300 MB entre todas las estructuras.
    public static let maxSamples = 18_000_000

    /// Combina el modelo con una forma. `resolution` = vóxeles a lo largo de la dimensión mayor.
    public static func combine(_ mesh: Mesh, with shape: ShapeSpec, operation: BooleanOperation,
                               resolution: Int) throws -> Mesh {
        let bounds: BoundingBox
        switch operation {
        case .union:
            bounds = union(mesh.bounds, shape.bounds)
        case .subtract:
            bounds = mesh.bounds
        case .intersect:
            guard let overlap = intersection(mesh.bounds, shape.bounds) else { throw SolidError.empty }
            bounds = overlap
        }
        let grid = try makeGrid(bounds, resolution: resolution, seed: mesh.vertexCount)
        var values = MeshDistance.sample(mesh, on: grid, band: grid.spacing * 2.5)
        for k in 0..<grid.nz {
            for j in 0..<grid.ny {
                for i in 0..<grid.nx {
                    let idx = grid.index(i, j, k)
                    let s = shape.signedDistance(grid.point(i, j, k))
                    switch operation {
                    case .union: values[idx] = Swift.min(values[idx], s)
                    case .subtract: values[idx] = Swift.max(values[idx], -s)
                    case .intersect: values[idx] = Swift.max(values[idx], s)
                    }
                }
            }
        }
        return try surface(values, grid: grid)
    }

    /// Reconstruye la malla con triángulos uniformes (útil antes de esculpir sobre un escaneo).
    public static func remesh(_ mesh: Mesh, resolution: Int) throws -> Mesh {
        let grid = try makeGrid(mesh.bounds, resolution: resolution, seed: mesh.vertexCount)
        let values = MeshDistance.sample(mesh, on: grid, band: grid.spacing * 2.5)
        return try surface(values, grid: grid)
    }

    /// Convierte una superficie (aunque esté abierta, como un vaso escaneado) en un sólido con
    /// paredes de `thickness` mm, la mitad a cada lado de la superficie original.
    public static func thicken(_ mesh: Mesh, thickness: Float, resolution: Int) throws -> Mesh {
        guard thickness > 0 else { throw SolidError.empty }
        let size = mesh.bounds.size
        // Al menos 3 vóxeles por pared, para que no aparezcan poros.
        let spacing = Swift.min(Swift.max(size.x, Swift.max(size.y, size.z)) / Float(resolution), thickness / 3)
        let padded = BoundingBox(min: mesh.bounds.min - thickness, max: mesh.bounds.max + thickness)
        let grid = VoxelGrid(covering: padded, spacing: spacing, jitterSeed: mesh.vertexCount)
        guard grid.count <= maxSamples else { throw SolidError.tooFine }
        let half = thickness / 2
        let distances = MeshDistance.sample(mesh, on: grid, band: half + spacing * 2.5, unsigned: true)
        return try surface(distances.map { $0 - half }, grid: grid)
    }

    // MARK: Auxiliares

    static func makeGrid(_ bounds: BoundingBox, resolution: Int, seed: Int) throws -> VoxelGrid {
        let size = bounds.size
        let largest = Swift.max(size.x, Swift.max(size.y, size.z))
        guard largest > 0 else { throw SolidError.empty }
        let grid = VoxelGrid(covering: bounds, spacing: largest / Float(Swift.max(resolution, 8)), jitterSeed: seed)
        guard grid.count <= maxSamples else { throw SolidError.tooFine }
        return grid
    }

    static func surface(_ values: [Float], grid: VoxelGrid) throws -> Mesh {
        // Un valor exactamente 0 crearía vértices repetidos en la misma posición.
        let tiny = grid.spacing * 1e-4
        let safe = values.map { $0 == 0 ? tiny : $0 }
        let mesh = MarchingTetrahedra.extract(safe, grid: grid)
        guard !mesh.isEmpty else { throw SolidError.empty }
        return mesh
    }

    static func union(_ a: BoundingBox, _ b: BoundingBox) -> BoundingBox {
        BoundingBox(min: simd_min(a.min, b.min), max: simd_max(a.max, b.max))
    }

    static func intersection(_ a: BoundingBox, _ b: BoundingBox) -> BoundingBox? {
        let lo = simd_max(a.min, b.min), hi = simd_min(a.max, b.max)
        guard lo.x < hi.x, lo.y < hi.y, lo.z < hi.z else { return nil }
        return BoundingBox(min: lo, max: hi)
    }
}
