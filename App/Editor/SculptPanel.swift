import Sculpt
import SwiftUI

/// Barra inferior del modo esculpir: pincel, tamaño, intensidad, invertir y simetría.
struct SculptPanel: View {
    @Binding var settings: SculptSettings
    let triangleCount: Int
    let onSubdivide: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(BrushKind.allCases) { brush in
                        Button {
                            settings.brush = brush
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: brush.systemImage)
                                    .font(.title3)
                                Text(brush.displayName)
                                    .font(.caption2)
                            }
                            .frame(width: 66, height: 50)
                            .background(settings.brush == brush ? Color.accentColor.opacity(0.28) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "circle.dashed")
                    .frame(width: 20)
                Slider(value: $settings.radius, in: 10...150)
                Text("\(Int(settings.radius))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 34, alignment: .trailing)
            }

            HStack(spacing: 10) {
                Image(systemName: "bolt")
                    .frame(width: 20)
                Slider(value: $settings.strength, in: 0.05...1)
                Text("\(Int(settings.strength * 100)) %")
                    .font(.caption.monospacedDigit())
                    .frame(width: 34, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Toggle(isOn: $settings.invert) {
                    Label("Hundir", systemImage: "minus.circle")
                }
                .toggleStyle(.button)
                .disabled(!settings.brush.supportsInvert)

                Toggle(isOn: $settings.symmetryX) {
                    Label("Simetría", systemImage: "arrow.left.and.right")
                }
                .toggleStyle(.button)

                Spacer()

                Button(action: onSubdivide) {
                    Label("Más detalle", systemImage: "square.grid.3x3")
                }
                .buttonStyle(.bordered)
                .help("Subdivide la malla: \(triangleCount.formatted()) → \((triangleCount * 4).formatted()) triángulos")
            }
            .font(.footnote)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }
}
