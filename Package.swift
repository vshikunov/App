// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DimensionalScanner",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "DimensionalScannerCore", targets: ["DimensionalScannerCore"]),
        .executable(name: "CoreSelfTest", targets: ["CoreSelfTest"])
    ],
    targets: [
        .target(
            name: "DimensionalScannerCore",
            path: "Sources/DimensionalScannerCore"
        ),
        .executableTarget(
            name: "CoreSelfTest",
            dependencies: ["DimensionalScannerCore"],
            path: "Tools/CoreSelfTest"
        ),
        .testTarget(
            name: "DimensionalScannerCoreTests",
            dependencies: ["DimensionalScannerCore"],
            path: "Tests/DimensionalScannerCoreTests"
        )
    ]
)
