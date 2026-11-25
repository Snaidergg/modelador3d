import Geometry
import simd

/// Informe de imprimibilidad de una malla.
public struct MeshReport: Equatable, Sendable {
    public var triangleCount: Int
    public var vertexCount: Int
    /// Dimensiones en mm.
    public var size: SIMD3<Float>
    /// Área en mm².
    public var surfaceArea: Float
    /// Volumen con signo en mm³ (positivo si las normales apuntan hacia afuera).
    public var volume: Float
    /// Aristas usadas por un solo triángulo (agujeros en la malla).
    public var boundaryEdges: Int
    /// Aristas compartidas por más de dos triángulos.
    public var nonManifoldEdges: Int
    /// Aristas cuyos dos triángulos tienen orientación opuesta (normales mezcladas).
    public var inconsistentEdges: Int

    /// Una malla estanca y bien orientada es la que los slicers imprimen sin problemas.
    public var isWatertight: Bool {
        triangleCount > 0 && boundaryEdges == 0 && nonManifoldEdges == 0 && inconsistentEdges == 0
    }

    public var normalsPointInward: Bool { isWatertight && volume < 0 }
}

public enum MeshAnalyzer {
    public static func analyze(_ mesh: Mesh) -> MeshReport {
        struct Edge: Hashable { let a: UInt32, b: UInt32 }
        struct Use { var forward = 0, backward = 0 }

        var edges: [Edge: Use] = [:]
        edges.reserveCapacity(mesh.triangleCount * 3 / 2)
        var area: Float = 0
        var volume: Float = 0

        for t in mesh.triangles.indices {
            let tri = mesh.triangles[t]
            let (p0, p1, p2) = mesh.corners(of: t)
            let cross = simd_cross(p1 - p0, p2 - p0)
            area += simd_length(cross) * 0.5
            volume += simd_dot(p0, simd_cross(p1, p2)) / 6

            for (u, v) in [(tri.x, tri.y), (tri.y, tri.z), (tri.z, tri.x)] {
                if u < v {
                    edges[Edge(a: u, b: v), default: Use()].forward += 1
                } else {
                    edges[Edge(a: v, b: u), default: Use()].backward += 1
                }
            }
        }

        var boundary = 0, nonManifold = 0, inconsistent = 0
        for use in edges.values {
            let total = use.forward + use.backward
            if total == 1 {
                boundary += 1
            } else if total > 2 {
                nonManifold += 1
            } else if use.forward != 1 {
                inconsistent += 1
            }
        }

        return MeshReport(
            triangleCount: mesh.triangleCount,
            vertexCount: mesh.vertexCount,
            size: mesh.bounds.size,
            surfaceArea: area,
            volume: volume,
            boundaryEdges: boundary,
            nonManifoldEdges: nonManifold,
            inconsistentEdges: inconsistent
        )
    }
}
