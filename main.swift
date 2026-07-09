import Foundation
import DimensionalScannerCore

struct Arguments {
    var outputDirectory: URL
}

func parseArguments() throws -> Arguments {
    let args = CommandLine.arguments.dropFirst()
    var output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    var iterator = args.makeIterator()

    while let arg = iterator.next() {
        switch arg {
        case "--out":
            guard let value = iterator.next() else {
                throw NSError(domain: "CoreSelfTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing value after --out"])
            }
            output = URL(fileURLWithPath: value, isDirectory: true)
        default:
            throw NSError(domain: "CoreSelfTest", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unknown argument: \(arg)"])
        }
    }

    return Arguments(outputDirectory: output)
}

let arguments = try parseArguments()
try FileManager.default.createDirectory(at: arguments.outputDirectory, withIntermediateDirectories: true)

let mesh = MeshFixtures.makeBox(widthMM: 70, heightMM: 110, depthMM: 50)
let stlURL = arguments.outputDirectory.appendingPathComponent("core_self_test_box.stl")
try STLExporter.writeASCII(mesh: mesh, name: "core_self_test_box", to: stlURL)

let measurements = MeshMeasurementCalculator.measurements(for: mesh)
let measurementMap = Dictionary(uniqueKeysWithValues: measurements.map { ($0.name, $0.value) })
let specs = ToleranceSpec.defaultObjectSpecs
let results = ToleranceAnalyzer.analyze(measurements: measurementMap, specs: specs)
let reportURL = arguments.outputDirectory.appendingPathComponent("core_self_test_report.csv")
try CSVExporter.toleranceReportCSV(results: results).write(to: reportURL, atomically: true, encoding: .utf8)
let measurementURL = arguments.outputDirectory.appendingPathComponent("core_self_test_measurements.csv")
try CSVExporter.measurementsCSV(measurements: measurements).write(to: measurementURL, atomically: true, encoding: .utf8)

print("Wrote STL: \(stlURL.path)")
print("Wrote tolerance report: \(reportURL.path)")
for result in results {
    let measured = result.measuredMM.map { String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "missing"
    print("\(result.name): measured=\(measured) mm, status=\(result.status.rawValue)")
}
