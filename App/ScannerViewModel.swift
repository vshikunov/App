import Foundation
import SwiftUI
import UIKit
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
    String(format: "%.1f × %.1f × %.1f mm", widthMM, heightMM, depthMM)
  }
}

enum ScannerWorkflowPhase: Equatable {
  case definingBox
  case readyToScan
  case scanning
  case review
  case exported
}

@MainActor
final class ScannerViewModel: ObservableObject {
  @Published var status: String = "Aim at the bottom face and tap Add."
  @Published var trackingSummary: String = "Starting AR…"
  @Published var isScanning: Bool = false
  @Published var hasStartedSurfaceScan: Bool = false
  @Published var objectCenterIsSet: Bool = false

  // Manual fallback crop values. The 6-face box overrides these during normal use.
  @Published var scanVolumeXMM: Double = 160.0
  @Published var scanVolumeYMM: Double = 160.0
  @Published var scanVolumeZMM: Double = 160.0

  // Display options.
  @Published var showMeshOverlay: Bool = false
  @Published var showCapturedSurface: Bool = true
  @Published var showBoundingBox: Bool = true
  @Published var boundingBoxMarginMM: Double = 2.0

  @Published var scaleCorrectionFactor: Double = 1.0
  @Published var specs: [ToleranceSpec] = ToleranceSpec.defaultObjectSpecs
  @Published var measurements: [MeshMeasurement] = []
  @Published var toleranceResults: [ToleranceResult] = []
  @Published var lastSTLURL: URL?
  @Published var lastReportURL: URL?
  @Published var lastTriangleCount: Int = 0
  @Published var lastVertexCount: Int = 0

  // Six-face bounding box state.
  @Published var referencePoints: [CapturedReferencePoint] = []
  @Published var sixPointReferenceReady: Bool = false
  @Published var sixPointSummary: SixPointReferenceSummary?

  // Live Measure-style feedback.
  @Published var reticleHasSurface: Bool = false
  @Published var reticleDistanceMM: Double?
  @Published var scanCoveragePercent: Double = 0
  @Published var capturedSurfaceTriangleCount: Int = 0

  weak var arController: ARScannerController?

  private let referencePointLabels = [
    "Bottom face",
    "Top face",
    "Left face",
    "Right face",
    "Front face",
    "Back face",
  ]

  private let referencePointInstructions = [
    "Aim at the center of the bottom face or support plane.",
    "Aim at the center of the top face.",
    "Aim at the left-most face of the part.",
    "Aim at the right-most face of the part.",
    "Aim at the front face of the part.",
    "Aim at the back face of the part.",
  ]

  var workflowPhase: ScannerWorkflowPhase {
    if lastSTLURL != nil { return .exported }
    if isScanning { return .scanning }
    if sixPointReferenceReady {
      return hasStartedSurfaceScan ? .review : .readyToScan
    }
    return .definingBox
  }

  var nextReferencePointLabel: String {
    guard referencePoints.count < referencePointLabels.count else {
      return "Bounding box complete"
    }
    return referencePointLabels[referencePoints.count]
  }

  var nextReferencePointInstruction: String {
    guard referencePoints.count < referencePointInstructions.count else {
      return "The blue box now limits the object surface capture."
    }
    return referencePointInstructions[referencePoints.count]
  }

  var referenceProgressText: String {
    "\(referencePoints.count) / \(referencePointLabels.count)"
  }

  var canCaptureMoreReferencePoints: Bool {
    referencePoints.count < referencePointLabels.count
  }

  var compactStatusTitle: String {
    switch workflowPhase {
    case .definingBox:
      return "\(nextReferencePointLabel) • \(referenceProgressText)"
    case .readyToScan:
      return "Box ready • Start surface scan"
    case .scanning:
      return "Capturing surface • \(Int(scanCoveragePercent.rounded()))%"
    case .review:
      return "Surface captured • Review or export"
    case .exported:
      return "STL and report are ready"
    }
  }

  func attach(controller: ARScannerController) {
    arController = controller
  }

