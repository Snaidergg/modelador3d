import Foundation
import Geometry
import simd

/// STL: el formato más universal para impresión 3D.
public enum STLFormat {
    /// Exporta STL binario (mucho más compacto que el ASCII).
    public static func exportBinary(_ mesh: Mesh, fileUpAxis: UpAxis = .z) -> Data {
        let count = mesh.triangleCount
        var data = Data(capacity: 84 + 50 * count)

        var header = [UInt8](repeating: 0, count: 80)
        let tag = Array("Modelador3D binary STL".utf8)
        header.replaceSubrange(0..<tag.count, with: tag)
        data.append(contentsOf: header)
        data.appendLittleEndian(UInt32(count))

        for t in 0..<count {
            let (a, b, c) = mesh.corners(of: t)
            data.appendLittleEndian(fileUpAxis.toFile(mesh.faceNormal(t)))
            data.appendLittleEndian(fileUpAxis.toFile(a))
            data.appendLittleEndian(fileUpAxis.toFile(b))
            data.appendLittleEndian(fileUpAxis.toFile(c))
            data.appendLittleEndian(UInt16(0))
        }
        return data
    }

    /// Carga STL binario o ASCII y une los vértices duplicados.
    public static func load(_ data: Data, fileUpAxis: UpAxis = .z) throws -> Mesh {
        let startsWithSolid = data.prefix(5) == Data("solid".utf8)

        if data.count >= 84 {
            let declared = Int(readUInt32(data, at: 80))
            if 84 + declared * 50 == data.count {
                return try loadBinary(data, count: declared, axis: fileUpAxis)
            }
        }
        if startsWithSolid {
            let mesh = try loadASCII(data, axis: fileUpAxis)
            if !mesh.isEmpty { return mesh }
        }
        if data.count >= 84 {
            // Algunos programas escriben un conteo incorrecto: usar lo que realmente cabe.
            let available = (data.count - 84) / 50
            let declared = Int(readUInt32(data, at: 80))
            return try loadBinary(data, count: Swift.min(declared, available), axis: fileUpAxis)
        }
        throw MeshIOError.invalidData("STL vacío o dañado")
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data.withUnsafeBytes { raw in
            UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
        }
    }

    private static func loadBinary(_ data: Data, count: Int, axis: UpAxis) throws -> Mesh {
        guard count > 0 else { throw MeshIOError.invalidData("el STL no tiene triángulos") }
        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(count * 3)
        var triangles: [SIMD3<UInt32>] = []
        triangles.reserveCapacity(count)

        data.withUnsafeBytes { raw in
            func float(_ offset: Int) -> Float {
                Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
            }
            for t in 0..<count {
                let base = 84 + t * 50 + 12 // saltar la normal guardada; se recalcula
                for k in 0..<3 {
                    let o = base + k * 12
                    positions.append(axis.fromFile(SIMD3<Float>(float(o), float(o + 4), float(o + 8))))
                }
                let i = UInt32(t * 3)
                triangles.append(SIMD3<UInt32>(i, i + 1, i + 2))
            }
        }
        return Mesh(positions: positions, triangles: triangles).welded()
    }

    private static func loadASCII(_ data: Data, axis: UpAxis) throws -> Mesh {
        let text = String(decoding: data, as: UTF8.self)
        let tokens = text.split(whereSeparator: { $0.isWhitespace })
        var positions: [SIMD3<Float>] = []
        var i = 0
        while i < tokens.count {
            if tokens[i].lowercased() == "vertex", i + 3 < tokens.count {
                guard let x = Float(tokens[i + 1]), let y = Float(tokens[i + 2]), let z = Float(tokens[i + 3]) else {
                    throw MeshIOError.invalidData("coordenada no numérica en STL ASCII")
                }
                positions.append(axis.fromFile(SIMD3<Float>(x, y, z)))
                i += 4
            } else {
                i += 1
            }
        }
        let triCount = positions.count / 3
        positions.removeLast(positions.count - triCount * 3)
        let triangles = (0..<triCount).map { t -> SIMD3<UInt32> in
            let base = UInt32(t * 3)
            return SIMD3<UInt32>(base, base + 1, base + 2)
        }
        return Mesh(positions: positions, triangles: triangles).welded()
    }
}
