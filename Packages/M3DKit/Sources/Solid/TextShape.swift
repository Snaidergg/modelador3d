import CoreGraphics
import CoreText
import Foundation
import Geometry
import simd

/// Fuentes disponibles en iOS y macOS (así las pruebas usan las mismas).
public enum TextFont: String, CaseIterable, Identifiable, Sendable {
    case bold = "Helvetica-Bold"
    case rounded = "ArialRoundedMTBold"
    case heavy = "AvenirNext-Heavy"
    case serif = "Georgia-Bold"
    case mono = "Courier-Bold"

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .bold: "Negrita"
        case .rounded: "Redondeada"
        case .heavy: "Gruesa"
        case .serif: "Con serifa"
        case .mono: "Máquina de escribir"
        }
    }
}

/// Contornos 2D de un texto en mm, centrados en el origen (X a la derecha, Y hacia arriba).
public struct TextOutline: Equatable, Sendable {
    public var loops: [[SIMD2<Float>]]
    public var size: SIMD2<Float>

    public var isEmpty: Bool { loops.isEmpty }

    public init(loops: [[SIMD2<Float>]], size: SIMD2<Float>) {
        self.loops = loops
        self.size = size
    }

    /// `height` es el alto total del texto en mm (de la letra más baja a la más alta).
    public static func make(_ text: String, font: TextFont, height: Float) -> TextOutline {
        let line = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, height > 0 else { return TextOutline(loops: [], size: .zero) }

        let ctFont = CTFontCreateWithName(font.rawValue as CFString, 100, nil)
        let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): ctFont]
        let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attributes))
        let collector = PathCollector()

        for run in (CTLineGetGlyphRuns(ctLine) as? [CTRun]) ?? [] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            // Si falta un carácter en la fuente, CoreText usa otra: hay que pedir el contorno a esa.
            let runAttributes = CTRunGetAttributes(run) as NSDictionary
            let runFont: CTFont
            if let value = runAttributes[kCTFontAttributeName] {
                runFont = value as! CTFont
            } else {
                runFont = ctFont
            }
            for g in 0..<count {
                var transform = CGAffineTransform(translationX: positions[g].x, y: positions[g].y)
                guard let path = CTFontCreatePathForGlyph(runFont, glyphs[g], &transform) else { continue }
                collector.add(path)
            }
        }
        return normalized(collector.loops, height: height)
    }

    static func normalized(_ raw: [[SIMD2<Float>]], height: Float) -> TextOutline {
        let loops = raw.filter { $0.count >= 3 }
        guard let first = loops.first?.first else { return TextOutline(loops: [], size: .zero) }
        var lo = first, hi = first
        for loop in loops { for p in loop { lo = simd_min(lo, p); hi = simd_max(hi, p) } }
        let rawSize = hi - lo
        guard rawSize.y > 0 else { return TextOutline(loops: [], size: .zero) }
        let scale = height / rawSize.y
        let center = (lo + hi) / 2
        return TextOutline(loops: loops.map { $0.map { ($0 - center) * scale } }, size: rawSize * scale)
    }

    /// Recorre un CGPath y aproxima las curvas con segmentos.
    private final class PathCollector {
        var loops: [[SIMD2<Float>]] = []
        private var current: [SIMD2<Float>] = []
        private var last = SIMD2<Float>.zero

        func add(_ path: CGPath) {
            path.applyWithBlock { element in self.handle(element.pointee) }
            finish()
        }

        private func handle(_ e: CGPathElement) {
            switch e.type {
            case .moveToPoint:
                finish()
                append(vector(e.points[0]))
            case .addLineToPoint:
                append(vector(e.points[0]))
            case .addQuadCurveToPoint:
                let p0 = last
                let c = vector(e.points[0])
                let p1 = vector(e.points[1])
                for s in 1...6 { append(quadratic(p0, c, p1, Float(s) / 6)) }
            case .addCurveToPoint:
                let p0 = last
                let c1 = vector(e.points[0])
                let c2 = vector(e.points[1])
                let p1 = vector(e.points[2])
                for s in 1...8 { append(cubic(p0, c1, c2, p1, Float(s) / 8)) }
            case .closeSubpath:
                finish()
            @unknown default:
                break
            }
        }

        private func quadratic(_ p0: SIMD2<Float>, _ c: SIMD2<Float>, _ p1: SIMD2<Float>, _ t: Float) -> SIMD2<Float> {
            let m: Float = 1 - t
            let w0: Float = m * m
            let w1: Float = 2 * m * t
            let w2: Float = t * t
            return p0 * w0 + c * w1 + p1 * w2
        }

        private func cubic(_ p0: SIMD2<Float>, _ c1: SIMD2<Float>, _ c2: SIMD2<Float>, _ p1: SIMD2<Float>,
                           _ t: Float) -> SIMD2<Float> {
            let m: Float = 1 - t
            let w0: Float = m * m * m
            let w1: Float = 3 * m * m * t
            let w2: Float = 3 * m * t * t
            let w3: Float = t * t * t
            let a: SIMD2<Float> = p0 * w0 + c1 * w1
            let b: SIMD2<Float> = c2 * w2 + p1 * w3
            return a + b
        }

        private func vector(_ p: CGPoint) -> SIMD2<Float> { SIMD2<Float>(Float(p.x), Float(p.y)) }

        private func append(_ p: SIMD2<Float>) {
            if let previous = current.last, simd_distance(previous, p) < 1e-4 { last = p; return }
            current.append(p)
            last = p
        }

        private func finish() {
            if let f = current.first, let l = current.last, current.count > 1, simd_distance(f, l) < 1e-4 {
                current.removeLast()
            }
            if current.count >= 3 { loops.append(current) }
            current = []
        }
    }
}

