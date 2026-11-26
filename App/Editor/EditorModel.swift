import Foundation
import Geometry
import MeshIO
import PrintPrep
import Sculpt
import Solid
import SwiftUI

enum EditorMode {
    /// Los gestos solo mueven la cámara.
    case view
    /// Un dedo sobre el modelo esculpe; fuera del modelo, gira la cámara.
    case sculpt
    /// Se muestra un plano de corte que se mueve con el panel inferior.
    case cut
    /// Tocar una cara la apoya en la cama; el panel permite inclinar en pasos de 1° o 5°.
    case orient
    /// Se muestra una forma (cubo, cilindro…) semitransparente que se une o se resta del modelo.
    case shape
}

/// Estado del editor (MVVM: la vista observa este modelo).
@MainActor
final class EditorModel: ObservableObject {
    /// Límite para no agotar la memoria del teléfono al subdividir.
    static let maxTriangles = 700_000

    @Published private(set) var mesh: Mesh
    /// Cambia cada vez que la malla cambia; el visor lo usa para saber cuándo subirla a la GPU.
    @Published private(set) var meshVersion = 0
    /// Cambia cuando la cámara debe volver a encuadrar el modelo.
    @Published private(set) var frameVersion = 0
    @Published private(set) var report: MeshReport
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var smoothShading = true
    @Published var mode: EditorMode = .view
    @Published var sculpt = SculptSettings()
    @Published var cutHeight: Float = 0
    @Published var cutKeepAbove = true
    @Published var shape = ShapeSpec()
    @Published var shapeOperation: BooleanOperation = .union
    @Published var voxelQuality: VoxelQuality = .normal
    /// Texto de la operación larga en curso (nil si no hay ninguna).
    @Published private(set) var busyMessage: String?
    @Published var fileName = "esfera"
    @Published var errorMessage: String?

    private var history = CommandHistory()

    init() {
        let initial = EditorModel.sculptBase()
        mesh = initial
        report = MeshAnalyzer.analyze(initial)
    }

    /// Esfera geodésica de 40 mm con 20 480 triángulos.
    private static func sculptBase() -> Mesh {
        Mesh.icosphere(radius: 20, subdivisions: 5).recentered()
    }

    func perform(_ command: EditCommand) {
        let before = mesh
        let after = command.apply(to: before)
        guard after != before else { return }
        history.record(name: command.name, before: before, after: after)
        show(after, frame: command.reframes)
    }

    /// Guarda un trazo de escultura terminado como un paso deshacible.
    func commitStroke(_ sculpted: Mesh, brush: BrushKind) {
        guard sculpted != mesh else { return }
        history.record(name: brush.displayName, before: mesh, after: sculpted)
        show(sculpted, frame: false)
    }

    func undo() {
        if let previous = history.undo() { show(previous, frame: false) }
    }

    func redo() {
        if let next = history.redo() { show(next, frame: false) }
    }

    func newSphere() {
        smoothShading = true
        fileName = "esfera"
        perform(ReplaceMeshCommand(name: "Nueva esfera", mesh: EditorModel.sculptBase()))
    }

    func newBox() {
        smoothShading = false
        fileName = "cubo"
        perform(ReplaceMeshCommand(name: "Nuevo cubo",
                                   mesh: Mesh.box(size: SIMD3<Float>(30, 30, 30)).recentered()))
    }

    func newCylinder() {
        smoothShading = false
        fileName = "cilindro"
        perform(ReplaceMeshCommand(name: "Nuevo cilindro", mesh: Mesh.cylinder(radius: 15, height: 30).recentered()))
    }

    func newCone() {
        smoothShading = false
        fileName = "cono"
        perform(ReplaceMeshCommand(name: "Nuevo cono",
                                   mesh: Mesh.frustum(bottomRadius: 15, topRadius: 0, height: 30).recentered()))
    }

    // MARK: Formas y operaciones de sólidos

    /// Entra en modo formas con valores útiles para la operación elegida.
    func beginShape(_ operation: BooleanOperation = .union) {
        shapeOperation = operation
        shape = defaultShape(for: operation)
        mode = .shape
    }

    /// Al cambiar de operación se propone otra forma: una base para unir, un agujero para restar.
    func changeShapeOperation(_ operation: BooleanOperation) {
        guard operation != shapeOperation else { return }
        shapeOperation = operation
        shape = defaultShape(for: operation)
    }

