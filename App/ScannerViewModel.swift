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

struct GroundAreaSummary: Equatable {
  let widthMM: Double
  let depthMM: Double
  let areaMM2: Double
  let planeTiltDegrees: Double
  let paddingMM: Double

  var compactDescription: String {
    String(format: "%.1f × %.1f mm", widthMM, depthMM)
  }

  var areaDescription: String {
    if areaMM2 >= 1_000_000 {
      return String(format: "%.3f m²", areaMM2 / 1_000_000)
    }
    return String(format: "%.0f mm²", areaMM2)
  }
}

struct STLDimensionSummary: Equatable {
  let widthMM: Double
  let heightMM: Double
  let depthMM: Double
  let triangleCount: Int

  var compactDescription: String {
    String(format: "%.1f × %.1f × %.1f mm", widthMM, heightMM, depthMM)
  }

  var isUsable: Bool {
    widthMM.isFinite && heightMM.isFinite && depthMM.isFinite
      && widthMM > 0 && heightMM > 0 && depthMM > 0
  }
}

enum ScannerWorkflowPhase: Equatable {
  case definingArea
  case readyToScan
  case scanning
  case review
  case processing
  case exported
}

@MainActor
final class ScannerViewModel: ObservableObject {
  @Published var status: String = "Capture four ground corners clockwise around the object."
  @Published var trackingSummary: String = "Starting AR…"
  @Published var isScanning: Bool = false
  @Published var hasStartedSurfaceScan: Bool = false
  @Published var objectCenterIsSet: Bool = false

  // Manual fallback crop values. The 4-point ground area overrides X and Z.
  @Published var scanVolumeXMM: Double = 200.0
  @Published var scanVolumeYMM: Double = 600.0
  @Published var scanVolumeZMM: Double = 200.0

  // Automatic area/object isolation settings.
  @Published var footprintMarginMM: Double = 8.0
  @Published var maximumObjectHeightMM: Double = 600.0
  @Published var groundClearanceMM: Double = 3.0
  @Published var minimumObjectHeightMM: Double = 4.0
  @Published var objectMergeDistanceMM: Double = 18.0

  // Per-frame LiDAR depth fusion. This is the reliable fallback when ARKit's coarse
  // scene-reconstruction mesh does not resolve a small tabletop object.
  @Published var depthFusionEnabled: Bool = true
  @Published var depthSamplingStride: Int = 4
  @Published var depthMaximumEdgeMM: Double = 35.0
  @Published var includeLowConfidenceDepth: Bool = true

  // Display options.
  @Published var showMeshOverlay: Bool = false
  @Published var showCapturedSurface: Bool = true
  @Published var showBoundingBox: Bool = true

  @Published var scaleCorrectionFactor: Double = 1.0
  @Published var specs: [ToleranceSpec] = ToleranceSpec.defaultObjectSpecs
  @Published var measurements: [MeshMeasurement] = []
  @Published var toleranceResults: [ToleranceResult] = []
  @Published var lastSTLURL: URL?
  @Published var lastReportURL: URL?
  @Published var lastMeasurementsURL: URL?
  @Published var lastTriangleCount: Int = 0
  @Published var lastVertexCount: Int = 0

  // Four-point ground footprint state.
  @Published var referencePoints: [CapturedReferencePoint] = []
  @Published var groundAreaReady: Bool = false
  @Published var groundAreaSummary: GroundAreaSummary?

  // Live Measure-style feedback and automatic object isolation state.
  @Published var reticleHasSurface: Bool = false
  @Published var reticleDistanceMM: Double?
  @Published var scanCoveragePercent: Double = 0
  @Published var capturedSurfaceTriangleCount: Int = 0
  @Published var liveMeshDimensions: STLDimensionSummary?
  @Published var exportedSTLDimensions: STLDimensionSummary?
  @Published var isGeneratingSTL: Bool = false
  @Published var detectedComponentCount: Int = 0
  @Published var objectIsolationMessage: String = "Waiting for the four-point area"

  // Capture diagnostics make failed scans actionable instead of silently producing
  // no STL.
  @Published var capturedDepthPointCount: Int = 0
  @Published var capturedDepthTriangleCount: Int = 0
  @Published var capturedSceneMeshAnchorCount: Int = 0
  @Published var captureSourceText: String = "Waiting for LiDAR depth"

