import Geometry
import MetalKit
import simd

/// Dibuja una malla en un MTKView con la GPU del dispositivo.
public final class MeshRenderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    public var camera = OrbitCamera()
    /// Tras cambiarlo hay que volver a llamar a `setMesh`.
    public var smoothShading = true
    public var baseColor = SIMD4<Float>(0.78, 0.80, 0.84, 1)
    /// Altura del plano de corte que se dibuja (semitransparente); `nil` para ocultarlo.
    public var cutPlaneY: Float?
    public var cutPlaneColor = SIMD4<Float>(0.95, 0.35, 0.30, 0.35)

    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let blendedPipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let overlayDepthState: MTLDepthStencilState
    private var meshBounds = BoundingBox(min: .zero, max: .zero)
    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private var drawCount = 0
    /// Topología del último índice subido: si no cambia (escultura), no se vuelve a subir.
    private var uploadedTriangles: [SIMD3<UInt32>] = []

    struct GPUVertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
    }

    struct Uniforms {
        var viewProjection: simd_float4x4
        var model: simd_float4x4
        var baseColor: SIMD4<Float>
        var lightDir: SIMD4<Float>
    }

    public init?(view: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }

        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1)
        view.preferredFramesPerSecond = 60

        let pipeline: MTLRenderPipelineState
        let blendedPipeline: MTLRenderPipelineState
        do {
            let library = try device.makeLibrary(source: ShaderSource.code, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
            descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
            descriptor.vertexDescriptor = MeshRenderer.makeVertexDescriptor()
            descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

            // Igual, pero con transparencia (para el plano de corte).
            let attachment = descriptor.colorAttachments[0]!
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.sourceAlphaBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            blendedPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("Error creando el pipeline de Metal: \(error)")
            return nil
        }

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        let overlayDescriptor = MTLDepthStencilDescriptor()
        overlayDescriptor.depthCompareFunction = .less
        overlayDescriptor.isDepthWriteEnabled = false
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor),
              let overlayDepthState = device.makeDepthStencilState(descriptor: overlayDescriptor) else { return nil }

        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.blendedPipeline = blendedPipeline
        self.depthState = depthState
        self.overlayDepthState = overlayDepthState
        super.init()
    }

    private static func makeVertexDescriptor() -> MTLVertexDescriptor {
        let d = MTLVertexDescriptor()
        d.attributes[0].format = .float3
        d.attributes[0].offset = 0
        d.attributes[0].bufferIndex = 0
        d.attributes[1].format = .float3
        d.attributes[1].offset = MemoryLayout<GPUVertex>.offset(of: \GPUVertex.normal) ?? 16
        d.attributes[1].bufferIndex = 0
        d.layouts[0].stride = MemoryLayout<GPUVertex>.stride
        return d
    }

    /// Encuadra un modelo completo en pantalla.
    public func frame(_ bounds: BoundingBox) {
        camera.frame(bounds)
    }

    /// Sube la malla a la GPU. Es barato llamarlo en cada movimiento del pincel:
    /// con sombreado suave solo se reenvían los vértices, no los índices.
    public func setMesh(_ mesh: Mesh) {
        meshBounds = mesh.bounds
        guard !mesh.isEmpty else {
            vertexBuffer = nil
            indexBuffer = nil
            uploadedTriangles = []
            drawCount = 0
            return
        }

        if smoothShading {
            let normals = mesh.vertexNormals()
            var vertices: [GPUVertex] = []
            vertices.reserveCapacity(mesh.vertexCount)
            for i in mesh.positions.indices {
                vertices.append(GPUVertex(position: mesh.positions[i], normal: normals[i]))
            }
            vertexBuffer = makeBuffer(vertices)

            if indexBuffer == nil || mesh.triangles != uploadedTriangles {
                var indices: [UInt32] = []
                indices.reserveCapacity(mesh.triangleCount * 3)
                for t in mesh.triangles {
                    indices.append(t.x)
                    indices.append(t.y)
                    indices.append(t.z)
                }
                indexBuffer = makeBuffer(indices)
                uploadedTriangles = mesh.triangles
            }
        } else {
            // Sombreado plano: cada triángulo con sus propios vértices y la normal de la cara.
            var vertices: [GPUVertex] = []
            vertices.reserveCapacity(mesh.triangleCount * 3)
            for t in mesh.triangles.indices {
                let tri = mesh.triangles[t]
                let n = mesh.faceNormal(t)
                vertices.append(GPUVertex(position: mesh.positions[Int(tri.x)], normal: n))
                vertices.append(GPUVertex(position: mesh.positions[Int(tri.y)], normal: n))
                vertices.append(GPUVertex(position: mesh.positions[Int(tri.z)], normal: n))
            }
            vertexBuffer = makeBuffer(vertices)
            indexBuffer = nil
            uploadedTriangles = []
        }
        drawCount = mesh.triangleCount * 3
    }

    private func makeBuffer<T>(_ array: [T]) -> MTLBuffer? {
        guard !array.isEmpty else { return nil }
        return array.withUnsafeBytes { raw in
            device.makeBuffer(bytes: raw.baseAddress!, length: raw.count, options: .storageModeShared)
        }
    }

    // MARK: Conversión pantalla ↔ mundo

    /// Rayo que sale de la cámara y pasa por un punto de la pantalla (en puntos de UIKit).
    public func ray(through point: CGPoint, viewSize: CGSize) -> Ray {
        let w = Float(max(viewSize.width, 1))
        let h = Float(max(viewSize.height, 1))
        let ndc = SIMD2<Float>(2 * Float(point.x) / w - 1, 1 - 2 * Float(point.y) / h)
        let inverse = simd_inverse(camera.projectionMatrix(aspect: w / h) * camera.viewMatrix())
        func unproject(_ z: Float) -> SIMD3<Float> {
            let p = inverse * SIMD4<Float>(ndc.x, ndc.y, z, 1)
            return SIMD3<Float>(p.x, p.y, p.z) / p.w
        }
        let near = unproject(0)
        let far = unproject(1)
        return Ray(origin: near, direction: far - near)
    }

    /// Cuántos mm del modelo ocupa un punto de pantalla a cierta distancia de la cámara.
    public func worldUnitsPerPoint(atDistance distance: Float, viewHeight: CGFloat) -> Float {
        2 * distance * tan(camera.fovY * 0.5) / Float(max(viewHeight, 1))
    }

    private func drawCutPlane(at y: Float, encoder: MTLRenderCommandEncoder, view: MTKView) {
        let center = meshBounds.center
        let half = SIMD2<Float>(max(meshBounds.size.x, 1), max(meshBounds.size.z, 1)) * 0.75
        let n = SIMD3<Float>(0, 1, 0)
        let corners = [
            SIMD3<Float>(center.x - half.x, y, center.z - half.y),
            SIMD3<Float>(center.x + half.x, y, center.z - half.y),
            SIMD3<Float>(center.x + half.x, y, center.z + half.y),
            SIMD3<Float>(center.x - half.x, y, center.z + half.y),
        ]
        var quad = [0, 1, 2, 0, 2, 3].map { GPUVertex(position: corners[$0], normal: n) }

        let size = view.drawableSize
        let aspect = Float(size.width / max(size.height, 1))
        var uniforms = Uniforms(viewProjection: camera.projectionMatrix(aspect: aspect) * camera.viewMatrix(),
                                model: matrix_identity_float4x4,
                                baseColor: cutPlaneColor,
                                lightDir: SIMD4<Float>(camera.viewDirection, 0))
        encoder.setRenderPipelineState(blendedPipeline)
        encoder.setDepthStencilState(overlayDepthState)
        encoder.setVertexBytes(&quad, length: MemoryLayout<GPUVertex>.stride * quad.count, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: quad.count)
    }

    // MARK: MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)
        // Nuestras caras exteriores van en sentido antihorario (Metal asume horario por defecto).
        encoder.setFrontFacing(.counterClockwise)

        if let vertexBuffer, drawCount > 0 {
            let size = view.drawableSize
            let aspect = Float(size.width / max(size.height, 1))
            let viewProjection = camera.projectionMatrix(aspect: aspect) * camera.viewMatrix()
            var uniforms = Uniforms(viewProjection: viewProjection,
                                    model: matrix_identity_float4x4,
                                    baseColor: baseColor,
                                    lightDir: SIMD4<Float>(camera.viewDirection, 0))
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            if let indexBuffer {
                encoder.drawIndexedPrimitives(type: .triangle,
                                              indexCount: drawCount,
                                              indexType: .uint32,
                                              indexBuffer: indexBuffer,
                                              indexBufferOffset: 0)
            } else {
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: drawCount)
            }
        }

        if let planeY = cutPlaneY {
            drawCutPlane(at: planeY, encoder: encoder, view: view)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
