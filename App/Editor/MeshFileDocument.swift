import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let stlModel = UTType(filenameExtension: "stl") ?? .data
    static let objModel = UTType(filenameExtension: "obj") ?? .data
    static let plyModel = UTType(filenameExtension: "ply") ?? .data
}

/// Documento para el diálogo "Guardar en Archivos".
struct MeshFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.stlModel] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
