import Solid
import SwiftUI

/// Panel inferior del modo texto.
struct TextPanel: View {
    @ObservedObject var model: EditorModel
    @FocusState private var editing: Bool

    var body: some View {
        VStack(spacing: 10) {
            Picker("Tipo", selection: $model.textEngrave) {
                Text("En relieve").tag(false)
                Text("Grabado").tag(true)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                TextField("Texto", text: $model.textContent)
                    .textFieldStyle(.roundedBorder)
                    .focused($editing)
                    .submitLabel(.done)
                Picker("Fuente", selection: $model.textFont) {
                    ForEach(TextFont.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }

            HStack(spacing: 8) {
                MMField(label: "Alto letras", value: $model.textHeight, minimum: 2, editing: $editing)
                MMField(label: model.textEngrave ? "Profundidad" : "Relieve",
                        value: $model.textDepth, minimum: 0.2, editing: $editing)
            }

            HStack(spacing: 8) {
                Image(systemName: "rotate.right")
                    .frame(width: 20)
                Slider(value: $model.textRotation, in: -180...180, step: 1)
                Text("\(Int(model.textRotation))°")
                    .font(.caption.monospacedDigit())
                    .frame(width: 44, alignment: .trailing)
            }

            Text("Toca el modelo donde quieras el texto. Funciona mejor sobre zonas planas o poco curvas.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Button("Cancelar") { model.mode = .view }
                    .buttonStyle(.bordered)
                Spacer()
                Button(model.textEngrave ? "Grabar" : "Añadir", systemImage: "textformat") { model.applyText() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.textShape?.outline.isEmpty ?? true)
            }
            .disabled(model.busyMessage != nil)
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
}