  weak var arController: ARScannerController?

  private let referencePointLabels = [
    "Ground corner 1",
    "Ground corner 2",
    "Ground corner 3",
    "Ground corner 4",
  ]

  private let referencePointInstructions = [
    "Aim at the ground just outside the object, then tap Add.",
    "Move clockwise to the next ground corner.",
    "Continue clockwise around the object footprint.",
    "Capture the final corner. Scanning starts automatically.",
  ]

  var workflowPhase: ScannerWorkflowPhase {
    if isGeneratingSTL { return .processing }
    if lastSTLURL != nil { return .exported }
    if isScanning { return .scanning }
    if groundAreaReady {
      return hasStartedSurfaceScan ? .review : .readyToScan
    }
    return .definingArea
  }

  var nextReferencePointLabel: String {
    guard referencePoints.count < referencePointLabels.count else {
      return "Ground area complete"
    }
    return referencePointLabels[referencePoints.count]
  }

  var nextReferencePointInstruction: String {
    guard referencePoints.count < referencePointInstructions.count else {
      return "The blue footprint now limits automatic object detection."
    }
    return referencePointInstructions[referencePoints.count]
  }

  var referenceProgressText: String {
    "\(referencePoints.count) / \(referencePointLabels.count)"
  }

  var canCaptureMoreReferencePoints: Bool {
    referencePoints.count < referencePointLabels.count
  }

  var canBuildSTL: Bool {
    capturedSurfaceTriangleCount > 0
      || capturedDepthTriangleCount >= 12
      || capturedSceneMeshAnchorCount > 0
  }

  var captureDiagnosticsText: String {
    "\(captureSourceText) • pts \(capturedDepthPointCount.formatted()) • tris \(capturedDepthTriangleCount.formatted()) • anchors \(capturedSceneMeshAnchorCount.formatted())"
  }

  var compactStatusTitle: String {
    switch workflowPhase {
    case .definingArea:
      return "\(nextReferencePointLabel) • \(referenceProgressText)"
    case .readyToScan:
      return "Ground area ready • Start scan"
    case .scanning:
      if let liveMeshDimensions {
        return "Object detected • \(liveMeshDimensions.compactDescription)"
      }
      return "Finding object • \(captureSourceText)"
    case .review:
      return "Object surface captured • Review or measure"
    case .processing:
      return "Isolating object and building STL…"
    case .exported:
      return "STL and object dimensions are ready"
    }
  }

  func attach(controller: ARScannerController) {
    arController = controller
  }

  /// Manual fallback for unusual objects. Four ground points are the normal workflow.
  func setObjectCenter() {
    guard let arController else {
      status = "AR view is not ready yet."
      return
    }
    clearReferencePointsWithoutResettingAR()
    arController.setObjectCenterFromScreenCenter()
    objectCenterIsSet = true
    groundAreaReady = false
    groundAreaSummary = nil
  }

  func captureReferencePoint() {
    guard let arController else {
      status = "AR view is not ready yet."
      return
    }
    guard canCaptureMoreReferencePoints else {
      status = "The four ground corners are already captured. Undo or clear to edit them."
      return
    }
    guard reticleHasSurface else {
      status = "No stable surface at the reticle. Hold still and aim at the ground."
      UINotificationFeedbackGenerator().notificationOccurred(.warning)
      return
    }
    guard let point = arController.captureWorldPointFromScreenCenter() else {
      status = "Could not capture a 3D ground point. Hold steady and try again."
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
      applyGroundAreaReference()
    } else {
      status = "Captured corner \(index + 1). Continue clockwise to corner \(index + 2)."
    }
  }

