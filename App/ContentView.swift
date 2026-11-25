import SwiftUI

struct ContentView: View {
    @StateObject private var model = EditorModel()
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var showInspector = false
    @State private var exportDocument: MeshFileDocument?

    var body: some View {
        NavigationStack {
            MetalViewport(mesh: model.mesh,
                          version: model.meshVersion,
                          frameVersion: model.frameVersion,
                          smoothShading: model.smoothShading,
                          mode: model.mode,
                          sculptSettings: model.sculpt,
                          onStrokeEnded: { mesh, brush in model.commitStroke(mesh, brush: brush) })
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { statusBar }
                .overlay(alignment: .bottom) {
                    if model.mode == .sculpt {
                        SculptPanel(settings: $model.sculpt,
                                    triangleCount: model.report.triangleCount,
                                    onSubdivide: { model.subdivide() })
                    }
                }
                .navigationTitle(model.fileName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.stlModel, .objModel]) { result in
            switch result {
            case .success(let url): model.importFile(at: url)
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .fileExporter(isPresented: $showExporter,
                      document: exportDocument,
                      contentType: .stlModel,
                      defaultFilename: model.fileName) { result in
            if case .failure(let error) = result {
                model.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showInspector) {
            InspectorView(model: model)
                .presentationDetents([.medium, .large])
        }
        .alert("Aviso",
               isPresented: Binding(get: { model.errorMessage != nil },
                                    set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.canRedo)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                model.mode = model.mode == .sculpt ? .view : .sculpt
            } label: {
                Image(systemName: model.mode == .sculpt ? "paintbrush.pointed.fill" : "paintbrush.pointed")
            }
            Menu {
                Section("Nuevo modelo") {
                    Button("Esfera para esculpir", systemImage: "circle") { model.newSphere() }
                    Button("Cubo", systemImage: "cube") { model.newBox() }
                }
                Button("Importar STL u OBJ…", systemImage: "square.and.arrow.down") { showImporter = true }
            } label: {
                Image(systemName: "plus")
            }
            Button {
                exportDocument = model.makeSTLDocument()
                showExporter = true
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            Button { showInspector = true } label: { Image(systemName: "slider.horizontal.3") }
        }
    }

    private var statusBar: some View {
        let r = model.report
        return HStack(spacing: 12) {
            Label("\(r.triangleCount.formatted())", systemImage: "triangle")
            Text("\(Format.mm(r.size.x)) × \(Format.mm(r.size.y)) × \(Format.mm(r.size.z)) mm")
            Image(systemName: r.isWatertight ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(r.isWatertight ? .green : .orange)
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 8)
        .allowsHitTesting(false)
    }
}

enum Format {
    static func mm(_ value: Float) -> String {
        Double(value).formatted(.number.precision(.fractionLength(1)))
    }
}