/// Texto extruido, apoyado sobre la superficie del modelo.
/// El texto queda en el plano tangente al punto `anchor`, entre `bottom` y `top` mm a lo largo de la normal
/// (negativo = hacia dentro del modelo).
public struct TextShape: DistanceShape, Equatable {
    public var outline: TextOutline
    public var anchor: SIMD3<Float>
    public var normal: SIMD3<Float>
    /// Giro del texto sobre la superficie, en grados.
    public var rotation: Float
    public var bottom: Float
    public var top: Float

    public init(outline: TextOutline, anchor: SIMD3<Float>, normal: SIMD3<Float>,
                rotation: Float = 0, bottom: Float, top: Float) {
        self.outline = outline
        self.anchor = anchor
        self.normal = simd_length(normal) > 0 ? simd_normalize(normal) : SIMD3<Float>(0, 0, 1)
        self.rotation = rotation
        self.bottom = Swift.min(bottom, top)
        self.top = Swift.max(bottom, top)
    }

    /// Ejes del texto: derecha (u) y arriba (v) sobre la superficie.
    /// "Arriba" es el eje Y del modelo; en caras horizontales, hacia el fondo (−Z), para leerse de frente.
    public var frame: (u: SIMD3<Float>, v: SIMD3<Float>) {
        let n = normal
        var up = SIMD3<Float>(0, 1, 0) - n * n.y
        if simd_length(up) < 0.2 {
            let back = SIMD3<Float>(0, 0, -1)
            up = back - n * simd_dot(back, n)
        }
        let v0 = simd_normalize(up)
        let u0 = simd_cross(v0, n)
        let a = rotation * .pi / 180
        let u = u0 * cos(a) + v0 * sin(a)
        let v = v0 * cos(a) - u0 * sin(a)
        return (u, v)
    }

    public var bounds: BoundingBox {
        let (u, v) = frame
        let h = outline.size / 2
        var corners: [SIMD3<Float>] = []
        for sx in [-h.x, h.x] { for sy in [-h.y, h.y] { for sz in [bottom, top] {
            corners.append(anchor + u * sx + v * sy + normal * sz)
        } } }
        return BoundingBox(points: corners)
    }

    public func signedDistance(_ p: SIMD3<Float>) -> Float {
        let (u, v) = frame
        let d = p - anchor
        let q = SIMD2<Float>(simd_dot(d, u), simd_dot(d, v))
        let z = simd_dot(d, normal)
        let wz = Swift.max(bottom - z, z - top)

        // Lejos del rectángulo del texto basta la distancia al rectángulo (siempre es menor o igual).
        let half = outline.size / 2
        let outsideBox = simd_max(simd_abs(q) - half, .zero)
        let boxDistance = simd_length(outsideBox)
        let d2: Float = boxDistance > 6 ? boxDistance : outlineDistance(q)

        let w = SIMD2<Float>(d2, wz)
        return Swift.min(Swift.max(w.x, w.y), 0) + simd_length(simd_max(w, .zero))
    }

    /// Distancia con signo 2D a los contornos (regla par-impar: los huecos de "o", "A"… quedan fuera).
    func outlineDistance(_ p: SIMD2<Float>) -> Float {
        var best = Float.greatestFiniteMagnitude
        var inside = false
        for loop in outline.loops {
            var j = loop.count - 1
            for i in loop.indices {
                let a = loop[j], b = loop[i]
                let e = b - a, w = p - a
                let ee = simd_dot(e, e)
                let t = ee > 0 ? Swift.min(Swift.max(simd_dot(w, e) / ee, 0), 1) : 0
                best = Swift.min(best, simd_length_squared(w - e * t))
                if (a.y > p.y) != (b.y > p.y) {
                    let x = a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x)
                    if p.x < x { inside.toggle() }
                }
                j = i
            }
        }
        let dist = best.squareRoot()
        return inside ? -dist : dist
    }

    /// Paredes del texto (por ambas caras) para la vista previa semitransparente.
    public func previewMesh() -> Mesh {
        let (u, v) = frame
        var positions: [SIMD3<Float>] = []
        var triangles: [SIMD3<UInt32>] = []
        func place(_ q: SIMD2<Float>, _ z: Float) -> SIMD3<Float> { anchor + u * q.x + v * q.y + normal * z }
        for loop in outline.loops {
            var j = loop.count - 1
            for i in loop.indices {
                let b0 = UInt32(positions.count)
                let b1: UInt32 = b0 + 1, b2: UInt32 = b0 + 2, b3: UInt32 = b0 + 3
                positions.append(place(loop[j], bottom))
                positions.append(place(loop[i], bottom))
                positions.append(place(loop[i], top))
                positions.append(place(loop[j], top))
                // Por las dos caras, para que se vea desde cualquier lado.
                triangles.append(SIMD3<UInt32>(b0, b1, b2))
                triangles.append(SIMD3<UInt32>(b0, b2, b3))
                triangles.append(SIMD3<UInt32>(b0, b2, b1))
                triangles.append(SIMD3<UInt32>(b0, b3, b2))
                j = i
            }
        }
        return Mesh(positions: positions, triangles: triangles)
    }
}
