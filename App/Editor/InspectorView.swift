import PrintPrep
import SwiftUI

/// Panel con información del modelo y herramientas de preparación para impresión.
struct InspectorView: View {
    @ObservedObject var model: EditorModel
    @State private var targetHeight: Double = 50
    @State private var wallThickness: Double = 2
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Malla") {
                    LabeledContent("Triángulos", value: model.report.triangleCount.formatted())
                    LabeledContent("Vértices", value: model.report.vertexCount.formatted())
                    Toggle("Sombreado suave", isOn: $model.smoothShading)
                }

                Section("Dimensiones") {
                    LabeledContent("Ancho (X)", value: "\(Format.mm(model.report.size.x)) mm")
                    LabeledContent("Alto (Y)", value: "\(Format.mm(model.report.size.y)) mm")
                    LabeledContent("Fondo (Z)", value: "\(Format.mm(model.report.size.z)) mm")
                    LabeledContent("Volumen", value: "\(Format.mm(abs(model.report.volume) / 1000)) cm³")
                    LabeledContent("Superficie", value: "\(Format.mm(model.report.surfaceArea / 100)) cm²")
                }

                Section {
                    LabeledContent("Malla estanca") {
                        Text(model.report.isWatertight ? "Sí" : "No")
                            .foregroundStyle(model.report.isWatertight ? .green : .orange)
                    }
                    LabeledContent("Bordes abiertos", value: "\(model.report.boundaryEdges)")
                    LabeledContent("Aristas no-manifold", value: "\(model.report.nonManifoldEdges)")
                    LabeledContent("Normales inconsistentes", value: "\(model.report.inconsistentEdges)")
                    if model.report.normalsPointInward {
                        Text("Las normales apuntan hacia adentro. Usa “Invertir normales”.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Imprimibilidad")
                } footer: {
                    Text("Para imprimir, la malla debe ser estanca: sin agujeros ni aristas compartidas por más de dos caras.")
                }

                Section {
                    LabeledContent("Piezas separadas", value: "\(MeshRepair.pieceCount(model.mesh))")
                    Button("Orientar (apoyar en una cara)…", systemImage: "rotate.3d") {
                        model.mode = .orient
                        dismiss()
                    }
                    Button("Recortar con plano…", systemImage: "scissors") {
                        model.beginCut()
                        dismiss()
                    }
                    Button("Quitar piezas sueltas", systemImage: "trash.slash") { model.perform(RemovePiecesCommand()) }
                    Button("Cerrar agujeros", systemImage: "circle.dashed.inset.filled") { model.perform(FillHolesCommand()) }
                    Button("Reparar para imprimir", systemImage: "wand.and.stars") { model.perform(RepairForPrintCommand()) }
                } header: {
                    Text("Limpieza de capturas")
                } footer: {
                    Text("Primero orienta el modelo para que quede derecho, recorta el soporte o la mesa y luego usa “Reparar para imprimir”.")
                }

                Section {
                    Picker("Calidad", selection: $model.voxelQuality) {
                        ForEach(VoxelQuality.allCases) { Text($0.displayName).tag($0) }
                    }
                    Button("Remallar (triángulos uniformes)", systemImage: "circle.grid.cross") {
                        model.remesh()
                        dismiss()
                    }
                    HStack {
                        Text("Dar grosor")
                        TextField("Grosor", value: $wallThickness, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("mm").foregroundStyle(.secondary)
                        Button("Aplicar") {
                            model.thicken(Float(wallThickness))
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } header: {
                    Text("Sólidos (vóxeles)")
                } footer: {
                    Text("“Dar grosor” convierte una superficie abierta (un vaso, una máscara) en un sólido imprimible. "
                        + "Mayor calidad = más detalle, más triángulos y más tiempo.")
                }

                Section("Herramientas") {
                    HStack {
                        TextField("Altura", value: $targetHeight, format: .number)
                            .keyboardType(.decimalPad)
                        Text("mm").foregroundStyle(.secondary)
                        Button("Escalar") { model.perform(ScaleToHeightCommand(height: Float(targetHeight))) }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("Apoyar en la cama", systemImage: "arrow.down.to.line") { model.perform(PlaceOnBedCommand()) }
                    Button("Subdividir (más detalle)", systemImage: "square.grid.3x3") { model.subdivide() }
                    HStack {
                        Text("Girar 90°")
                        Spacer()
                        Button("X") { model.perform(RotateCommand(axis: .x)) }
                        Button("Y") { model.perform(RotateCommand(axis: .y)) }
                        Button("Z") { model.perform(RotateCommand(axis: .z)) }
                    }
                    .buttonStyle(.bordered)
                    Button("Soldar vértices", systemImage: "link") { model.perform(WeldCommand()) }
                    Button("Invertir normales", systemImage: "arrow.triangle.2.circlepath") { model.perform(FlipNormalsCommand()) }
                }
            }
            .navigationTitle("Modelo")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
