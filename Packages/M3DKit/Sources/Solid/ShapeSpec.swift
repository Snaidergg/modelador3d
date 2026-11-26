import Geometry
import simd

public enum ShapeKind: String, CaseIterable, Identifiable, Sendable {
    case box, cylinder, cone, sphere
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .box: "Cubo"
        case .cylinder: "Cilindro"
        case .cone: "Cono"
        case .sphere: "Esfera"
        }
    }
    public var systemImage: String {
        switch self {
        case .box: "cube"
        case .cylinder: "cylinder"
        case .cone: "cone"
        case .sphere: "circle"
        }
    }
}

/// Dirección del eje de cilindros y conos.
public enum ShapeAxis: String, CaseIterable, Identifiable, Sendable {
    case y, x, z
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .y: "Vertical"
        case .x: "Eje X"
        case .z: "Eje Z"
        }
    }
    var direction: SIMD3<Float> {
        switch self {
        case .y: SIMD3<Float>(0, 1, 0)
        case .x: SIMD3<Float>(1, 0, 0)
        case .z: SIMD3<Float>(0, 0, 1)
        }
    }
}

public enum BooleanOperation: String, CaseIterable, Identifiable, Sendable {
    case union, subtract, intersect
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .union: "Unir"
        case .subtract: "Restar"
        case .intersect: "Intersecar"
        }
    }
}

/// Forma paramétrica con medidas en mm, ya colocada en la escena.
public struct ShapeSpec: Equatable, Sendable {
    public var kind: ShapeKind = .cylinder
    /// Cubo: ancho (X). Cilindro, cono y esfera: diámetro (en el cono, el de la base).
    public var width: Float = 20
    /// Alto a lo largo del eje (cubo: Y).
    public var height: Float = 5
    /// Cubo: fondo (Z).
    public var depth: Float = 20
    /// Cono: diámetro de arriba (0 = punta).
    public var topDiameter: Float = 0
    public var center: SIMD3<Float> = .zero
    public var axis: ShapeAxis = .y

    public init() {}

    private var rotation: simd_quatf {
        Mesh.rotationAligning(SIMD3<Float>(0, 1, 0), to: axis.direction)
    }

    private var radii: (bottom: Float, top: Float) {
        switch kind {
        case .cone: (width / 2, Swift.max(topDiameter, 0) / 2)
        default: (width / 2, width / 2)
        }
    }

    /// Malla de la forma (para la vista previa o como modelo nuevo).
    public func mesh() -> Mesh {
        let local: Mesh
        switch kind {
        case .box:
            local = Mesh.box(size: SIMD3<Float>(width, height, depth))
        case .sphere:
            local = Mesh.icosphere(radius: width / 2, subdivisions: 3)
        case .cylinder, .cone:
            local = Mesh.frustum(bottomRadius: radii.bottom, topRadius: radii.top, height: height)
        }
        return local.rotated(by: kind == .sphere ? simd_quatf(angle: 0, axis: SIMD3<Float>(1, 0, 0)) : rotation)
            .translated(by: center)
    }

    /// Caja envolvente en el espacio de la escena.
    public var bounds: BoundingBox {
        let half: SIMD3<Float>
        switch kind {
        case .box: half = SIMD3<Float>(width, height, depth) / 2
        case .sphere: return BoundingBox(min: center - width / 2, max: center + width / 2)
        case .cylinder, .cone:
            let r = Swift.max(radii.bottom, radii.top)
            half = SIMD3<Float>(r, height / 2, r)
        }
        var corners: [SIMD3<Float>] = []
        for i in 0..<8 {
            let s = SIMD3<Float>(i & 1 == 0 ? -1 : 1, i & 2 == 0 ? -1 : 1, i & 4 == 0 ? -1 : 1)
            corners.append(rotation.act(s * half) + center)
        }
        return BoundingBox(points: corners)
    }

    /// Distancia con signo (negativa dentro) desde `p` hasta la superficie.
    public func signedDistance(_ p: SIMD3<Float>) -> Float {
        let local = rotation.inverse.act(p - center)
        switch kind {
        case .sphere:
            return simd_length(p - center) - width / 2
        case .box:
            let q = simd_abs(local) - SIMD3<Float>(width, height, depth) / 2
            return simd_length(simd_max(q, .zero)) + Swift.min(Swift.max(q.x, Swift.max(q.y, q.z)), 0)
        case .cylinder, .cone:
            // Sólido de revolución: distancia 2D al trapecio (radio, altura).
            let q = SIMD2<Float>(simd_length(SIMD2<Float>(local.x, local.z)), local.y)
            let (r1, r2) = radii
            let h = height / 2
            if r2 > 0 {
                return ShapeSpec.polygonDistance(q, [SIMD2(-r1, -h), SIMD2(r1, -h), SIMD2(r2, h), SIMD2(-r2, h)])
            }
            return ShapeSpec.polygonDistance(q, [SIMD2(-r1, -h), SIMD2(r1, -h), SIMD2(0, h)])
        }
    }

    /// Distancia con signo de un punto a un polígono 2D (negativa dentro).
    static func polygonDistance(_ p: SIMD2<Float>, _ v: [SIMD2<Float>]) -> Float {
        var d = simd_length_squared(p - v[0])
        var s: Float = 1
        var j = v.count - 1
        for i in v.indices {
            let e = v[j] - v[i], w = p - v[i]
            let ee = simd_dot(e, e)
            let t = ee > 0 ? Swift.min(Swift.max(simd_dot(w, e) / ee, 0), 1) : 0
            let b = w - e * t
            d = Swift.min(d, simd_dot(b, b))
            let c0 = p.y >= v[i].y, c1 = p.y < v[j].y, c2 = e.x * w.y > e.y * w.x
            if (c0 && c1 && c2) || (!c0 && !c1 && !c2) { s = -s }
            j = i
        }
        return s * d.squareRoot()
    }
}
