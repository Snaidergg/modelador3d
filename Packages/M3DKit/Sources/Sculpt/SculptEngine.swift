import Geometry
import simd

/// Aplica pinceles de escultura sobre una copia de trabajo de la malla.
/// Durante un trazo, la vista llama a `applyDab` (o `updateGrab`) muchas veces; al terminar,
/// la malla resultante se entrega al editor como un único paso deshacible.
public final class SculptEngine {
    public private(set) var mesh: Mesh
    public private(set) var normals: [SIMD3<Float>]
    private let neighbors: [[UInt32]]
    private var grabbed: [GrabbedVertex] = []

    private struct GrabbedVertex {
        let index: Int
        let original: SIMD3<Float>
        let weight: Float
        let mirrored: Bool
    }

    public init(mesh: Mesh) {
        self.mesh = mesh
        self.normals = mesh.vertexNormals()
        self.neighbors = SculptEngine.buildNeighbors(mesh)
    }

    /// Punto de la superficie bajo el rayo.
    public func hit(_ ray: Ray) -> SIMD3<Float>? {
        mesh.raycast(ray)?.point
    }

    // MARK: Pinceles de toque (todos menos Arrastrar)

    public func applyDab(at center: SIMD3<Float>, radius: Float, settings: SculptSettings) {
        guard radius > 0, settings.brush != .grab else { return }
        dab(at: center, radius: radius, settings: settings)
        // Si el centro está casi sobre el plano de simetría, un solo toque ya es simétrico.
        if settings.symmetryX, abs(center.x) > radius * 0.25 {
            dab(at: SIMD3<Float>(-center.x, center.y, center.z), radius: radius, settings: settings)
        }
        normals = mesh.vertexNormals()
    }

    private func dab(at center: SIMD3<Float>, radius: Float, settings: SculptSettings) {
        let affected = verticesInside(center: center, radius: radius)
        guard !affected.isEmpty else { return }
        let sign: Float = settings.invert && settings.brush.supportsInvert ? -1 : 1
        let s = settings.strength

        switch settings.brush {
        case .draw:
            // Empuja la zona en la dirección normal media: crea relieves o surcos.
            var n = SIMD3<Float>.zero
            for (i, w) in affected { n += normals[i] * w }
            guard simd_length(n) > 0 else { return }
            n = simd_normalize(n)
            let step = sign * s * radius * 0.06
            for (i, w) in affected { mesh.positions[i] += n * (step * w) }

        case .inflate:
            // Empuja cada vértice según su propia normal: hincha o desinfla.
            let step = sign * s * radius * 0.04
            for (i, w) in affected { mesh.positions[i] += normals[i] * (step * w) }

        case .smooth:
            // Acerca cada vértice al promedio de sus vecinos (Laplaciano).
            var updates: [(Int, SIMD3<Float>)] = []
            updates.reserveCapacity(affected.count)
            for (i, w) in affected {
                let nb = neighbors[i]
                guard !nb.isEmpty else { continue }
                var avg = SIMD3<Float>.zero
                for j in nb { avg += mesh.positions[Int(j)] }
                avg /= Float(nb.count)
                let p = mesh.positions[i]
                updates.append((i, p + (avg - p) * Swift.min(1, s * w)))
            }
            for (i, p) in updates { mesh.positions[i] = p }

        case .flatten:
            // Proyecta los vértices hacia el plano medio de la zona.
            var c0 = SIMD3<Float>.zero, n = SIMD3<Float>.zero
            var total: Float = 0
            for (i, w) in affected {
                c0 += mesh.positions[i] * w
                n += normals[i] * w
                total += w
            }
            guard total > 0, simd_length(n) > 0 else { return }
            c0 /= total
            n = simd_normalize(n)
            for (i, w) in affected {
                let d = simd_dot(mesh.positions[i] - c0, n)
                mesh.positions[i] -= n * (d * Swift.min(1, s * w * 0.5))
            }

        case .grab:
            break
        }
    }

    // MARK: Arrastrar

    /// Fija la zona que se va a arrastrar durante todo el trazo.
    public func beginGrab(at center: SIMD3<Float>, radius: Float, symmetryX: Bool) {
        var chosen: [Int: GrabbedVertex] = [:]
        func collect(_ c: SIMD3<Float>, mirrored: Bool) {
            for (i, w) in verticesInside(center: c, radius: radius) {
                if let existing = chosen[i], existing.weight >= w { continue }
                chosen[i] = GrabbedVertex(index: i, original: mesh.positions[i], weight: w, mirrored: mirrored)
            }
        }
        collect(center, mirrored: false)
        if symmetryX, abs(center.x) > radius * 0.25 {
            collect(SIMD3<Float>(-center.x, center.y, center.z), mirrored: true)
        }
        grabbed = Array(chosen.values)
    }

    /// Mueve la zona fijada `delta` mm desde su posición original.
    public func updateGrab(delta: SIMD3<Float>) {
        guard !grabbed.isEmpty else { return }
        let mirroredDelta = SIMD3<Float>(-delta.x, delta.y, delta.z)
        for g in grabbed {
            mesh.positions[g.index] = g.original + (g.mirrored ? mirroredDelta : delta) * g.weight
        }
        normals = mesh.vertexNormals()
    }

    public func endStroke() {
        grabbed = []
        normals = mesh.vertexNormals()
    }

    // MARK: Utilidades

    /// Vértices dentro del radio, con su peso (1 en el centro, 0 en el borde, transición suave).
    private func verticesInside(center: SIMD3<Float>, radius: Float) -> [(Int, Float)] {
        let r2 = radius * radius
        var result: [(Int, Float)] = []
        for i in mesh.positions.indices {
            let d2 = simd_distance_squared(mesh.positions[i], center)
            if d2 < r2 {
                let x = 1 - d2 / r2
                result.append((i, x * x))
            }
        }
        return result
    }

    static func buildNeighbors(_ mesh: Mesh) -> [[UInt32]] {
        var neighbors = [[UInt32]](repeating: [], count: mesh.vertexCount)
        func link(_ a: UInt32, _ b: UInt32) {
            if !neighbors[Int(a)].contains(b) { neighbors[Int(a)].append(b) }
        }
        for t in mesh.triangles {
            link(t.x, t.y); link(t.y, t.x)
            link(t.y, t.z); link(t.z, t.y)
            link(t.z, t.x); link(t.x, t.z)
        }
        return neighbors
    }
}
