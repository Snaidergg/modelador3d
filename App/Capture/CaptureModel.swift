import AVFoundation
import Foundation
import Geometry
import MeshIO
import PhotosUI
import RealityKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Carpeta de trabajo de una captura: fotos, punto de control y modelo resultante.
struct CaptureFolder {
    let root: URL
    var images: URL { root.appendingPathComponent("Fotos", isDirectory: true) }
    var checkpoint: URL { root.appendingPathComponent("Checkpoint", isDirectory: true) }
    var model: URL { root.appendingPathComponent("modelo.usdz") }

    /// Se guarda en Documentos/Capturas, visible desde la app Archivos.
    static func create() throws -> CaptureFolder {
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let root = documents
            .appendingPathComponent("Capturas", isDirectory: true)
            .appendingPathComponent(formatter.string(from: Date()), isDirectory: true)
        let folder = CaptureFolder(root: root)
        try FileManager.default.createDirectory(at: folder.images, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.checkpoint, withIntermediateDirectories: true)
        return folder
    }

    /// Borra las fotos y datos intermedios (pueden ocupar cientos de MB) y conserva el modelo.
    func removeIntermediates() {
        try? FileManager.default.removeItem(at: images)
        try? FileManager.default.removeItem(at: checkpoint)
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// Video elegido de la fototeca, copiado a una carpeta temporal.
struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedVideo(url: destination)
        }
    }
}

/// Flujo de captura: escaneo guiado, fotos o video → reconstrucción en el iPhone → malla.
@MainActor
final class CaptureModel: ObservableObject {
    enum Phase {
        case intro
        case scanning
        case preparing(String, Double)
        case reconstructing(Double)
        case failed(String)
    }

    /// Estado del escaneo guiado, simplificado para la interfaz.
    enum ScanStep {
        case initializing, ready, detecting, capturing, finishing, completed, failed
    }

    static let minimumImages = 20

    static var scanSupported: Bool { ObjectCaptureSession.isSupported }
    static var reconstructionSupported: Bool { PhotogrammetrySession.isSupported }

    @Published private(set) var phase: Phase = .intro
    @Published private(set) var scanStep: ScanStep = .initializing
    @Published private(set) var feedback: [String] = []
    @Published private(set) var shots = 0
    @Published private(set) var passCompleted = false

    private(set) var scanSession: ObjectCaptureSession?
    private var photogrammetry: PhotogrammetrySession?
    private var folder: CaptureFolder?
    private var work: Task<Void, Never>?
    private var polling: Task<Void, Never>?

    var onFinished: (@MainActor (Mesh) -> Void)?

    // MARK: Escaneo guiado (Object Capture)

    func startScan() {
        guard CaptureModel.scanSupported else {
            phase = .failed("Este iPhone no admite el escaneo guiado (requiere LiDAR).")
            return
        }
        do {
            let folder = try CaptureFolder.create()
            self.folder = folder
            let session = ObjectCaptureSession()
            var configuration = ObjectCaptureSession.Configuration()
            configuration.checkpointDirectory = folder.checkpoint
            try session.start(imagesDirectory: folder.images, configuration: configuration)
            scanSession = session
            scanStep = .initializing
            shots = 0
            passCompleted = false
            feedback = []
            phase = .scanning
            startPolling()
        } catch {
            phase = .failed("No se pudo preparar la carpeta de la captura: \(error.localizedDescription)")
        }
    }

    // `try?` no hace daño si estos métodos no lanzan errores en esta versión de iOS.
    func startDetecting() { _ = try? scanSession?.startDetecting() }
    func startCapturing() { _ = try? scanSession?.startCapturing() }
    func newPass() { _ = try? scanSession?.beginNewScanPass() }
    func newPassAfterFlip() { _ = try? scanSession?.beginNewScanPassAfterFlip() }
    func finishScan() { _ = try? scanSession?.finish() }

