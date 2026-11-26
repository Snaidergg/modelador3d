import simd
import XCTest
import Geometry
import PrintPrep
@testable import Solid

final class TextAndSimplifyTests: XCTestCase {
    func testSimplifyKeepsClosedShapeAndVolume() {
        let sphere = Mesh.icosphere(radius: 20, subdivisions: 5) // 20 480 triángulos
        let simple = MeshSimplifier.simplify(sphere, targetTriangles: 2000)
        let report = MeshAnalyzer.analyze(simple)
        XCTAssertLessThanOrEqual(simple.triangleCount, 2000)
        XCTAssertGreaterThan(simple.triangleCount, 1000)
        XCTAssertTrue(report.isWatertight)
        let expected = MeshAnalyzer.analyze(sphere).volume
        XCTAssertEqual(report.volume, expected, accuracy: expected * 0.03)
    }

    func testSimplifyDoesNothingWhenAlreadySmall() {
        let box = Mesh.box(size: SIMD3<Float>(10, 10, 10))
        XCTAssertEqual(MeshSimplifier.simplify(box, targetTriangles: 100), box)
    }

    func testTextOutlineSizeAndAccents() {
        let outline = TextOutline.make("Hola", font: .bold, height: 10)
        XCTAssertFalse(outline.isEmpty)
        XCTAssertEqual(outline.size.y, 10, accuracy: 0.01)
        XCTAssertGreaterThan(outline.size.x, 15)
        // Letras con tilde y eñe también tienen contorno.
        XCTAssertFalse(TextOutline.make("Año", font: .serif, height: 8).isEmpty)
        XCTAssertTrue(TextOutline.make("   ", font: .bold, height: 8).isEmpty)
    }

    func testTextSignedDistance() {
        let outline = TextOutline.make("I", font: .bold, height: 10)
        let text = TextShape(outline: outline, anchor: .zero, normal: SIMD3(0, 0, 1), bottom: -1, top: 1)
        XCTAssertLessThan(text.signedDistance(SIMD3(0, 0, 0)), 0, "el centro de la I está dentro")
        XCTAssertEqual(text.signedDistance(SIMD3(0, 0, 4)), 3, accuracy: 0.01)
        XCTAssertGreaterThan(text.signedDistance(SIMD3(30, 0, 0)), 20)
        // La I es más alta que ancha y queda vertical (eje Y del modelo).
        XCTAssertGreaterThan(text.bounds.size.y, text.bounds.size.x)
    }

    func testEngraveAndEmbossTextOnABox() throws {
        let box = Mesh.box(size: SIMD3<Float>(40, 20, 10))
        let outline = TextOutline.make("AB", font: .bold, height: 10)

        let engraveShape = TextShape(outline: outline, anchor: SIMD3(0, 0, 5), normal: SIMD3(0, 0, 1),
                                     bottom: -1, top: 1)
        let engraved = try VoxelCSG.combine(box, with: engraveShape, operation: .subtract,
                                            resolution: 128, spacing: 10.0 / 18)
        let engravedReport = MeshAnalyzer.analyze(engraved)
        XCTAssertTrue(engravedReport.isWatertight)
        XCTAssertLessThan(engravedReport.volume, 8000 - 20, "se quitó material")
        XCTAssertGreaterThan(engravedReport.volume, 8000 - 400)

        let embossShape = TextShape(outline: outline, anchor: SIMD3(0, 0, 5), normal: SIMD3(0, 0, 1),
                                    bottom: -0.6, top: 1.5)
        let embossed = try VoxelCSG.combine(box, with: embossShape, operation: .union,
                                            resolution: 128, spacing: 10.0 / 18)
        let embossedReport = MeshAnalyzer.analyze(embossed)
        XCTAssertTrue(embossedReport.isWatertight)
        XCTAssertGreaterThan(embossedReport.volume, 8000 + 30, "se añadió material")
        XCTAssertEqual(MeshRepair.pieceCount(embossed), 1, "las letras quedan unidas a la caja")

        // Y el simplificador lo deja cerrado.
        let simple = MeshSimplifier.simplify(embossed, targetTriangles: embossed.triangleCount / 4)
        XCTAssertTrue(MeshAnalyzer.analyze(simple).isWatertight)
    }
}
