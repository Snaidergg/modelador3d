import simd
import XCTest
import Geometry
import PrintPrep
@testable import Solid

final class SolidTests: XCTestCase {
    func testCylinderAndConeMeshesAreClosed() {
        let cylinder = Mesh.cylinder(radius: 10, height: 20)
        let report = MeshAnalyzer.analyze(cylinder)
        XCTAssertTrue(report.isWatertight)
        let expected = Float.pi * 100 * 20
        XCTAssertEqual(report.volume, expected, accuracy: expected * 0.01)

        let cone = Mesh.frustum(bottomRadius: 10, topRadius: 0, height: 30)
        let coneReport = MeshAnalyzer.analyze(cone)
        XCTAssertTrue(coneReport.isWatertight)
        XCTAssertEqual(coneReport.volume, expected / 2, accuracy: expected * 0.01) // π r² h / 3 = 1000π
    }

    func testShapeSignedDistance() {
        var box = ShapeSpec()
        box.kind = .box
        box.width = 10; box.height = 20; box.depth = 30
        XCTAssertEqual(box.signedDistance(SIMD3(0, 0, 0)), -5, accuracy: 1e-5)
        XCTAssertEqual(box.signedDistance(SIMD3(8, 0, 0)), 3, accuracy: 1e-5)

        var cylinder = ShapeSpec()
        cylinder.kind = .cylinder
        cylinder.width = 10; cylinder.height = 20
        cylinder.center = SIMD3(1, 2, 3)
        XCTAssertLessThan(cylinder.signedDistance(SIMD3(1, 2, 3)), 0)
        XCTAssertEqual(cylinder.signedDistance(SIMD3(1 + 7, 2, 3)), 2, accuracy: 1e-4)
        XCTAssertEqual(cylinder.signedDistance(SIMD3(1, 2 + 13, 3)), 3, accuracy: 1e-4)

        // Cilindro tumbado a lo largo de X: 20 mm de largo en X.
        cylinder.axis = .x
        XCTAssertEqual(cylinder.signedDistance(SIMD3(1 + 13, 2, 3)), 3, accuracy: 1e-4)
        XCTAssertEqual(cylinder.bounds.size.x, 20, accuracy: 1e-3)

        var cone = ShapeSpec()
        cone.kind = .cone
        cone.width = 20; cone.height = 10; cone.topDiameter = 0
        XCTAssertLessThan(cone.signedDistance(SIMD3(0, -4, 0)), 0)
        XCTAssertGreaterThan(cone.signedDistance(SIMD3(9, 4, 0)), 0) // cerca de la punta, fuera
    }

    func testRemeshKeepsSphereClosedAndRound() throws {
        let sphere = Mesh.icosphere(radius: 10, subdivisions: 3)
        let remeshed = try VoxelCSG.remesh(sphere, resolution: 40)
        let report = MeshAnalyzer.analyze(remeshed)
        XCTAssertTrue(report.isWatertight)
        let expected = MeshAnalyzer.analyze(sphere).volume
        XCTAssertEqual(report.volume, expected, accuracy: expected * 0.03)
    }

    func testSubtractCylinderMakesAHole() throws {
        let box = Mesh.box(size: SIMD3<Float>(20, 20, 20))
        var hole = ShapeSpec()
        hole.kind = .cylinder
        hole.width = 8; hole.height = 30
        let result = try VoxelCSG.combine(box, with: hole, operation: .subtract, resolution: 48)
        let report = MeshAnalyzer.analyze(result)
        XCTAssertTrue(report.isWatertight)
        let expected: Float = 8000 - .pi * 16 * 20
        XCTAssertEqual(report.volume, expected, accuracy: expected * 0.03)
        // Por el centro ya no hay material: un rayo vertical no toca la malla.
        XCTAssertNil(result.raycast(Ray(origin: SIMD3(0.1, 50, 0.2), direction: SIMD3(0, -1, 0))))
    }

    func testUnionAddsABase() throws {
        let sphere = Mesh.icosphere(radius: 10, subdivisions: 3)
        var base = ShapeSpec()
        base.kind = .cylinder
        base.width = 30; base.height = 4
        base.center = SIMD3(0, -11, 0) // se solapa 1 mm con la esfera
        let result = try VoxelCSG.combine(sphere, with: base, operation: .union, resolution: 48)
        let report = MeshAnalyzer.analyze(result)
        XCTAssertTrue(report.isWatertight)
        XCTAssertEqual(MeshRepairCount.pieces(result), 1, "la base queda unida a la esfera")
        XCTAssertEqual(result.bounds.size.x, 30, accuracy: 1.5)
        XCTAssertEqual(result.bounds.min.y, -13, accuracy: 0.6)
    }

    func testIntersectWithoutOverlapThrows() {
        let sphere = Mesh.icosphere(radius: 5, subdivisions: 2)
        var far = ShapeSpec()
        far.center = SIMD3(100, 0, 0)
        XCTAssertThrowsError(try VoxelCSG.combine(sphere, with: far, operation: .intersect, resolution: 32))
    }

    func testThickenOpenSurface() throws {
        var openBox = Mesh.box(size: SIMD3<Float>(20, 20, 20))
        openBox.triangles.removeLast(2) // sin tapa: como un vaso
        let solid = try VoxelCSG.thicken(openBox, thickness: 2, resolution: 40)
        let report = MeshAnalyzer.analyze(solid)
        XCTAssertTrue(report.isWatertight)
        // 5 caras de 400 mm² con 2 mm de pared ≈ 4000 mm³ (más las esquinas redondeadas).
        XCTAssertGreaterThan(report.volume, 3500)
        XCTAssertLessThan(report.volume, 5500)
    }
}

/// Cuenta piezas sin depender de detalles internos de PrintPrep.
private enum MeshRepairCount {
    static func pieces(_ mesh: Mesh) -> Int { MeshRepair.pieceCount(mesh) }
}
