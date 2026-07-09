import Foundation
import SwiftUI
import simd

struct CapturedReferencePoint: Identifiable, Equatable {
    let id: Int
    let label: String
    let world: SIMD3<Float>

    var displayText: String {
        "\(id + 1). \(label)"
    }
}

struct SixPointReferenceSummary: Equatable {
    let widthMM: Double
    let heightMM: Double
    let depthMM: Double
    let paddingMM: Double

    var compactDescription: String {
        String(format: "Reference box %.1f × %.1f × %.1f mm", widthMM, heightMM, depthMM)
    }
}

@MainActor
final class ScannerViewModel: ObservableObject {
    @Published var status: String = "Aim the center reticle at ground zero and capture the 6 reference points."
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
    @Published var referencePoints: [CapturedReferencePoint] = []
    @Published var sixPointReferenceReady: Bool = false
    @Published var sixPointSummary: SixPointReferenceSummary?

    weak var arController: ARScannerController?

    private let referencePointLabels = [
        "Ground zero / datum",
        "Highest point",
        "Boundary point 1",
        "Boundary point 2",
        "Boundary point 3",
        "Boundary point 4"
    ]

    var nextReferencePointLabel: String {
        guard referencePoints.count < referencePointLabels.count else {
            return "6-point reference complete"
        }
        return referencePointLabels[referencePoints.count]
    }

    var referenceProgressText: String {
        "\(referencePoints.count) / \(referencePointLabels.count) points"
    }

    var canCaptureMoreReferencePoints: Bool {
        referencePoints.count < referencePointLabels.count
    }

    func attach(controller: ARScannerController) {
        self.arController = controller
    }

    /// Legacy/manual center mode. The 6-point reference mode is preferred because it also sets ground zero and object bounds.
    func setObjectCenter() {
        guard let arController else {
            status = "AR view is not ready yet."
            return
        }
        clearReferencePointsWithoutResettingAR()
        arController.setObjectCenterFromScreenCenter()
        objectCenterIsSet = true
        sixPointReferenceReady = false
        sixPointSummary = nil
    }

    func captureReferencePoint() {
        guard let arController else {
            status = "AR view is not ready yet."
            return
        }
        guard canCaptureMoreReferencePoints else {
            status = "The 6 reference points are already captured. Clear or undo to change them."
            return
        }

        guard let point = arController.captureWorldPointFromScreenCenter() else {
            status = "Could not capture a 3D point. Move slowly, aim the reticle at a visible surface, and try again."
            return
        }

        let index = referencePoints.count
        let captured = CapturedReferencePoint(id: index, label: referencePointLabels[index], world: point)
        referencePoints.append(captured)

        if referencePoints.count == referencePointLabels.count {
            applySixPointReference()
        } else {
            status = "Captured \(captured.label). Next: \(nextReferencePointLabel)."
        }
    }

    func undoReferencePoint() {
        guard !referencePoints.isEmpty else {
            status = "No reference points to undo."
            return
        }
        let removed = referencePoints.removeLast()
        objectCenterIsSet = false
        sixPointReferenceReady = false
        sixPointSummary = nil
        arController?.clearSixPointReference()
        status = "Removed \(removed.label). Next: \(nextReferencePointLabel)."
    }

    func clearReferencePoints() {
        clearReferencePointsWithoutResettingAR()
        status = "Reference points cleared. Aim at ground zero and capture point 1."
    }

    private func clearReferencePointsWithoutResettingAR() {
        referencePoints = []
        objectCenterIsSet = false
        sixPointReferenceReady = false
        sixPointSummary = nil
        arController?.clearSixPointReference()
    }

    private func applySixPointReference() {
        guard let arController else { return }
        let points = referencePoints.map { $0.world }
        guard let summary = arController.applySixPointReference(points: points, paddingMM: 5.0) else {
            objectCenterIsSet = false
            sixPointReferenceReady = false
            sixPointSummary = nil
            status = "The 6 points did not define a usable object volume. Make sure point 2 is above point 1 and the four boundary points surround the part."
            return
        }

        sixPointSummary = summary
        sixPointReferenceReady = true
        objectCenterIsSet = true
        scanVolumeXMM = summary.widthMM
        scanVolumeYMM = summary.heightMM
        scanVolumeZMM = summary.depthMM
        status = "6-point reference locked. \(summary.compactDescription). Press Scan and move around the part."
    }

    func detectObjectAndStartScan() {
        guard objectCenterIsSet, sixPointReferenceReady else {
            status = "Capture all 6 reference points before object detection."
            return
        }
        guard !isScanning else {
            status = "Already scanning. Move around the part slowly."
            return
        }
        isScanning = true
        measurements = []
        toleranceResults = []
        lastSTLURL = nil
        lastReportURL = nil
        lastTriangleCount = 0
        lastVertexCount = 0
        arController?.beginCapture()
        status = "Object detector active. Only mesh inside the 6-point volume and above ground zero will be saved."
    }

    func toggleScan() {
        guard let arController else {
            status = "AR view is not ready yet."
            return
        }
        guard objectCenterIsSet else {
            status = "Capture the 6 reference points or set a manual center before scanning."
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
            if sixPointReferenceReady {
                status = "Scanning with 6-point object detection. Move slowly around all sides."
            } else {
                status = "Scanning with manual crop box. Walk around the object slowly."
            }
        } else {
            arController.endCapture()
            status = "Scan paused. Export when the visible mesh covers the object."
        }
    }

    func resetScan() {
        arController?.resetSession()
        isScanning = false
        objectCenterIsSet = false
        sixPointReferenceReady = false
        sixPointSummary = nil
        referencePoints = []
        measurements = []
        toleranceResults = []
        lastSTLURL = nil
        lastReportURL = nil
        lastTriangleCount = 0
        lastVertexCount = 0
        status = "Reset complete. Capture the 6 reference points again."
    }

    func exportCurrentScan() {
        guard let arController else {
            status = "AR view is not ready yet."
            return
        }
        guard objectCenterIsSet else {
            status = "Capture the 6 reference points or set a manual center before exporting."
            return
        }

        do {
            guard let rawMesh = arController.makeCroppedObjectMesh(
                volumeXMM: scanVolumeXMM,
                volumeYMM: scanVolumeYMM,
                volumeZMM: scanVolumeZMM
            ), !rawMesh.isEmpty else {
                status = "No object mesh was found. Scan more angles or recapture the 6 boundary points tighter around the part."
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

            var newMeasurements = MeshMeasurementCalculator.measurements(for: mesh)
            if let summary = sixPointSummary {
                newMeasurements.append(MeshMeasurement(name: "reference_height_mm", value: summary.heightMM, unit: "mm"))
                newMeasurements.append(MeshMeasurement(name: "reference_width_mm", value: summary.widthMM, unit: "mm"))
                newMeasurements.append(MeshMeasurement(name: "reference_depth_mm", value: summary.depthMM, unit: "mm"))
            }

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
            status = "Exported STL and tolerance report with the selected 6-point object reference."
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
