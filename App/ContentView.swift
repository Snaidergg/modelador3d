import Solid
import SwiftUI

struct ContentView: View {
    @StateObject private var model = EditorModel()
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var showInspector = false
    @State private var showCapture = false
    @State private var exportDocument: MeshFileDocument?

    var body: some View {
        NavigationStack {
            MetalViewport(mesh: model.mesh,
                          version: model.meshVersion,
                          frameVersion: model.frameVersion,
                          smoothShading: model.smoothShading,
                          mode: model.mode,
                          sculptSettings: model.sculpt,
                          cutPlaneY: planeY,
                          overlay: model.mode == .shape ? model.shape : nil,
                          overlayColor: overlayColor,
                          onStrokeEnded: { mesh, brush in model.commitStroke(mesh, brush: brush) },
                          onFaceTapped: { point, triangle in model.layFlat(at: point, triangle: triangle) })
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { statusBar }
                .overlay(alignment: .bottom) {
                    if model.mode == .sculpt {
                        SculptPanel(settings: $model.sculpt,
                                    triangleCount: model.report.triangleCount,
                                    onSubdivide: { model.subdivide() })
                    } else if model.mode == .cut {
                        CutPanel(height: $model.cutHeight,
                                 keepAbove: $model.cutKeepAbove,
                                 range: model.mesh.bounds.min.y...max(model.mesh.bounds.max.y, model.mesh.bounds.min.y + 0.1),
                                 onCancel: { model.mode = .view },
                                 onApply: { model.applyCut() })
                    } else if model.mode == .shape {
                        ShapePanel(shape: $model.shape,
                                   operation: $model.shapeOperation,
                                   quality: $model.voxelQuality,
                                   modelBounds: model.mesh.bounds,
                                   busy: model.busyMessage != nil,
                                   onOperationChanged: { model.changeShapeOperation($0) },
                                   onCancel: { model.mode = .view },
                                   onApply: { model.applyShape() })
                    } else if model.mode == .orient {
                        OrientPanel(onTilt: { axis, degrees in model.tilt(axis, degrees: degrees) },
                                    onDone: { model.mode = .view })
                    }
                }
                .overlay {
                    if let message = model.busyMessage {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text(message).font(.callout)
                            Text("Puede tardar unos segundos").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .disabled(model.busyMessage != nil)
                .navigationTitle(model.fileName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.stlModel, .objModel, .usdz, .plyModel]) { result in
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
        .fullScreenCover(isPresented: $showCapture) {
            CaptureFlowView { captured in model.importCaptured(captured) }
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

    /// Plano que se dibuja: el de corte (rojo) o la cama de impresión (azul) al orientar.
    private var planeY: Float? {
        switch model.mode {
        case .cut: return model.cutHeight
        case .orient: return model.mesh.bounds.min.y
        default: return nil
        }
    }

    /// Verde = unir, rojo = restar, azul = intersecar.
    private var overlayColor: SIMD4<Float> {
        switch model.shapeOperation {
        case .union: SIMD4<Float>(0.35, 0.80, 0.45, 0.40)
        case .subtract: SIMD4<Float>(0.95, 0.35, 0.30, 0.45)
        case .intersect: SIMD4<Float>(0.30, 0.55, 0.95, 0.40)
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
            Button { showCapture = true } label: { Image(systemName: "camera.viewfinder") }
            Button {
                model.mode = model.mode == .sculpt ? .view : .sculpt
            } label: {
                Image(systemName: model.mode == .sculpt ? "paintbrush.pointed.fill" : "paintbrush.pointed")
            }
            Menu {
                Section("Nuevo modelo") {
                    Button("Esfera para esculpir", systemImage: "circle") { model.newSphere() }
                    Button("Cubo", systemImage: "cube") { model.newBox() }
                    Button("Cilindro", systemImage: "cylinder") { model.newCylinder() }
                    Button("Cono", systemImage: "cone") { model.newCone() }
                }
                Section("Sólidos") {
                    Button("Añadir forma (unir)…", systemImage: "plus.square.on.square") { model.beginShape(.union) }
                    Button("Hacer agujero (restar)…", systemImage: "minus.square") { model.beginShape(.subtract) }
                }
                Button("Importar STL, OBJ, USDZ o PLY…", systemImage: "square.and.arrow.down") { showImporter = true }
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