  /// Manual fallback for unusual objects. The six-face box is the normal workflow.
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
      status = "The six box faces are already captured. Undo or clear to edit them."
      return
    }
    guard reticleHasSurface else {
      status = "No stable surface at the reticle. Move more slowly and aim at a visible face."
      UINotificationFeedbackGenerator().notificationOccurred(.warning)
      return
    }
    guard let point = arController.captureWorldPointFromScreenCenter() else {
      status = "Could not capture a 3D point. Hold steady and try again."
      UINotificationFeedbackGenerator().notificationOccurred(.warning)
      return
    }

    let index = referencePoints.count
    let captured = CapturedReferencePoint(
      id: index,
      label: referencePointLabels[index],
      world: point
    )
    referencePoints.append(captured)
    arController.showReferencePoint(at: point, index: index)
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()

    if referencePoints.count == referencePointLabels.count {
      applySixPointReference()
    } else {
      status = "Captured \(captured.label). Next: \(nextReferencePointLabel)."
    }
  }

  func undoReferencePoint() {
    guard !referencePoints.isEmpty else {
      status = "No reference point to undo."
      return
    }

    let removed = referencePoints.removeLast()
    objectCenterIsSet = false
    hasStartedSurfaceScan = false
    sixPointReferenceReady = false
    sixPointSummary = nil
    capturedSurfaceTriangleCount = 0
    scanCoveragePercent = 0
    arController?.removeLastReferencePointMarker()
    arController?.invalidateBoundingBox()
    status = "Removed \(removed.label). Aim at \(nextReferencePointLabel)."
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  func clearReferencePoints() {
    clearReferencePointsWithoutResettingAR()
    status = "Box cleared. Aim at the bottom face and tap Add."
  }

  private func clearReferencePointsWithoutResettingAR() {
    isScanning = false
    hasStartedSurfaceScan = false
    referencePoints = []
    objectCenterIsSet = false
    sixPointReferenceReady = false
    sixPointSummary = nil
    scanCoveragePercent = 0
    capturedSurfaceTriangleCount = 0
    measurements = []
    toleranceResults = []
    lastSTLURL = nil
    lastReportURL = nil
    arController?.clearReferenceVisuals()
  }

  private func applySixPointReference() {
    guard let arController else { return }
    let points = referencePoints.map(\.world)

    guard
      let summary = arController.applySixPointReference(
        points: points,
        paddingMM: boundingBoxMarginMM
      )
    else {
      objectCenterIsSet = false
      sixPointReferenceReady = false
      sixPointSummary = nil
      status = "Those points do not form a usable box. Check each opposite face and try again."
      UINotificationFeedbackGenerator().notificationOccurred(.error)
      return
    }

    sixPointSummary = summary
    sixPointReferenceReady = true
    objectCenterIsSet = true
    scanVolumeXMM = summary.widthMM
    scanVolumeYMM = summary.heightMM
    scanVolumeZMM = summary.depthMM
    status = "Bounding box locked at \(summary.compactDescription). Start the surface scan."
    UINotificationFeedbackGenerator().notificationOccurred(.success)
  }

  func startSurfaceScan() {
    guard let arController else {
      status = "AR view is not ready yet."
      return
    }
    guard sixPointReferenceReady else {
      status = "Capture all six box faces first."
      return
    }

    isScanning = true
    hasStartedSurfaceScan = true
    measurements = []
    toleranceResults = []
    lastSTLURL = nil
    lastReportURL = nil
    lastTriangleCount = 0
    lastVertexCount = 0
    scanCoveragePercent = 0
    capturedSurfaceTriangleCount = 0
    arController.beginCapture(resetCoverage: true)
    status = "Move slowly around the part. The teal overlay is the surface that will be exported."
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
  }

  func stopSurfaceScan() {
    guard isScanning else { return }
    arController?.endCapture()
    isScanning = false
    status = "Scan paused. Inspect the teal surface, resume if needed, or export."
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  func resumeSurfaceScan() {
    guard sixPointReferenceReady else { return }
    isScanning = true
    arController?.beginCapture(resetCoverage: false)
    status = "Surface capture resumed. Fill in missing sides and corners."
  }

  /// Compatibility for older UI actions.
  func detectObjectAndStartScan() {
    startSurfaceScan()
  }

  /// Compatibility for older UI actions.
  func toggleScan() {
    if isScanning {
      stopSurfaceScan()
    } else if sixPointReferenceReady {
      startSurfaceScan()
    } else {
      startManualScan()
    }
  }

  private func startManualScan() {
    guard objectCenterIsSet else {
      status = "Set a manual center or capture the six box faces first."
      return
    }
    isScanning = true
    hasStartedSurfaceScan = true
    arController?.beginCapture(resetCoverage: true)
    status = "Scanning with the manual crop volume."
  }

  func resetScan() {
    arController?.resetSession()
    isScanning = false
    hasStartedSurfaceScan = false
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
    scanCoveragePercent = 0
    capturedSurfaceTriangleCount = 0
    reticleHasSurface = false
    reticleDistanceMM = nil
    status = "New scan ready. Aim at the bottom face and tap Add."
  }

  func exportCurrentScan() {
    guard let arController else {
      status = "AR view is not ready yet."
      return
    }
    guard objectCenterIsSet else {
      status = "Create the six-face bounding box before exporting."
      return
    }

    if isScanning {
      arController.endCapture()
      isScanning = false
    }

    do {
      guard
        let rawMesh = arController.makeCroppedObjectMesh(
          volumeXMM: scanVolumeXMM,
          volumeYMM: scanVolumeYMM,
          volumeZMM: scanVolumeZMM
        ), !rawMesh.isEmpty
      else {
        status = "No object surface was found inside the box. Resume scanning or redefine the box."
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
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
        newMeasurements.append(
          MeshMeasurement(name: "reference_width_mm", value: summary.widthMM, unit: "mm"))
        newMeasurements.append(
          MeshMeasurement(name: "reference_height_mm", value: summary.heightMM, unit: "mm"))
        newMeasurements.append(
          MeshMeasurement(name: "reference_depth_mm", value: summary.depthMM, unit: "mm"))
      }
      newMeasurements.append(
        MeshMeasurement(name: "scan_coverage_percent", value: scanCoveragePercent, unit: "percent"))

      let measurementMap = Dictionary(
        uniqueKeysWithValues: newMeasurements.map { ($0.name, $0.value) })
      let newResults = ToleranceAnalyzer.analyze(measurements: measurementMap, specs: specs)
      try CSVExporter.toleranceReportCSV(results: newResults)
        .write(to: reportURL, atomically: true, encoding: .utf8)
      try CSVExporter.measurementsCSV(measurements: newMeasurements)
        .write(to: measurementURL, atomically: true, encoding: .utf8)

      measurements = newMeasurements
      toleranceResults = newResults
      lastSTLURL = stlURL
      lastReportURL = reportURL
      lastVertexCount = mesh.vertices.count
      lastTriangleCount = mesh.validFaceCount()
      status = "Export complete: \(lastTriangleCount) triangles."
      UINotificationFeedbackGenerator().notificationOccurred(.success)
    } catch {
      status = "Export failed: \(error.localizedDescription)"
      UINotificationFeedbackGenerator().notificationOccurred(.error)
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
