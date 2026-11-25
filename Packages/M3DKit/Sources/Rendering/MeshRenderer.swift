import Geometry
import MetalKit
import simd

/// Dibuja una malla en un MTKView con la GPU del dispositivo.
public final class MeshRenderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    public var camera = OrbitCamera()
    public var smoothShading = true
    public var baseColor = SIMD4<Float>(0.78, 0.80, 0.84, 1)

    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private var vertexBuffer: MTLBuffer?
    private var vertexCount = 0

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
        do {
            let library = try device.makeLibrary(source: ShaderSource.code, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
            descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
            descriptor.vertexDescriptor = MeshRenderer.makeVertexDescriptor()
            descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("Error creando el pipeline de Metal: \(error)")
            return nil
        }

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else { return nil }

        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.depthState = depthState
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

    /// Sube la malla a la GPU. `frameCamera` la encuadra en pantalla.
    public func setMesh(_ mesh: Mesh, frameCamera: Bool) {
        if frameCamera { camera.frame(mesh.bounds) }
        guard !mesh.isEmpty else {
            vertexBuffer = nil
            vertexCount = 0
            return
        }

        let normals = smoothShading ? mesh.vertexNormals() : []
        var vertices: [GPUVertex] = []
        vertices.reserveCapacity(mesh.triangleCount * 3)
        for t in mesh.triangles.indices {
            let tri = mesh.triangles[t]
            let faceNormal = smoothShading ? SIMD3<Float>.zero : mesh.faceNormal(t)
            for i in [tri.x, tri.y, tri.z] {
                let index = Int(i)
                vertices.append(GPUVertex(position: mesh.positions[index],
                                          normal: smoothShading ? normals[index] : faceNormal))
            }
        }
        vertexBuffer = device.makeBuffer(bytes: vertices,
                                         length: vertices.count * MemoryLayout<GPUVertex>.stride,
                                         options: .storageModeShared)
        vertexCount = vertices.count
    }

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

        if let vertexBuffer, vertexCount > 0 {
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
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
