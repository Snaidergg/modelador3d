// swift-tools-version:5.9
// Núcleo de la app, dividido en módulos independientes.
// Se puede probar con `swift test` sin compilar la app completa.
import PackageDescription

let package = Package(
    name: "M3DKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Geometry", targets: ["Geometry"]),
        .library(name: "MeshIO", targets: ["MeshIO"]),
        .library(name: "Rendering", targets: ["Rendering"]),
        .library(name: "PrintPrep", targets: ["PrintPrep"]),
    ],
    targets: [
        // Estructuras de malla, primitivas y transformaciones. No depende de nada.
        .target(name: "Geometry"),
        // Lectura/escritura de archivos (STL, OBJ; luego 3MF, USDZ).
        .target(name: "MeshIO", dependencies: ["Geometry"]),
        // Render en Metal y cámara orbital.
        .target(name: "Rendering", dependencies: ["Geometry"]),
        // Análisis y reparación para impresión 3D.
        .target(name: "PrintPrep", dependencies: ["Geometry"]),
        .testTarget(name: "M3DKitTests", dependencies: ["Geometry", "MeshIO", "PrintPrep"]),
    ]
)
