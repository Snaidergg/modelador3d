import Foundation
import Geometry
import MeshIO
import PrintPrep
import SwiftUI

/// Estado del editor (MVVM: la vista observa este modelo).
@MainActor
final class EditorModel: ObservableObject {
    @Published private(set) var mesh: Mesh
    /// Cambia cada vez que la malla cambia; el visor lo usa para saber cuándo subirla a la GPU.
    @Published private(set) var meshVersion = 0
    @Published private(set) var report: MeshReport
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var smoothShading = true
    @Published var fileName = "esfera"
    @Published var errorMessage: String?

    private var history = CommandHistory()

    init() {
        let initial = Mesh.uvSphere(radius: 20, segments: 64, rings: 32).recentered()
        mesh = initial
        report = MeshAnalyzer.analyze(initial)
    }

    func perform(_ command: EditCommand) {
        let before = mesh
        let after = command.apply(to: before)
        guard after != before else { return }
        history.record(name: command.name, before: before, after: after)
        show(after)
    }

    func undo() {
        if let previous = history.undo() { show(previous) }
    }

    func redo() {
        if let next = history.redo() { show(next) }
    }

    func newSphere() {
        smoothShading = true
        fileName = "esfera"
        perform(ReplaceMeshCommand(name: "Nueva esfera",
                                   mesh: Mesh.uvSphere(radius: 20, segments: 64, rings: 32).recentered()))
    }

    func newBox() {
        smoothShading = false
        fileName = "cubo"
        perform(ReplaceMeshCommand(name: "Nuevo cubo",
                                   mesh: Mesh.box(size: SIMD3<Float>(30, 30, 30)).recentered()))
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

    private func show(_ newMesh: Mesh) {
        mesh = newMesh
        report = MeshAnalyzer.analyze(newMesh)
        meshVersion += 1
        canUndo = history.canUndo
        canRedo = history.canRedo
    }
}
