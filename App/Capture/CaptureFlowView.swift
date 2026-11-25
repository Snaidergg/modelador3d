import Geometry
import PhotosUI
import RealityKit
import SwiftUI

/// Pantalla completa de captura: elegir modo → capturar → reconstruir → volver al editor.
struct CaptureFlowView: View {
    let onFinished: (Mesh) -> Void

    @StateObject private var capture = CaptureModel()
    @Environment(\.dismiss) private var dismiss
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var videoItem: PhotosPickerItem?

    var body: some View {
        Group {
            switch capture.phase {
            case .intro:
                intro
            case .scanning:
                if let session = capture.scanSession {
                    ScanView(capture: capture, session: session)
                } else {
                    ProgressView()
                }
            case .preparing(let message, let progress):
                ProgressScreen(title: message, progress: progress,
                               detail: nil, onCancel: { capture.cancel() })
            case .reconstructing(let progress):
                ProgressScreen(title: "Creando el modelo 3D…", progress: progress,
                               detail: "Puede tardar varios minutos. Mantén la app abierta; la pantalla no se apagará.",
                               onCancel: { capture.cancel() })
            case .failed(let message):
                FailureScreen(message: message, onBack: { capture.dismissError() })
            }
        }
        .onAppear {
            capture.onFinished = { mesh in
                onFinished(mesh)
                dismiss()
            }
        }
        .onDisappear { capture.cancel() }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            capture.startFromPhotos(items)
            photoItems = []
        }
        .onChange(of: videoItem) { _, item in
            guard let item else { return }
            capture.startFromVideo(item)
            videoItem = nil
        }
    }

    private var intro: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        capture.startScan()
                    } label: {
                        ModeRow(icon: "viewfinder", title: "Escanear con la cámara",
                                subtitle: "Rodeas el objeto y la app toma las fotos sola. El más preciso.")
                    }
                    .disabled(!CaptureModel.scanSupported)

                    PhotosPicker(selection: $photoItems, maxSelectionCount: 200, matching: .images) {
                        ModeRow(icon: "photo.stack", title: "Desde fotos",
                                subtitle: "Elige entre 40 y 80 fotos tomadas alrededor del objeto.")
                    }

                    PhotosPicker(selection: $videoItem, matching: .videos) {
                        ModeRow(icon: "video", title: "Desde un video",
                                subtitle: "Un video rodeando el objeto despacio, de 20 a 40 segundos.")
                    }
                } footer: {
                    if !CaptureModel.reconstructionSupported {
                        Text("Este dispositivo no admite la reconstrucción 3D.")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Consejos para un buen resultado") {
                    Tip(icon: "sun.max", text: "Luz uniforme y difusa, sin sombras fuertes ni contraluz.")
                    Tip(icon: "square.on.square.dashed", text: "Objeto con textura o detalles. Los brillantes, transparentes o de un solo color liso salen mal.")
                    Tip(icon: "arrow.triangle.2.circlepath", text: "Rodea el objeto completo a dos o tres alturas distintas.")
                    Tip(icon: "rectangle.dashed", text: "Fondo despejado y el objeto ocupando buena parte de la imagen.")
                    Tip(icon: "hand.raised", text: "No muevas el objeto durante la captura (salvo al voltearlo cuando la app lo pida).")
                }
            }
            .navigationTitle("Capturar objeto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Escaneo guiado

private struct ScanView: View {
    @ObservedObject var capture: CaptureModel
    let session: ObjectCaptureSession

    var body: some View {
        ZStack {
            ObjectCaptureView(session: session)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                HStack {
                    Button("Cancelar") { capture.cancel() }
                        .buttonStyle(.bordered)
                    Spacer()
                    Label("\(capture.shots)", systemImage: "camera")
                        .font(.headline.monospacedDigit())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }

                ForEach(capture.feedback, id: \.self) { message in
                    Text(message)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.orange.opacity(0.85), in: Capsule())
                        .foregroundStyle(.white)
                }

                Spacer()

                Text(hint)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

                controls
            }
            .padding()
        }
    }

    private var hint: String {
        switch capture.scanStep {
        case .initializing: return "Preparando la cámara…"
        case .ready: return "Apunta al objeto y déjalo en el centro de la pantalla."
        case .detecting: return "Ajusta la caja para que envuelva todo el objeto (puedes arrastrar sus bordes)."
        case .capturing:
            return capture.passCompleted
                ? "¡Vuelta completa! Haz otra a distinta altura, voltea el objeto para captar la base, o termina."
                : "Camina despacio alrededor del objeto. El anillo se llena a medida que se toman fotos."
        case .finishing: return "Guardando las fotos…"
        case .completed: return "Listo. Preparando la reconstrucción…"
        case .failed: return "El escaneo falló."
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch capture.scanStep {
        case .ready:
            Button("Continuar") { capture.startDetecting() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .detecting:
            Button("Empezar a capturar") { capture.startCapturing() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .capturing:
            if capture.passCompleted {
                HStack {
                    Button("Otra vuelta") { capture.newPass() }
                    Button("Voltear objeto") { capture.newPassAfterFlip() }
                    Button("Terminar") { capture.finishScan() }
                        .buttonStyle(.borderedProminent)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else if capture.shots >= CaptureModel.minimumImages {
                Button("Terminar ahora") { capture.finishScan() }
                    .buttonStyle(.bordered)
            }
        case .initializing, .finishing, .completed:
            ProgressView()
        case .failed:
            EmptyView()
        }
    }
}

// MARK: - Piezas de interfaz

private struct ModeRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 36)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct Tip: View {
    let icon: String
    let text: String

    var body: some View {
        Label {
            Text(text).font(.footnote)
        } icon: {
            Image(systemName: icon).foregroundStyle(.secondary)
        }
    }
}

private struct ProgressScreen: View {
    let title: String
    let progress: Double
    let detail: String?
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(title).font(.title3.weight(.semibold))
            ProgressView(value: min(max(progress, 0), 1))
                .padding(.horizontal, 40)
            Text("\(Int((min(max(progress, 0), 1)) * 100)) %")
                .font(.headline.monospacedDigit())
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            Button("Cancelar", role: .cancel, action: onCancel)
                .buttonStyle(.bordered)
                .padding(.bottom, 30)
        }
    }
}

private struct FailureScreen: View {
    let message: String
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
            Button("Volver", action: onBack)
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 30)
        }
    }
}
