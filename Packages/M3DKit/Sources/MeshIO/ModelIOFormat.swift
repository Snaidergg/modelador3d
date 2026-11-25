#if canImport(ModelIO)
import Foundation
import Geometry
import ModelIO
import simd

/// Lee formatos que entiende ModelIO de Apple: USDZ (el que produce Object Capture), USD y PLY.
public enum ModelIOFormat {
    public static let extensions = ["usdz", "usd", "usda", "usdc", "ply"]

    /// - Parameter scale: factor para pasar a mm. Si es `nil` se adivina: los modelos de menos de
    ///   10 unidades se asumen en metros (Object Capture y la mayoría de USDZ) y se multiplican por 1000.
    public static func load(url: URL, scale: Float? = nil) throws -> Mesh {
        let ext = url.pathExtension.lowercased()
        guard MDLAsset.canImportFileExtension(ext) else { throw MeshIOError.unsupportedFormat(ext) }

        let asset = MDLAsset(url: url)
        var positions: [SIMD3<Float>] = []
        var triangles: [SIMD3<UInt32>] = []

        for case let mesh as MDLMesh in asset.childObjects(of: MDLMesh.self) {
            guard let attribute = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition),
                  attribute.format == .float3 || attribute.format == .float4 else { continue }

            let base = UInt32(positions.count)
            let vertexCount = mesh.vertexCount
            let transform = MDLTransform.globalTransform(with: mesh, atTime: 0)
            let vertexStride = attribute.stride
            let start = UnsafeRawPointer(attribute.dataStart)

            for i in 0..<vertexCount {
                let o = i * vertexStride
                let x = start.loadUnaligned(fromByteOffset: o, as: Float.self)
                let y = start.loadUnaligned(fromByteOffset: o + 4, as: Float.self)
                let z = start.loadUnaligned(fromByteOffset: o + 8, as: Float.self)
                let p = transform * SIMD4<Float>(x, y, z, 1)
                positions.append(SIMD3<Float>(p.x, p.y, p.z))
            }

            guard let submeshes = mesh.submeshes else { continue }
            for case let submesh as MDLSubmesh in submeshes {
                guard submesh.geometryType == .triangles else { continue }
                let map = submesh.indexBuffer.map()
                let bytes = UnsafeRawPointer(map.bytes)
                var indices: [UInt32] = []
                indices.reserveCapacity(submesh.indexCount)
                for k in 0..<submesh.indexCount {
                    switch submesh.indexType {
                    case .uInt8: indices.append(UInt32(bytes.load(fromByteOffset: k, as: UInt8.self)))
                    case .uInt16: indices.append(UInt32(bytes.loadUnaligned(fromByteOffset: k * 2, as: UInt16.self)))
                    case .uInt32: indices.append(bytes.loadUnaligned(fromByteOffset: k * 4, as: UInt32.self))
                    default: throw MeshIOError.invalidData("tipo de índice desconocido")
                    }
                }
                var t = 0
                while t + 2 < indices.count {
                    let a = indices[t], b = indices[t + 1], c = indices[t + 2]
                    if Int(a) < vertexCount, Int(b) < vertexCount, Int(c) < vertexCount {
                        triangles.append(SIMD3<UInt32>(base + a, base + b, base + c))
                    }
                    t += 3
                }
            }
        }

        guard !triangles.isEmpty else { throw MeshIOError.invalidData("el archivo no contiene mallas de triángulos") }
        let mesh = Mesh(positions: positions, triangles: triangles)
        let size = mesh.bounds.size
        let largest = Swift.max(size.x, Swift.max(size.y, size.z))
        let factor = scale ?? (largest < 10 ? 1000 : 1)
        return (factor == 1 ? mesh : mesh.scaled(by: factor)).welded(tolerance: 0.001)
    }
}
#endif
