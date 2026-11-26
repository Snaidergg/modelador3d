import Geometry
import Solid
import SwiftUI

/// Calidad de las operaciones con vóxeles: vóxeles a lo largo de la dimensión mayor.
enum VoxelQuality: String, CaseIterable, Identifiable {
    case draft, normal, high
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .draft: "Rápida"
        case .normal: "Normal"
        case .high: "Alta"
        }
    }
    var resolution: Int {
        switch self {
        case .draft: 128
        case .normal: 192
        case .high: 288
        }
    }
}

/// Panel inferior del modo formas: elegir forma, medidas, posición y operación.
struct ShapePanel: View {
    @Binding var shape: ShapeSpec
    @Binding var operation: BooleanOperation
    @Binding var quality: VoxelQuality
    let modelBounds: BoundingBox
    let busy: Bool
    let onOperationChanged: (BooleanOperation) -> Void
    let onCancel: () -> Void
    let onApply: () -> Void

    @FocusState private var editing: Bool

    var body: some View {
        VStack(spacing: 10) {
            Picker("Operación", selection: Binding(get: { operation }, set: { onOperationChanged($0) })) {
                ForEach(BooleanOperation.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Forma", selection: $shape.kind) {
                ForEach(ShapeKind.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) { dimensionFields }

            if shape.kind == .cylinder || shape.kind == .cone {
                Picker("Eje", selection: $shape.axis) {
                    ForEach(ShapeAxis.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            positionSlider("X", value: $shape.center.x, axis: 0, reference: modelBounds.center.x)
            positionSlider("Y", value: $shape.center.y, axis: 1, reference: modelBounds.min.y)
            positionSlider("Z", value: $shape.center.z, axis: 2, reference: modelBounds.center.z)

            HStack {
                Picker("Calidad", selection: $quality) {
                    ForEach(VoxelQuality.allCases) { Text("Calidad \($0.displayName.lowercased())").tag($0) }
                }
                .pickerStyle(.menu)
                Spacer()
                Button("Cancelar", action: onCancel)
                    .buttonStyle(.bordered)
                Button(operation.displayName, systemImage: "checkmark", action: onApply)
                    .buttonStyle(.borderedProminent)
            }
            .disabled(busy)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") { editing = false }
            }
        }
    }

    @ViewBuilder
    private var dimensionFields: some View {
        switch shape.kind {
        case .box:
            MMField(label: "Ancho X", value: $shape.width, editing: $editing)
            MMField(label: "Alto Y", value: $shape.height, editing: $editing)
            MMField(label: "Fondo Z", value: $shape.depth, editing: $editing)
        case .cylinder:
            MMField(label: "Diámetro", value: $shape.width, editing: $editing)
            MMField(label: "Alto", value: $shape.height, editing: $editing)
        case .cone:
            MMField(label: "Ø base", value: $shape.width, editing: $editing)
            MMField(label: "Ø arriba", value: $shape.topDiameter, minimum: 0, editing: $editing)
            MMField(label: "Alto", value: $shape.height, editing: $editing)
        case .sphere:
            MMField(label: "Diámetro", value: $shape.width, editing: $editing)
        }
    }

    /// Deslizador de posición; el valor se muestra respecto al centro del modelo (X, Z) o a la cama (Y).
    private func positionSlider(_ name: String, value: Binding<Float>, axis: Int, reference: Float) -> some View {
        let reach = Swift.max(shape.width, Swift.max(shape.height, shape.depth)) + 5
        let lo = modelBounds.min[axis] - reach
        let hi = Swift.max(modelBounds.max[axis] + reach, lo + 1)
        return HStack(spacing: 8) {
            Text(name)
                .font(.caption.bold())
                .frame(width: 14)
            Slider(value: value, in: lo...hi)
            Text("\(Format.mm(value.wrappedValue - reference)) mm")
                .font(.caption.monospacedDigit())
                .frame(width: 64, alignment: .trailing)
        }
    }
}

/// Campo numérico en milímetros.
struct MMField: View {
    let label: String
    @Binding var value: Float
    var minimum: Float = 0.1
    var editing: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(label) (mm)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField(label,
                      value: Binding(get: { Double(value) }, set: { value = Swift.max(Float($0), minimum) }),
                      format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .focused(editing)
        }
    }
}
