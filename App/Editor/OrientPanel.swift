import SwiftUI

/// Panel inferior del modo orientar: tocar una cara para apoyarla e inclinar en pasos finos.
struct OrientPanel: View {
    let onTilt: (RotateCommand.Axis, Float) -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Orientar")
                .font(.headline)

            Text("Toca una zona plana del modelo (por ejemplo, la base) para apoyarla sobre la cama azul.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            tiltRow("Inclinar adelante/atrás", axis: .x)
            tiltRow("Inclinar a los lados", axis: .z)
            tiltRow("Girar sobre la cama", axis: .y)

            HStack {
                Text("Cada paso se deshace con ↩︎.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Listo", systemImage: "checkmark", action: onDone)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private func tiltRow(_ title: String, axis: RotateCommand.Axis) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            ForEach([Float(-5), -1, 1, 5], id: \.self) { step in
                Button(step > 0 ? "+\(Int(step))°" : "\(Int(step))°") { onTilt(axis, step) }
                    .font(.caption.monospacedDigit())
                    .buttonStyle(.bordered)
            }
        }
    }
}
