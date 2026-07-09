import Foundation
import SwiftUI

@MainActor
final class ScannerViewModel: ObservableObject {
    @Published var status: String = "Move around the object, then set the object center."
    @Published var trackingSummary: String = "AR not started"
    @Published var isScanning: Bool = false
    @Published var objectCenterIsSet: Bool = false
    @Published var scanVolumeXMM: Double = 160.0
    @Published var scanVolumeYMM: Double = 160.0
    @Published var scanVolumeZMM: Double = 160.0
    @Published var showMeshOverlay: Bool = true
    @Published var scaleCorrectionFactor: Double = 1.0
    @Published var specs: [ToleranceSpec] = ToleranceSpec.defaultObjectSpecs
    @Published var measurements: [MeshMeasurement] = []
    @Published var toleranceResults: [ToleranceResult] = []
    @Published var lastSTLURL: URL?
    @Published var lastReportURL: URL?
    @Published var lastTriangleCount: Int = 0
    @Published var lastVertexCount: Int = 0

    weak var arController: ARScannerController?

    func attach(controller: ARScannerController) {
        self.arController = controller
    }

    func setObjectCenter() {
        guard let arController else {
            status = "AR view is not ready yet."
            return
        }
        arController.setObjectCenterFromScreenCenter()
        objectCenterIsSet = true
    }

    func toggleScan() {
        guard let arController else {
            status = "AR view is not ready yet."
            return
        }
        guard objectCenterIsSet else {
            status = "Set the object center before scanning."
            return
        }

        isScanning.toggle()
        if isScanning {
            measurements = []
            toleranceResults = []
            lastSTLURL = nil
            lastReportURL = nil
            lastTriangleCount = 0
            lastVertexCount = 0
            arController.beginCapture()
            status = "Scanning. Walk around the object slowly."
        } else {
            arController.endCapture()
            status = "Scan paused. Export when the visible mesh covers the object."
        }
    }

    func resetScan() {
        arController?.resetSession()
        isScanning = false
        objectCenterIsSet = false
        measurements = []
        toleranceResults = []
        lastSTLURL = nil
        lastReportURL = nil
        lastTriangleCount = 0
        lastVertexCount = 0
        status = "Reset complete. Set the object center again."
    }

    func exportCurrentScan() {
        guard let arController else {
            status = "AR view is not ready yet."
            return
        }
        guard objectCenterIsSet else {
            status = "Set the object center before exporting."
            return
        }

        do {
            guard let rawMesh = arController.makeCroppedObjectMesh(
                volumeXMM: scanVolumeXMM,
                volumeYMM: scanVolumeYMM,
                volumeZMM: scanVolumeZMM
            ), !rawMesh.isEmpty else {
                status = "No cropped mesh was found. Tighten the crop volume or scan more angles."
                return
            }

            let safeScale = scaleCorrectionFactor > 0 ? scaleCorrectionFactor : 1.0
            let mesh = rawMesh.scaled(by: safeScale)

            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let folder = documents.appendingPathComponent("DimensionalScans", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            let stamp = Self.safeTimestamp()
            let stlURL = folder.appendingPathComponent("scan_\(stamp).stl")
            let reportURL = folder.appendingPathComponent("scan_report_\(stamp).csv")
            let measurementURL = folder.appendingPathComponent("scan_measurements_\(stamp).csv")

            try STLExporter.writeASCII(mesh: mesh, name: "iPhone_scan_\(stamp)", to: stlURL)

            let newMeasurements = MeshMeasurementCalculator.measurements(for: mesh)
            let measurementMap = Dictionary(uniqueKeysWithValues: newMeasurements.map { ($0.name, $0.value) })
            let newResults = ToleranceAnalyzer.analyze(measurements: measurementMap, specs: specs)
            try CSVExporter.toleranceReportCSV(results: newResults).write(to: reportURL, atomically: true, encoding: .utf8)
            try CSVExporter.measurementsCSV(measurements: newMeasurements).write(to: measurementURL, atomically: true, encoding: .utf8)

            measurements = newMeasurements
            toleranceResults = newResults
            lastSTLURL = stlURL
            lastReportURL = reportURL
            lastVertexCount = mesh.vertices.count
            lastTriangleCount = mesh.validFaceCount()
            status = "Exported STL and tolerance report on this iPhone."
        } catch {
            status = "Export failed: \(error.localizedDescription)"
        }
    }

    func applyDefaultBoxSpecs() {
        specs = ToleranceSpec.defaultObjectSpecs
    }

    private static func safeTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }
}
