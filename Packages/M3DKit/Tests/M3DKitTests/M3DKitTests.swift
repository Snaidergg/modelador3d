import Foundation
import simd
import XCTest
import Geometry
import MeshIO
import PrintPrep

final class GeometryTests: XCTestCase {
    func testSphereIsWatertightWithOutwardNormals() {
        let sphere = Mesh.uvSphere(radius: 10, segments: 64, rings: 32)
        let report = MeshAnalyzer.analyze(sphere)
        XCTAssertTrue(report.isWatertight)
        let expected = 4.0 / 3.0 * Float.pi * 1000
        XCTAssertGreaterThan(report.volume, 0, "las normales deben apuntar hacia afuera")
        XCTAssertEqual(report.volume, expected, accuracy: expected * 0.02)
    }

    func testBoxVolumeAndOrientation() {
        let box = Mesh.box(size: SIMD3<Float>(10, 20, 30))
        let report = MeshAnalyzer.analyze(box)
        XCTAssertTrue(report.isWatertight)
        XCTAssertEqual(report.volume, 6000, accuracy: 0.01)
        XCTAssertEqual(report.surfaceArea, 2 * (200 + 300 + 600), accuracy: 0.01)
    }

    func testFlippedMeshHasNegativeVolume() {
        let report = MeshAnalyzer.analyze(Mesh.box(size: SIMD3<Float>(1, 1, 1)).flipped())
        XCTAssertTrue(report.normalsPointInward)
    }

    func testOpenMeshIsNotWatertight() {
        var box = Mesh.box(size: SIMD3<Float>(1, 1, 1))
        box.triangles.removeLast()
        let report = MeshAnalyzer.analyze(box)
        XCTAssertFalse(report.isWatertight)
        XCTAssertEqual(report.boundaryEdges, 3)
    }

    func testRecenteredSitsOnBed() {
        let mesh = Mesh.uvSphere(radius: 5).translated(by: SIMD3<Float>(7, 3, -2)).recentered()
        let b = mesh.bounds
        XCTAssertEqual(b.min.y, 0, accuracy: 1e-4)
        XCTAssertEqual(b.center.x, 0, accuracy: 1e-4)
        XCTAssertEqual(b.center.z, 0, accuracy: 1e-4)
    }

    func testNegativeScaleKeepsOutwardNormals() {
        let mirrored = Mesh.box(size: SIMD3<Float>(1, 1, 1)).scaled(by: SIMD3<Float>(-1, 1, 1))
        XCTAssertGreaterThan(MeshAnalyzer.analyze(mirrored).volume, 0)
    }
}

final class MeshIOTests: XCTestCase {
    func testBinarySTLRoundTrip() throws {
        let box = Mesh.box(size: SIMD3<Float>(10, 20, 30))
        let data = STLFormat.exportBinary(box)
        XCTAssertEqual(data.count, 84 + 50 * 12)

        let loaded = try STLFormat.load(data)
        XCTAssertEqual(loaded.triangleCount, 12)
        XCTAssertEqual(loaded.vertexCount, 8, "los vértices duplicados deben unirse")
        let report = MeshAnalyzer.analyze(loaded)
        XCTAssertTrue(report.isWatertight)
        XCTAssertEqual(report.volume, 6000, accuracy: 0.01)
        XCTAssertEqual(loaded.bounds.size.y, 20, accuracy: 1e-4, "el eje vertical se convierte ida y vuelta")
    }

    func testExportedSTLIsZUp() throws {
        // Una caja alta en Y (interno) debe quedar alta en Z dentro del archivo.
        let box = Mesh.box(size: SIMD3<Float>(1, 5, 1))
        let fileSpace = try STLFormat.load(STLFormat.exportBinary(box), fileUpAxis: .y)
        XCTAssertEqual(fileSpace.bounds.size.z, 5, accuracy: 1e-4)
    }

    func testASCIISTL() throws {
        let text = """
        solid prueba
          facet normal 0 0 1
            outer loop
              vertex 0 0 0
              vertex 1 0 0
              vertex 0 1 0
            endloop
          endfacet
        endsolid prueba
        """
        let mesh = try STLFormat.load(Data(text.utf8))
        XCTAssertEqual(mesh.triangleCount, 1)
        XCTAssertEqual(mesh.vertexCount, 3)
    }

    func testOBJQuadAndNegativeIndices() throws {
        let text = """
        v 0 0 0
        v 1 0 0
        v 1 1 0
        v 0 1 0
        f 1/1/1 2/2/2 3/3/3 4/4/4
        f -4 -2 -1
        """
        let mesh = try OBJFormat.load(Data(text.utf8))
        XCTAssertEqual(mesh.triangleCount, 3)
        XCTAssertEqual(mesh.triangles[2], SIMD3<UInt32>(0, 2, 3))
    }

    func testOBJRoundTrip() throws {
        let sphere = Mesh.uvSphere(radius: 3, segments: 12, rings: 6)
        let loaded = try OBJFormat.load(OBJFormat.export(sphere))
        XCTAssertEqual(loaded.triangles, sphere.triangles)
        XCTAssertEqual(loaded.vertexCount, sphere.vertexCount)
    }

    func testInvalidOBJThrows() {
        XCTAssertThrowsError(try OBJFormat.load(Data("v 0 0 0\nf 1 2 3\n".utf8)))
    }
}
