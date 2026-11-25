import simd
import XCTest
import Geometry
import PrintPrep
import Sculpt

final class SubdivisionAndRaycastTests: XCTestCase {
    func testIcosphereIsWatertightAndRound() {
        let sphere = Mesh.icosphere(radius: 10, subdivisions: 4)
        XCTAssertEqual(sphere.triangleCount, 20 * 256)
        let report = MeshAnalyzer.analyze(sphere)
        XCTAssertTrue(report.isWatertight)
        let expected = 4.0 / 3.0 * Float.pi * 1000
        XCTAssertEqual(report.volume, expected, accuracy: expected * 0.02)
    }

    func testSubdivisionKeepsShapeAndClosure() {
        let box = Mesh.box(size: SIMD3<Float>(10, 20, 30)).subdivided()
        XCTAssertEqual(box.triangleCount, 48)
        let report = MeshAnalyzer.analyze(box)
        XCTAssertTrue(report.isWatertight)
        XCTAssertEqual(report.volume, 6000, accuracy: 0.01)
    }

    func testRaycastHitsNearestSurface() {
        let sphere = Mesh.icosphere(radius: 10, subdivisions: 3)
        let hit = sphere.raycast(Ray(origin: SIMD3<Float>(0.1, 0.2, 50), direction: SIMD3<Float>(0, 0, -1)))
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit?.distance ?? 0, 40, accuracy: 0.3)
        XCTAssertEqual(hit?.point.z ?? 0, 10, accuracy: 0.3)
    }

    func testRaycastMiss() {
        let sphere = Mesh.icosphere(radius: 10, subdivisions: 2)
        XCTAssertNil(sphere.raycast(Ray(origin: SIMD3<Float>(50, 50, 50), direction: SIMD3<Float>(0, 0, -1))))
    }
}

final class SculptEngineTests: XCTestCase {
    private func base() -> Mesh { Mesh.icosphere(radius: 10, subdivisions: 4) }

    private func settings(_ brush: BrushKind, invert: Bool = false, symmetry: Bool = false) -> SculptSettings {
        var s = SculptSettings()
        s.brush = brush
        s.strength = 1
        s.invert = invert
        s.symmetryX = symmetry
        return s
    }

    private func topHit(_ engine: SculptEngine) -> SIMD3<Float> {
        engine.hit(Ray(origin: SIMD3<Float>(0.2, 50, 0.3), direction: SIMD3<Float>(0, -1, 0)))!
    }

    func testDrawRaisesAndInvertSinks() {
        let original = MeshAnalyzer.analyze(base()).volume

        let up = SculptEngine(mesh: base())
        up.applyDab(at: topHit(up), radius: 4, settings: settings(.draw))
        XCTAssertGreaterThan(MeshAnalyzer.analyze(up.mesh).volume, original)
        XCTAssertGreaterThan(up.mesh.bounds.max.y, 10.1)

        let down = SculptEngine(mesh: base())
        down.applyDab(at: topHit(down), radius: 4, settings: settings(.draw, invert: true))
        XCTAssertLessThan(MeshAnalyzer.analyze(down.mesh).volume, original)
    }

    func testSculptingKeepsMeshClosed() {
        let engine = SculptEngine(mesh: base())
        for _ in 0..<5 {
            engine.applyDab(at: topHit(engine), radius: 4, settings: settings(.inflate))
        }
        XCTAssertTrue(MeshAnalyzer.analyze(engine.mesh).isWatertight)
    }

    func testSymmetryMirrorsAcrossX() {
        let side = Ray(origin: SIMD3<Float>(50, 0.3, 0.2), direction: SIMD3<Float>(-1, 0, 0))

        let mirrored = SculptEngine(mesh: base())
        mirrored.applyDab(at: mirrored.hit(side)!, radius: 4, settings: settings(.inflate, symmetry: true))
        let b = mirrored.mesh.bounds
        XCTAssertGreaterThan(b.max.x, 10.05)
        XCTAssertEqual(b.min.x, -b.max.x, accuracy: 1e-3)

        let single = SculptEngine(mesh: base())
        single.applyDab(at: single.hit(side)!, radius: 4, settings: settings(.inflate))
        XCTAssertEqual(single.mesh.bounds.min.x, -10, accuracy: 1e-3)
    }

    func testSmoothReducesBump() {
        let engine = SculptEngine(mesh: base())
        let center = topHit(engine)
        engine.applyDab(at: center, radius: 3, settings: settings(.draw))
        engine.applyDab(at: center, radius: 3, settings: settings(.draw))
        let bumped = engine.mesh.bounds.max.y
        for _ in 0..<20 {
            engine.applyDab(at: center, radius: 5, settings: settings(.smooth))
        }
        XCTAssertLessThan(engine.mesh.bounds.max.y, bumped)
    }

    func testFlattenLowersTop() {
        let engine = SculptEngine(mesh: base())
        let center = topHit(engine)
        for _ in 0..<10 {
            engine.applyDab(at: center, radius: 6, settings: settings(.flatten))
        }
        XCTAssertLessThan(engine.mesh.bounds.max.y, 9.9)
    }

    func testGrabPullsSurface() {
        let engine = SculptEngine(mesh: base())
        engine.beginGrab(at: topHit(engine), radius: 4, symmetryX: false)
        engine.updateGrab(delta: SIMD3<Float>(0, 5, 0))
        engine.endStroke()
        XCTAssertGreaterThan(engine.mesh.bounds.max.y, 13)
        XCTAssertTrue(MeshAnalyzer.analyze(engine.mesh).isWatertight)
    }
}
