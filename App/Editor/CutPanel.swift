import SwiftUI

/// Panel inferior del modo recorte: mover el plano y elegir qué lado conservar.
struct CutPanel: View {
    @Binding var height: Float
    @Binding var keepAbove: Bool
    let range: ClosedRange<Float>
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Recortar con plano")
                .font(.headline)

            HStack(spacing: 10) {
                Image(systemName: "arrow.up.and.down")
                    .frame(width: 20)
                Slider(value: $height, in: range)
                Text("\(Format.mm(height - range.lowerBound)) mm")
                    .font(.caption.monospacedDigit())
                    .frame(width: 64, alignment: .trailing)
            }

            Picker("Conservar", selection: $keepAbove) {
                Text("Conservar arriba").tag(true)
                Text("Conservar abajo").tag(false)
            }
            .pickerStyle(.segmented)

            Text("Se elimina lo que queda al otro lado del plano rojo y el corte se tapa automáticamente.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Button("Cancelar", action: onCancel)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Recortar", systemImage: "scissors", action: onApply)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }
}