    private func defaultShape(for operation: BooleanOperation) -> ShapeSpec {
        let b = mesh.bounds
        var s = ShapeSpec()
        s.kind = .cylinder
        s.axis = .y
        switch operation {
        case .union:
            // Base redonda bajo el modelo, solapada 0,5 mm para que quede unida.
            s.width = Swift.max((Swift.max(b.size.x, b.size.z) * 1.2).rounded(), 5)
            s.depth = s.width
            s.height = 3
            s.center = SIMD3<Float>(b.center.x, b.min.y - s.height / 2 + 0.5, b.center.z)
        case .subtract:
            // Agujero vertical que atraviesa el modelo (p. ej. para un tornillo o un imán).
            s.width = Swift.max((Swift.min(b.size.x, b.size.z) * 0.2).rounded(), 2)
            s.depth = s.width
            s.height = b.size.y + 2
            s.center = b.center
        case .intersect:
            s.kind = .box
            s.width = b.size.x
            s.height = b.size.y * 0.5
            s.depth = b.size.z
            s.center = SIMD3<Float>(b.center.x, b.min.y + s.height / 2, b.center.z)
        }
        return s
    }

    func applyShape() {
        let mesh = self.mesh, shape = self.shape, operation = shapeOperation
        let resolution = voxelQuality.resolution
        runHeavy("\(operation.displayName) \(shape.kind.displayName.lowercased())", onSuccess: { [weak self] in
            self?.mode = .view
        }) {
            try VoxelCSG.combine(mesh, with: shape, operation: operation, resolution: resolution)
        }
    }

    func remesh() {
        let mesh = self.mesh, resolution = voxelQuality.resolution
        runHeavy("Remallar") { try VoxelCSG.remesh(mesh, resolution: resolution) }
    }

    func thicken(_ thickness: Float) {
        let mesh = self.mesh, resolution = voxelQuality.resolution
        runHeavy("Dar grosor de \(Format.mm(thickness)) mm") {
            try VoxelCSG.thicken(mesh, thickness: thickness, resolution: resolution)
        }
    }

    /// Ejecuta una operación pesada fuera del hilo principal y la guarda como paso deshacible.
    private func runHeavy(_ name: String, onSuccess: (@MainActor () -> Void)? = nil,
                          _ work: @escaping @Sendable () throws -> Mesh) {
        guard busyMessage == nil else { return }
        busyMessage = "\(name)…"
        Task {
            let result = await Task.detached(priority: .userInitiated) { Result { try work() } }.value
            busyMessage = nil
            switch result {
            case .success(let newMesh):
                perform(ReplaceMeshCommand(name: name, mesh: newMesh.recentered()))
                onSuccess?()
            case .failure(let error):
                errorMessage = EditorModel.describe(error)
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error as? SolidError {
        case .tooFine?:
            return "La operación necesita demasiada memoria con esta calidad. Elige una calidad menor "
                + "(o, para dar grosor, una pared más gruesa)."
        case .empty?:
            return "El resultado quedó vacío: la forma no toca el modelo o lo eliminó por completo."
        case nil:
            return error.localizedDescription
        }
    }

    /// Entra en modo recorte con el plano cerca de la base (donde suele colarse el soporte o la mesa).
    func beginCut() {
        let b = mesh.bounds
        cutHeight = b.min.y + b.size.y * 0.1
        cutKeepAbove = true
        mode = .cut
    }

    /// Apoya en la cama la cara tocada (se usa la normal media de la zona, para que el ruido de un
    /// escaneo no tuerza el resultado).
    func layFlat(at point: SIMD3<Float>, triangle: Int) {
        let radius = max(mesh.bounds.radius * 0.04, 0.5)
        guard let normal = mesh.averageNormal(around: point, radius: radius, including: triangle) else { return }
        perform(LayFlatCommand(normal: normal))
    }

    func tilt(_ axis: RotateCommand.Axis, degrees: Float) {
        perform(RotateCommand(axis: axis, degrees: degrees))
    }

    func applyCut() {
        perform(CutCommand(height: cutHeight, keepAbove: cutKeepAbove))
        mode = .view
    }

    /// Abre en el editor el modelo que salió de un escaneo, fotos o video.
    func importCaptured(_ captured: Mesh) {
        smoothShading = true
        mode = .view
        fileName = "captura"
        perform(ReplaceMeshCommand(name: "Captura 3D", mesh: captured))
    }

    func subdivide() {
        guard mesh.triangleCount * 4 <= EditorModel.maxTriangles else {
            errorMessage = "El modelo ya tiene \(mesh.triangleCount.formatted()) triángulos. "
                + "Subdividir otra vez superaría el límite de \(EditorModel.maxTriangles.formatted())."
            return
        }
        perform(SubdivideCommand())
    }

    func importFile(at url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let loaded = try MeshFile.load(from: url)
            guard !loaded.isEmpty else { throw MeshIOError.invalidData("el modelo está vacío") }
            fileName = url.deletingPathExtension().lastPathComponent
            perform(ReplaceMeshCommand(name: "Importar \(fileName)", mesh: loaded.recentered()))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func makeSTLDocument() -> MeshFileDocument {
        MeshFileDocument(data: STLFormat.exportBinary(mesh))
    }

    private func show(_ newMesh: Mesh, frame: Bool) {
        mesh = newMesh
        report = MeshAnalyzer.analyze(newMesh)
        meshVersion += 1
        if frame { frameVersion += 1 }
        canUndo = history.canUndo
        canRedo = history.canRedo
    }
}