    /// Lee el estado de la sesión cada pocos milisegundos (más robusto que depender de su API de observación).
    private func startPolling() {
        polling?.cancel()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshScan()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func refreshScan() {
        guard let session = scanSession else { return }
        shots = session.numberOfShotsTaken
        passCompleted = session.userCompletedScanPass
        feedback = session.feedback.map { CaptureModel.describe(feedback: String(describing: $0)) }.sorted()

        let state = String(describing: session.state)
        if state.hasPrefix("ready") { scanStep = .ready }
        else if state.hasPrefix("detecting") { scanStep = .detecting }
        else if state.hasPrefix("capturing") { scanStep = .capturing }
        else if state.hasPrefix("finishing") { scanStep = .finishing }
        else if state.hasPrefix("completed") {
            scanStep = .completed
            polling?.cancel()
            scanSession = nil // la sesión de cámara debe cerrarse antes de reconstruir
            if let folder { reconstruct(folder) }
        } else if state.hasPrefix("failed") {
            scanStep = .failed
            polling?.cancel()
            scanSession = nil
            phase = .failed("El escaneo falló: \(state)")
        } else {
            scanStep = .initializing
        }
    }

    private static func describe(feedback raw: String) -> String {
        switch raw {
        case "objectTooClose": return "Aléjate un poco del objeto"
        case "objectTooFar": return "Acércate al objeto"
        case "movingTooFast": return "Muévete más despacio"
        case "environmentLowLight": return "Hay poca luz"
        case "environmentTooDark": return "Está demasiado oscuro"
        case "outOfFieldOfView": return "Mantén el objeto en la pantalla"
        case "objectNotFlippable": return "Este objeto no conviene voltearlo"
        case "overCapturing": return "Ya hay suficientes fotos de esta zona"
        case "objectNotDetected": return "No se detecta el objeto"
        default: return raw
        }
    }

    // MARK: Desde fotos

    func startFromPhotos(_ items: [PhotosPickerItem]) {
        guard items.count >= CaptureModel.minimumImages else {
            phase = .failed("Elegiste \(items.count) fotos. Hacen falta al menos \(CaptureModel.minimumImages) "
                + "(lo ideal son 40–80) tomadas alrededor del objeto.")
            return
        }
        work?.cancel()
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let folder = try CaptureFolder.create()
                self.folder = folder
                var saved = 0
                for (index, item) in items.enumerated() {
                    try Task.checkCancellation()
                    self.phase = .preparing("Copiando fotos…", Double(index) / Double(items.count))
                    guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                    let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                    let name = String(format: "foto_%04d.%@", index, ext)
                    try data.write(to: folder.images.appendingPathComponent(name))
                    saved += 1
                }
                guard saved >= CaptureModel.minimumImages else {
                    throw CaptureError.message("Solo se pudieron leer \(saved) fotos.")
                }
                self.reconstruct(folder)
            } catch is CancellationError {
                self.phase = .intro
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: Desde video

    func startFromVideo(_ item: PhotosPickerItem) {
        work?.cancel()
        work = Task { [weak self] in
            guard let self else { return }
            do {
                self.phase = .preparing("Cargando video…", 0)
                guard let video = try await item.loadTransferable(type: PickedVideo.self) else {
                    throw CaptureError.message("No se pudo leer el video.")
                }
                defer { try? FileManager.default.removeItem(at: video.url) }
                let folder = try CaptureFolder.create()
                self.folder = folder
                try await self.extractFrames(from: video.url, to: folder.images)
                self.reconstruct(folder)
            } catch is CancellationError {
                self.phase = .intro
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Extrae fotogramas repartidos por todo el video (3 por segundo, entre 20 y 120).
    private func extractFrames(from url: URL, to directory: URL) async throws {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 1 else {
            throw CaptureError.message("El video es demasiado corto.")
        }
        let count = Int(min(120, max(Double(CaptureModel.minimumImages), duration * 3)))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let tolerance = CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        for i in 0..<count {
            try Task.checkCancellation()
            phase = .preparing("Extrayendo fotogramas del video…", Double(i) / Double(count))
            let time = CMTime(seconds: duration * (Double(i) + 0.5) / Double(count), preferredTimescale: 600)
            let frame = try await generator.image(at: time).image
            guard let data = UIImage(cgImage: frame).jpegData(compressionQuality: 0.92) else { continue }
            try data.write(to: directory.appendingPathComponent(String(format: "fotograma_%04d.jpg", i)))
        }
    }

    // MARK: Reconstrucción (fotogrametría en el iPhone)

    private func reconstruct(_ folder: CaptureFolder) {
        work?.cancel()
        work = Task { [weak self] in
            guard let self else { return }
            self.phase = .reconstructing(0)
            UIApplication.shared.isIdleTimerDisabled = true
            defer {
                UIApplication.shared.isIdleTimerDisabled = false
                self.photogrammetry = nil
            }
            do {
                guard CaptureModel.reconstructionSupported else {
                    throw CaptureError.message("Este iPhone no admite la reconstrucción 3D.")
                }
                var configuration = PhotogrammetrySession.Configuration()
                configuration.checkpointDirectory = folder.checkpoint
                let session = try PhotogrammetrySession(input: folder.images, configuration: configuration)
                self.photogrammetry = session
                try session.process(requests: [.modelFile(url: folder.model, detail: .reduced)])

                var produced: URL?
                for try await output in session.outputs {
                    switch output {
                    case .requestProgress(_, let fraction):
                        self.phase = .reconstructing(fraction)
                    case .requestComplete(_, let result):
                        if case .modelFile(let url) = result { produced = url }
                    case .requestError(_, let error):
                        throw error
                    case .processingCancelled:
                        throw CancellationError()
                    default:
                        break
                    }
                }

                guard let produced else { throw CaptureError.message("La reconstrucción no produjo un modelo.") }
                self.phase = .preparing("Abriendo el modelo…", 1)
                let mesh = try ModelIOFormat.load(url: produced, scale: 1000).recentered()
                folder.removeIntermediates()
                self.phase = .intro
                self.onFinished?(mesh)
            } catch is CancellationError {
                folder.removeAll()
                self.phase = .intro
            } catch {
                self.phase = .failed("No se pudo reconstruir el modelo: \(error.localizedDescription)\n\n"
                    + "Consejos: más fotos, mejor luz y un objeto con textura (no brillante ni transparente).")
            }
        }
    }

    // MARK: Cancelar

    func cancel() {
        polling?.cancel()
        scanSession?.cancel()
        scanSession = nil
        photogrammetry?.cancel()
        work?.cancel()
        if case .scanning = phase { folder?.removeAll() }
        phase = .intro
    }

    func dismissError() {
        phase = .intro
    }
}

enum CaptureError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}
