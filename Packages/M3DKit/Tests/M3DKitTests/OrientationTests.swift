import simd
import XCTest
import Geometry

final class OrientationTests: XCTestCase {
    func testLayTiltedBoxFlatOnAFace() {
        let tilted = Mesh.box(size: SIMD3<Float>(10, 20, 30)).rotated(degrees: 33, axis: SIMD3<Float>(1, 1, 0.3))
        let hitTriangle = 0
        let (a, b, c) = tilted.corners(of: hitTriangle)
        let center = (a + b + c) / 3
        guard let normal = tilted.averageNormal(around: center, radius: 0.1, including: hitTriangle) else {
            return XCTFail("sin normal")
        }
        let flat = tilted.laidFlat(onFaceWithNormal: normal)

        // El triángulo 0 es de la cara −Z de la caja: apoyada en ella, la altura es el fondo (30 mm).
        XCTAssertEqual(flat.bounds.size.y, 30, accuracy: 1e-3)
        XCTAssertEqual(flat.bounds.min.y, 0, accuracy: 1e-4)
        // La cara tocada queda abajo, mirando hacia −Y.
        XCTAssertEqual(simd_normalize(flat.faceNormal(hitTriangle)).y, -1, accuracy: 1e-4)
    }

    func testFaceAlreadyUpsideDownTurnsHalfway() {
        let q = Mesh.rotationAligning(SIMD3<Float>(0, 1, 0), to: SIMD3<Float>(0, -1, 0))
        let v = q.act(SIMD3<Float>(0, 1, 0))
        XCTAssertEqual(v.y, -1, accuracy: 1e-5)
        let same = Mesh.rotationAligning(SIMD3<Float>(0, -1, 0), to: SIMD3<Float>(0, -1, 0))
        XCTAssertEqual(same.act(SIMD3<Float>(1, 2, 3)).y, 2, accuracy: 1e-5)
    }
}
