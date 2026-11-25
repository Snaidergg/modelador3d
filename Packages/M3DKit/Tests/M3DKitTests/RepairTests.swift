import simd
import XCTest
import Geometry
@testable import PrintPrep

final class RepairTests: XCTestCase {
    func testCutKeepAboveAndCapGivesClosedHalfSphere() {
        let sphere = Mesh.icosphere(radius: 10, subdivisions: 4)
        let cut = MeshRepair.cut(sphere, planeY: 0.37, keepAbove: true)
        XCTAssertFalse(MeshAnalyzer.analyze(cut).isWatertight, "antes de tapar hay un agujero")

        let capped = MeshRepair.fillHoles(cut)
        let report = MeshAnalyzer.analyze(capped)
        XCTAssertTrue(report.isWatertight)
        XCTAssertGreaterThan(report.volume, 0)
        // Casquete esférico de altura h = 10 - 0,37: V = π h² (3r - h) / 3
        let h: Float = 10 - 0.37
        let expected = Float.pi * h * h * (30 - h) / 3
        XCTAssertEqual(report.volume, expected, accuracy: expected * 0.03)
        XCTAssertEqual(capped.bounds.min.y, 0.37, accuracy: 1e-4)
    }

    func testCutKeepBelow() {
        let sphere = Mesh.icosphere(radius: 10, subdivisions: 3)
        let capped = MeshRepair.fillHoles(MeshRepair.cut(sphere, planeY: -2.5, keepAbove: false))
        XCTAssertTrue(MeshAnalyzer.analyze(capped).isWatertight)
        XCTAssertEqual(capped.bounds.max.y, -2.5, accuracy: 1e-4)
    }

    func testCutThroughVerticesOnThePlane() {
        // El ecuador de la icosfera tiene vértices exactamente en Y = 0.
        let sphere = Mesh.icosphere(radius: 10, subdivisions: 3)
        let capped = MeshRepair.fillHoles(MeshRepair.cut(sphere, planeY: 0, keepAbove: true))
        XCTAssertTrue(MeshAnalyzer.analyze(capped).isWatertight)
    }

    func testFillHoleInBox() {
        var box = Mesh.box(size: SIMD3<Float>(10, 20, 30))
        box.triangles.removeLast(2) // quitar una cara entera
        XCTAssertFalse(MeshAnalyzer.analyze(box).isWatertight)
        let report = MeshAnalyzer.analyze(MeshRepair.fillHoles(box))
        XCTAssertTrue(report.isWatertight)
        XCTAssertEqual(report.volume, 6000, accuracy: 0.05)
    }

    func testConcavePolygonIsTriangulatedWithoutExtraVertices() {
        // Contorno en forma de "L" (cóncavo): 6 vértices → 4 triángulos, sin abanico desde el centro.
        let points: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(20, 0, 0), SIMD3(20, 0, 10),
            SIMD3(10, 0, 10), SIMD3(10, 0, 20), SIMD3(0, 0, 20),
        ]
        let triangles = MeshRepair.earClip([0, 1, 2, 3, 4, 5], positions: points)
        XCTAssertEqual(triangles?.count, 4)
        // El área total debe ser la de la L: 20×10 + 10×10 = 300.
        let area = (triangles ?? []).reduce(Float(0)) { sum, t in
            let a = points[Int(t.x)], b = points[Int(t.y)], c = points[Int(t.z)]
            return sum + simd_length(simd_cross(b - a, c - a)) / 2
        }
        XCTAssertEqual(area, 300, accuracy: 0.01)
    }

    func testRemoveSmallPieces() {
        let sphere = Mesh.icosphere(radius: 10, subdivisions: 3)
        let crumb = Mesh.box(size: SIMD3<Float>(1, 1, 1)).translated(by: SIMD3<Float>(30, 0, 0))
        var combined = sphere
        let offset = UInt32(combined.positions.count)
        combined.positions += crumb.positions
        combined.triangles += crumb.triangles.map { $0 &+ SIMD3<UInt32>(repeating: offset) }
        XCTAssertEqual(MeshRepair.pieceCount(combined), 2)

        let cleaned = MeshRepair.removeSmallPieces(combined)
        XCTAssertEqual(MeshRepair.pieceCount(cleaned), 1)
        XCTAssertEqual(cleaned.triangleCount, sphere.triangleCount)
        XCTAssertEqual(cleaned.vertexCount, sphere.vertexCount, "los vértices sin usar se eliminan")
    }
}
