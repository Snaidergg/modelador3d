import Geometry
import simd

/// Patrón Comando: cada operación sobre el modelo es un objeto con nombre.
/// Permite deshacer/rehacer y, más adelante, un historial editable (modelado paramétrico).
protocol EditCommand {
    var name: String { get }
    /// Si tras aplicarlo la cámara debe volver a encuadrar el modelo.
    var reframes: Bool { get }
    func apply(to mesh: Mesh) -> Mesh
}

extension EditCommand {
    var reframes: Bool { true }
}

/// Sustituye el modelo completo (nueva primitiva, importación, resultado de un escaneo).
struct ReplaceMeshCommand: EditCommand {
    let name: String
    let mesh: Mesh
    func apply(to _: Mesh) -> Mesh { mesh }
}

/// Escala uniformemente para que el modelo mida `height` mm de alto.
struct ScaleToHeightCommand: EditCommand {
    let height: Float
    var name: String { "Escalar a \(Int(height)) mm" }
    func apply(to mesh: Mesh) -> Mesh {
        let current = mesh.bounds.size.y
        guard current > 0, height > 0 else { return mesh }
        return mesh.scaled(by: height / current).recentered()
    }
}

/// Centra el modelo y lo apoya en la cama de impresión.
struct PlaceOnBedCommand: EditCommand {
    let name = "Apoyar en la cama"
    func apply(to mesh: Mesh) -> Mesh { mesh.recentered() }
}

/// Une vértices duplicados (repara mallas importadas "sueltas").
struct WeldCommand: EditCommand {
    let name = "Soldar vértices"
    var reframes: Bool { false }
    func apply(to mesh: Mesh) -> Mesh { mesh.welded(tolerance: 0.01) }
}

/// Invierte las normales.
struct FlipNormalsCommand: EditCommand {
    let name = "Invertir normales"
    var reframes: Bool { false }
    func apply(to mesh: Mesh) -> Mesh { mesh.flipped() }
}

/// Multiplica por 4 los triángulos para tener más detalle al esculpir.
struct SubdivideCommand: EditCommand {
    let name = "Subdividir"
    var reframes: Bool { false }
    func apply(to mesh: Mesh) -> Mesh { mesh.subdivided() }
}

/// Historial de deshacer/rehacer basado en instantáneas.
/// Suficiente por ahora; con mallas muy grandes se cambiará por deltas de vértices.
struct CommandHistory {
    private struct Entry {
        let name: String
        let before: Mesh
        let after: Mesh
    }

    private var undoStack: [Entry] = []
    private var redoStack: [Entry] = []
    private let limit = 30

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var undoName: String? { undoStack.last?.name }

    mutating func record(name: String, before: Mesh, after: Mesh) {
        undoStack.append(Entry(name: name, before: before, after: after))
        if undoStack.count > limit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    mutating func undo() -> Mesh? {
        guard let entry = undoStack.popLast() else { return nil }
        redoStack.append(entry)
        return entry.before
    }

    mutating func redo() -> Mesh? {
        guard let entry = redoStack.popLast() else { return nil }
        undoStack.append(entry)
        return entry.after
    }
}