  func undoReferencePoint() {
    guard !referencePoints.isEmpty else {
      status = "No ground point to undo."
      return
    }

    let removed = referencePoints.removeLast()
    objectCenterIsSet = false
    hasStartedSurfaceScan = false
    groundAreaReady = false
    groundAreaSummary = nil
    capturedSurfaceTriangleCount = 0
    scanCoveragePercent = 0
    liveMeshDimensions = nil
    exportedSTLDimensions = nil
    isGeneratingSTL = false
    detectedComponentCount = 0
    objectIsolationMessage = "Waiting for the four-point area"
    capturedDepthPointCount = 0
    capturedDepthTriangleCount = 0
    capturedSceneMeshAnchorCount = 0
    captureSourceText = "Waiting for LiDAR depth"
    arController?.removeLastReferencePointMarker()
    arController?.invalidateBoundingBox()
    status = "Removed \(removed.label). Aim at \(nextReferencePointLabel)."
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  func clearReferencePoints() {
    clearReferencePointsWithoutResettingAR()
    status = "Area cleared. Capture four ground corners clockwise around the object."
  }

  private func clearReferencePointsWithoutResettingAR() {
    isScanning = false
    hasStartedSurfaceScan = false
    referencePoints = []
    objectCenterIsSet = false
    groundAreaReady = false
    groundAreaSummary = nil
    scanCoveragePercent = 0
    capturedSurfaceTriangleCount = 0
    liveMeshDimensions = nil
    exportedSTLDimensions = nil
    isGeneratingSTL = false
    detectedComponentCount = 0
    objectIsolationMessage = "Waiting for the four-point area"
    capturedDepthPointCount = 0
    capturedDepthTriangleCount = 0
    capturedSceneMeshAnchorCount = 0
    captureSourceText = "Waiting for LiDAR depth"
    measurements = []
    toleranceResults = []
    lastSTLURL = nil
    lastReportURL = nil
    lastMeasurementsURL = nil
    arController?.clearReferenceVisuals()
  }

  private func applyGroundAreaReference() {
    guard let arController else { return }
    let points = referencePoints.map(\.world)

    guard
      let summary = arController.applyFourPointGroundArea(
        points: points,
        paddingMM: footprintMarginMM,
        maximumHeightMM: maximumObjectHeightMM,
        groundClearanceMM: groundClearanceMM,
        minimumObjectHeightMM: minimumObjectHeightMM,
        mergeDistanceMM: objectMergeDistanceMM
      )
    else {
      objectCenterIsSet = false
      groundAreaReady = false
      groundAreaSummary = nil
      status = "Those points do not form a usable flat area. Capture four corners clockwise on one surface."
      UINotificationFeedbackGenerator().notificationOccurred(.error)
      return
    }

    groundAreaSummary = summary
    groundAreaReady = true
    objectCenterIsSet = true
    scanVolumeXMM = summary.widthMM
    scanVolumeYMM = maximumObjectHeightMM
    scanVolumeZMM = summary.depthMM
    status = "Ground area locked at \(summary.compactDescription). The app is now isolating the object above it."
    objectIsolationMessage = "Searching for the largest non-ground surface cluster"
    UINotificationFeedbackGenerator().notificationOccurred(.success)

    // The fourth ground point completes the 2D region. Begin 3D capture immediately.
    startSurfaceScan()
  }

  func startSurfaceScan() {
    guard let arController else {
      status = "AR view is not ready yet."
      return
    }
    guard groundAreaReady else {
      status = "Capture all four ground corners first."
      return
    }
    guard !isScanning, !isGeneratingSTL else { return }

    isScanning = true
    hasStartedSurfaceScan = true
    measurements = []
    toleranceResults = []
    lastSTLURL = nil
    lastReportURL = nil
    lastMeasurementsURL = nil
    lastTriangleCount = 0
    lastVertexCount = 0
    scanCoveragePercent = 0
    capturedSurfaceTriangleCount = 0
    liveMeshDimensions = nil
    exportedSTLDimensions = nil
    detectedComponentCount = 0
    capturedDepthPointCount = 0
    capturedDepthTriangleCount = 0
    capturedSceneMeshAnchorCount = 0
    captureSourceText = depthFusionEnabled ? "LiDAR depth starting" : "ARKit mesh starting"
    objectIsolationMessage = "Scanning the selected footprint and removing the support surface"
    isGeneratingSTL = false
    arController.beginCapture(resetCoverage: true)
    status = "Move slowly around the object. Teal geometry is the automatically isolated object surface."
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
  }

  func stopSurfaceScan() {
    guard isScanning else { return }
    arController?.endCapture()
    isScanning = false
    status = "Scan paused. Inspect the teal object surface, resume if needed, or finish and measure."
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  func finishSurfaceScanAndCreateSTL() {
    guard groundAreaReady else {
      status = "Capture the four ground corners before creating an STL."
      return
    }

    guard canBuildSTL else {
      status = "No object geometry has been captured yet. Keep the phone 25–80 cm from the object, move slowly around it, and wait until the points/triangles counter increases."
      UINotificationFeedbackGenerator().notificationOccurred(.warning)
      return
    }

    if isScanning {
      arController?.endCapture()
      isScanning = false
    }

    isGeneratingSTL = true
    status = "Identifying the object, generating its STL, and measuring X/Y/Z bounds…"

    Task { @MainActor [weak self] in
      await Task.yield()
      self?.exportCurrentScan()
    }
  }

  func resumeSurfaceScan() {
    guard groundAreaReady else { return }
    isScanning = true
    arController?.beginCapture(resetCoverage: false)
    status = "Object capture resumed. Fill in missing sides and corners."
  }

  /// Compatibility for older UI actions.
  func detectObjectAndStartScan() {
    startSurfaceScan()
  }

  /// Compatibility for older UI actions.
  func toggleScan() {
    if isScanning {
      stopSurfaceScan()
    } else if groundAreaReady {
      startSurfaceScan()
    } else {
      startManualScan()
    }
  }

  private func startManualScan() {
    guard objectCenterIsSet else {
      status = "Set a manual center or capture the four-point ground area first."
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
    groundAreaReady = false
    groundAreaSummary = nil
    referencePoints = []
    measurements = []
    toleranceResults = []
    lastSTLURL = nil
    lastReportURL = nil
    lastMeasurementsURL = nil
    lastTriangleCount = 0
    lastVertexCount = 0
    scanCoveragePercent = 0
    capturedSurfaceTriangleCount = 0
    liveMeshDimensions = nil
    exportedSTLDimensions = nil
    isGeneratingSTL = false
    detectedComponentCount = 0
    objectIsolationMessage = "Waiting for the four-point area"
    capturedDepthPointCount = 0
    capturedDepthTriangleCount = 0
    capturedSceneMeshAnchorCount = 0
    captureSourceText = "Waiting for LiDAR depth"
    reticleHasSurface = false
    reticleDistanceMM = nil
    status = "New scan ready. Capture four ground corners clockwise around the object."
  }

  func exportCurrentScan() {
    guard let arController else {
      isGeneratingSTL = false
      status = "AR view is not ready yet."
      return
    }
    guard objectCenterIsSet else {
      isGeneratingSTL = false
      status = "Create the four-point ground area before exporting."
      return
    }

    isGeneratingSTL = true
    defer { isGeneratingSTL = false }

    if isScanning {
      arController.endCapture()
      isScanning = false
    }

    do {
      guard
        let rawMesh = arController.makeDetectedObjectMesh(
          volumeXMM: scanVolumeXMM,
          maximumHeightMM: maximumObjectHeightMM,
          volumeZMM: scanVolumeZMM
        ), !rawMesh.isEmpty
      else {
        status = "No STL surface was found. Captured depth: \(capturedDepthPointCount) points / \(capturedDepthTriangleCount) triangles; AR mesh: \(capturedSceneMeshAnchorCount) anchors. Resume scanning, keep the object inside the blue area, and reduce Ground clearance if the part is very low."
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        return
      }

      let safeScale = scaleCorrectionFactor > 0 ? scaleCorrectionFactor : 1.0
      let mesh = rawMesh.scaled(by: safeScale)
      let stlBounds = mesh.boundingBox()
      let finalDimensions = stlBounds.map { box in
        let groundReferencedHeight = groundAreaReady ? max(box.max.y, box.size.y) : box.size.y
        return STLDimensionSummary(
          widthMM: box.size.x,
          heightMM: groundReferencedHeight,
          depthMM: box.size.z,
          triangleCount: mesh.validFaceCount()
        )
      }

      let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      let folder = documents.appendingPathComponent("DimensionalScans", isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

      let stamp = Self.safeTimestamp()
      let stlURL = folder.appendingPathComponent("scan_\(stamp).stl")
      let reportURL = folder.appendingPathComponent("scan_tolerances_\(stamp).csv")
      let measurementURL = folder.appendingPathComponent("scan_dimensions_\(stamp).csv")

      try STLExporter.writeASCII(mesh: mesh, name: "iPhone_object_\(stamp)", to: stlURL)

      var newMeasurements = MeshMeasurementCalculator.measurements(for: mesh)
      if groundAreaReady, let box = stlBounds {
        let heightFromGround = max(box.max.y, box.size.y)
        if let index = newMeasurements.firstIndex(where: { $0.name == "bbox_y_mm" }) {
          newMeasurements[index].value = heightFromGround
        }
        newMeasurements.append(
          MeshMeasurement(name: "height_from_ground_mm", value: heightFromGround, unit: "mm"))
      }
      if let summary = groundAreaSummary {
        newMeasurements.append(
          MeshMeasurement(name: "ground_area_width_mm", value: summary.widthMM, unit: "mm"))
        newMeasurements.append(
          MeshMeasurement(name: "ground_area_depth_mm", value: summary.depthMM, unit: "mm"))
        newMeasurements.append(
          MeshMeasurement(name: "ground_area_mm2", value: summary.areaMM2, unit: "mm2"))
        newMeasurements.append(
          MeshMeasurement(name: "ground_plane_tilt_deg", value: summary.planeTiltDegrees, unit: "degree"))
      }
      newMeasurements.append(
        MeshMeasurement(name: "scan_coverage_percent", value: scanCoveragePercent, unit: "percent"))
      newMeasurements.append(
        MeshMeasurement(name: "detected_component_count", value: Double(detectedComponentCount), unit: "count"))
      newMeasurements.append(
        MeshMeasurement(name: "depth_point_sample_count", value: Double(capturedDepthPointCount), unit: "count"))
      newMeasurements.append(
        MeshMeasurement(name: "depth_triangle_count", value: Double(capturedDepthTriangleCount), unit: "count"))
      newMeasurements.append(
        MeshMeasurement(name: "scene_mesh_anchor_count", value: Double(capturedSceneMeshAnchorCount), unit: "count"))

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
      lastMeasurementsURL = measurementURL
      lastVertexCount = mesh.vertices.count
      lastTriangleCount = mesh.validFaceCount()
      exportedSTLDimensions = finalDimensions
      if let finalDimensions {
        liveMeshDimensions = finalDimensions
        status = "Object STL ready: \(finalDimensions.compactDescription), \(lastTriangleCount) triangles."
      } else {
        status = "Object STL ready: \(lastTriangleCount) triangles."
      }
      objectIsolationMessage = "Object surface exported from \(captureSourceText)"
      UINotificationFeedbackGenerator().notificationOccurred(.success)
    } catch {
      status = "Export failed: \(error.localizedDescription)"
      UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
  }

  func updateCaptureDiagnostics(
    depthPointCount: Int,
    depthTriangleCount: Int,
    sceneMeshAnchorCount: Int,
    source: String
  ) {
    capturedDepthPointCount = max(depthPointCount, 0)
    capturedDepthTriangleCount = max(depthTriangleCount, 0)
    capturedSceneMeshAnchorCount = max(sceneMeshAnchorCount, 0)
    captureSourceText = source
  }

  func updateLiveMeshDimensions(
    widthMM: Double,
    heightMM: Double,
    depthMM: Double,
    triangleCount: Int,
    componentCount: Int
  ) {
    capturedSurfaceTriangleCount = max(triangleCount, 0)
    detectedComponentCount = max(componentCount, 0)

    let scale = scaleCorrectionFactor > 0 ? scaleCorrectionFactor : 1.0
    let summary = STLDimensionSummary(
      widthMM: widthMM * scale,
      heightMM: heightMM * scale,
      depthMM: depthMM * scale,
      triangleCount: max(triangleCount, 0)
    )
    liveMeshDimensions = summary.isUsable ? summary : nil
    objectIsolationMessage = summary.isUsable
      ? "Object isolated from \(max(componentCount, 1)) connected surface cluster(s)"
      : "Searching for a stable non-ground object surface"
  }

  func clearLiveMeshDimensions() {
    capturedSurfaceTriangleCount = 0
    liveMeshDimensions = nil
    detectedComponentCount = 0
    objectIsolationMessage = "Searching for a stable non-ground object surface"
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
