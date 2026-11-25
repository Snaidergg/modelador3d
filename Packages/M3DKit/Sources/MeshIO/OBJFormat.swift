import Foundation
import Geometry
import simd

/// OBJ: formato de intercambio con Blender, ZBrush, Nomad, etc. (Y arriba).
public enum OBJFormat {
    public static func load(_ data: Data) throws -> Mesh {
        let text = String(decoding: data, as: UTF8.self)
        var positions: [SIMD3<Float>] = []
        var triangles: [SIMD3<UInt32>] = []

        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let parts = rawLine.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let head = parts.first else { continue }

            if head == "v" {
                guard parts.count >= 4,
                      let x = Float(parts[1]), let y = Float(parts[2]), let z = Float(parts[3]) else {
                    throw MeshIOError.invalidData("vértice mal formado en OBJ")
                }
                positions.append(SIMD3<Float>(x, y, z))
            } else if head == "f" {
                var face: [UInt32] = []
                for token in parts.dropFirst() {
                    guard let first = token.split(separator: "/", omittingEmptySubsequences: false).first,
                          let raw = Int(first) else {
                        throw MeshIOError.invalidData("cara mal formada en OBJ")
                    }
                    // Índices de OBJ empiezan en 1; los negativos cuentan desde el final.
                    let index = raw < 0 ? positions.count + raw : raw - 1
                    guard index >= 0, index < positions.count else {
                        throw MeshIOError.invalidData("índice de vértice fuera de rango en OBJ")
                    }
                    face.append(UInt32(index))
                }
                guard face.count >= 3 else { continue }
                // Polígonos de más de 3 lados: triangular en abanico.
                for k in 1..<(face.count - 1) {
                    triangles.append(SIMD3<UInt32>(face[0], face[k], face[k + 1]))
                }
            }
        }
        guard !triangles.isEmpty else { throw MeshIOError.invalidData("el OBJ no tiene caras") }
        return Mesh(positions: positions, triangles: triangles)
    }

    public static func export(_ mesh: Mesh) -> Data {
        var out = "# Modelador3D\n"
        out.reserveCapacity(mesh.vertexCount * 32 + mesh.triangleCount * 24)
        for p in mesh.positions {
            out += "v \(p.x) \(p.y) \(p.z)\n"
        }
        for t in mesh.triangles {
            out += "f \(t.x + 1) \(t.y + 1) \(t.z + 1)\n"
        }
        return Data(out.utf8)
    }
}
