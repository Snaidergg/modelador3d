import Foundation
import Geometry
import MeshIO
import PrintPrep
import Sculpt
import SwiftUI

enum EditorMode {
    /// Los gestos solo mueven la cámara.
    case view
    /// Un dedo sobre el modelo esculpe; fuera del modelo, gira la cámara.
    case sculpt
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
