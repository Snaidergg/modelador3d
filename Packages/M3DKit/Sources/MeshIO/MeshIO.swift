import Foundation
import Geometry
import simd

public enum MeshIOError: Error, LocalizedError {
    case invalidData(String)
    case unsupportedFormat(String)

    public var errorDescription: String? {
        switch self {
        case .invalidData(let detail): return "Archivo no válido: \(detail)"
        case .unsupportedFormat(let ext): return "Formato no soportado: .\(ext)"
        }
    }
}

/// Eje vertical que usa un formato de archivo. Internamente la app usa +Y arriba;
/// los slicers (Cura, PrusaSlicer, Bambu) esperan +Z arriba en STL/3MF.
public enum UpAxis: Sendable {
    case y, z

    /// Interno (Y arriba) → archivo. Es una rotación de +90° en X: conserva la orientación.
    func toFile(_ p: SIMD3<Float>) -> SIMD3<Float> {
        switch self {
        case .y: return p
        case .z: return SIMD3<Float>(p.x, -p.z, p.y)
        }
    }

    /// Archivo → interno (Y arriba).
    func fromFile(_ p: SIMD3<Float>) -> SIMD3<Float> {
        switch self {
        case .y: return p
        case .z: return SIMD3<Float>(p.x, p.z, -p.y)
        }
    }
}

public enum MeshFile {
    /// Carga un archivo según su extensión.
    public static func load(from url: URL) throws -> Mesh {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "stl": return try STLFormat.load(Data(contentsOf: url))
        case "obj": return try OBJFormat.load(Data(contentsOf: url))
        default:
            #if canImport(ModelIO)
            if ModelIOFormat.extensions.contains(ext) {
                return try ModelIOFormat.load(url: url)
            }
            #endif
            throw MeshIOError.unsupportedFormat(url.pathExtension)
        }
    }
}

extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { self.append(contentsOf: $0) }
    }

    mutating func appendLittleEndian(_ value: Float) {
        appendLittleEndian(value.bitPattern)
    }

    mutating func appendLittleEndian(_ v: SIMD3<Float>) {
        appendLittleEndian(v.x)
        appendLittleEndian(v.y)
        appendLittleEndian(v.z)
    }
}
