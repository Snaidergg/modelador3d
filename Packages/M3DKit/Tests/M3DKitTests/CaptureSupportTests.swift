import Foundation
import simd
import XCTest
import Geometry
import MeshIO
import PrintPrep

final class CaptureSupportTests: XCTestCase {
    func testRotationKeepsVolumeAndOrientation() {
        let box = Mesh.box(size: SIMD3<Float>(10, 20, 30))
        let rotated = box.rotated(degrees: 90, axis: SIMD3<Float>(1, 0, 0))
        let report = MeshAnalyzer.analyze(rotated)
        XCTAssertEqual(report.volume, 6000, accuracy: 0.05)
        XCTAssertTrue(report.isWatertight)
        // Girar 90° en X intercambia alto (Y) y fondo (Z).
        XCTAssertEqual(rotated.bounds.size.y, 30, accuracy: 1e-3)
        XCTAssertEqual(rotated.bounds.size.z, 20, accuracy: 1e-3)
    }

    #if canImport(ModelIO)
    func testModelIOReaderLoadsTriangles() throws {
        let box = Mesh.box(size: SIMD3<Float>(10, 20, 30))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("obj")
        try OBJFormat.export(box).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = try ModelIOFormat.load(url: url, scale: 1)
        XCTAssertEqual(loaded.triangleCount, 12)
        XCTAssertEqual(abs(MeshAnalyzer.analyze(loaded).volume), 6000, accuracy: 0.05)
    }

    func testModelIOAssumesMetersForSmallModels() throws {
        // Una caja de 0,05 unidades se interpreta como metros → 50 mm.
        let box = Mesh.box(size: SIMD3<Float>(0.05, 0.05, 0.05))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("obj")
        try OBJFormat.export(box).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = try ModelIOFormat.load(url: url)
        XCTAssertEqual(loaded.bounds.size.x, 50, accuracy: 0.01)
    }
    #endif
}
