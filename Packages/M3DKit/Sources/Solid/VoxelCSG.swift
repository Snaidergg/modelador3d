import Geometry
import simd

public enum SolidError: Error, Equatable, Sendable {
    /// La rejilla necesaria superaría la memoria razonable del teléfono.
    case tooFine
    /// El resultado no tiene superficie (por ejemplo, se restó todo el modelo).
    case empty
}

/// Operaciones de sólidos mediante una rejilla de distancias (vóxeles) dispersa.
/// Son robustas incluso con escaneos imperfectos y siempre devuelven una malla cerrada.
/// Precio: las aristas vivas se redondean como mucho medio vóxel.
public enum VoxelCSG {
    /// Máximo de puntos guardados (≈ 200 MB entre distancias y votos).
    public static let maxSamples = 40_000_000

    /// Combina el modelo con una forma. El tamaño del vóxel es la dimensión mayor / `resolution`,
    /// salvo que `spacing` lo fije directamente (por ejemplo, para que un texto pequeño se lea).
    public static func combine(_ mesh: Mesh, with shape: some DistanceShape, operation: BooleanOperation,
                               resolution: Int, spacing fixedSpacing: Float? = nil) throws -> Mesh {
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
        let spacing = try voxelSize(bounds, resolution: resolution, fixed: fixedSpacing)
        let field = SparseField(covering: bounds, spacing: spacing, jitterSeed: mesh.vertexCount)
        let band = spacing * 2.5
        field.allocateAround(mesh, band: band, fill: band)
        field.allocateAround(shape, band: band, fill: band)
        guard field.pointCount <= maxSamples else { throw SolidError.tooFine }

        MeshDistance.fill(field, from: mesh, band: band)
        field.values.withUnsafeMutableBufferPointer { v in
            field.forEachStoredPoint { idx, i, j, k in
                let s = shape.signedDistance(field.point(i, j, k))
                switch operation {
                case .union: v[idx] = Swift.min(v[idx], s)
                case .subtract: v[idx] = Swift.max(v[idx], -s)
                case .intersect: v[idx] = Swift.max(v[idx], s)
                }
            }
        }
        return try surface(field)
    }

    /// Reconstruye la malla con triángulos uniformes (útil antes de esculpir sobre un escaneo).
    public static func remesh(_ mesh: Mesh, resolution: Int) throws -> Mesh {
        let spacing = try voxelSize(mesh.bounds, resolution: resolution, fixed: nil)
        let field = SparseField(covering: mesh.bounds, spacing: spacing, jitterSeed: mesh.vertexCount)
        let band = spacing * 2.5
        field.allocateAround(mesh, band: band, fill: band)
        guard field.pointCount <= maxSamples else { throw SolidError.tooFine }
        MeshDistance.fill(field, from: mesh, band: band)
        return try surface(field)
    }

    /// Convierte una superficie (aunque esté abierta, como un vaso escaneado) en un sólido con
    /// paredes de `thickness` mm, la mitad a cada lado de la superficie original.
    public static func thicken(_ mesh: Mesh, thickness: Float, resolution: Int) throws -> Mesh {
        guard thickness > 0, !mesh.isEmpty else { throw SolidError.empty }
        let size = mesh.bounds.size
        // Al menos 3 vóxeles por pared, para que no aparezcan poros.
        let spacing = Swift.min(Swift.max(size.x, Swift.max(size.y, size.z)) / Float(resolution), thickness / 3)
        let padded = BoundingBox(min: mesh.bounds.min - thickness, max: mesh.bounds.max + thickness)
        let field = SparseField(covering: padded, spacing: spacing, jitterSeed: mesh.vertexCount)
        let half = thickness / 2
        let band = half + spacing * 2.5
        field.allocateAround(mesh, band: band, fill: band)
        guard field.pointCount <= maxSamples else { throw SolidError.tooFine }
        MeshDistance.fill(field, from: mesh, band: band, unsigned: true)
        field.values.withUnsafeMutableBufferPointer { v in
            for i in v.indices { v[i] -= half }
        }
        return try surface(field)
    }

    // MARK: Auxiliares

    static func voxelSize(_ bounds: BoundingBox, resolution: Int, fixed: Float?) throws -> Float {
        let size = bounds.size
        let largest = Swift.max(size.x, Swift.max(size.y, size.z))
        guard largest > 0 else { throw SolidError.empty }
        let automatic = largest / Float(Swift.max(resolution, 8))
        guard let fixed, fixed > 0 else { return automatic }
        return Swift.min(fixed, automatic)
    }

    static func surface(_ field: SparseField) throws -> Mesh {
        // Un valor exactamente 0 crearía vértices repetidos en la misma posición.
        let tiny = field.spacing * 1e-4
        field.values.withUnsafeMutableBufferPointer { v in
            for i in v.indices where v[i] == 0 { v[i] = tiny }
        }
        let mesh = MarchingTetrahedra.extract(field)
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
