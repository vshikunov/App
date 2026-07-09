import XCTest
@testable import DimensionalScannerCore

final class DimensionalScannerCoreTests: XCTestCase {
    func testBoxMeasurements() throws {
        let mesh = MeshFixtures.makeBox(widthMM: 70, heightMM: 110, depthMM: 50)
        let values = MeshMeasurementCalculator.dictionary(for: mesh)

        XCTAssertEqual(values["bbox_x_mm"] ?? -1, 70, accuracy: 0.000_001)
        XCTAssertEqual(values["bbox_y_mm"] ?? -1, 110, accuracy: 0.000_001)
        XCTAssertEqual(values["bbox_z_mm"] ?? -1, 50, accuracy: 0.000_001)
        XCTAssertEqual(values["triangle_count"] ?? -1, 12, accuracy: 0.000_001)
    }

    func testMeshScaling() throws {
        let mesh = MeshFixtures.makeBox(widthMM: 70, heightMM: 110, depthMM: 50).scaled(by: 2.0)
        let values = MeshMeasurementCalculator.dictionary(for: mesh)
        XCTAssertEqual(values["bbox_x_mm"] ?? -1, 140, accuracy: 0.000_001)
        XCTAssertEqual(values["bbox_y_mm"] ?? -1, 220, accuracy: 0.000_001)
        XCTAssertEqual(values["bbox_z_mm"] ?? -1, 100, accuracy: 0.000_001)
    }

    func testToleranceAnalysisPassAndFail() throws {
        let measurements = [
            "bbox_x_mm": 70.0,
            "bbox_y_mm": 112.2,
            "bbox_z_mm": 49.5
        ]
        let specs = [
            ToleranceSpec(name: "bbox_x_mm", nominalMM: 70, lowerToleranceMM: -1, upperToleranceMM: 1),
            ToleranceSpec(name: "bbox_y_mm", nominalMM: 110, lowerToleranceMM: -1, upperToleranceMM: 1),
            ToleranceSpec(name: "bbox_z_mm", nominalMM: 50, lowerToleranceMM: -1, upperToleranceMM: 1)
        ]

        let results = ToleranceAnalyzer.analyze(measurements: measurements, specs: specs)
        let byName = Dictionary(uniqueKeysWithValues: results.map { ($0.name, $0.status) })
        XCTAssertEqual(byName["bbox_x_mm"], .pass)
        XCTAssertEqual(byName["bbox_y_mm"], .failHigh)
        XCTAssertEqual(byName["bbox_z_mm"], .pass)
    }

    func testSTLExporterWritesTriangles() throws {
        let mesh = MeshFixtures.makeBox(widthMM: 70, heightMM: 110, depthMM: 50)
        let stl = STLExporter.asciiSTL(mesh: mesh, name: "unit_test_box")
        XCTAssertTrue(stl.hasPrefix("solid unit_test_box"))
        XCTAssertTrue(stl.contains("facet normal"))
        XCTAssertEqual(stl.components(separatedBy: "facet normal").count - 1, 12)
    }

    func testCSVReport() throws {
        let results = [
            ToleranceResult(
                name: "bbox_x_mm",
                measuredMM: 70.0,
                nominalMM: 70.0,
                lowerLimitMM: 69.0,
                upperLimitMM: 71.0,
                errorMM: 0.0,
                status: .pass
            )
        ]
        let csv = CSVExporter.toleranceReportCSV(results: results)
        XCTAssertTrue(csv.contains("name,measured_mm,nominal_mm"))
        XCTAssertTrue(csv.contains("bbox_x_mm,70.000000"))
    }
}
