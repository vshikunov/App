import ARKit
import CoreVideo
import QuartzCore
import RealityKit
import SwiftUI
import UIKit
import simd

struct ARScannerView: UIViewRepresentable {
  @EnvironmentObject var model: ScannerViewModel

  func makeCoordinator() -> Coordinator {
    Coordinator(model: model)
  }

  func makeUIView(context: Context) -> ARView {
    let arView = ARView(frame: .zero)
    arView.automaticallyConfigureSession = false
    arView.renderOptions.insert(.disableMotionBlur)

    let controller = ARScannerController(arView: arView, model: model)
    context.coordinator.controller = controller
    model.attach(controller: controller)
    controller.startSession(showMeshOverlay: model.showMeshOverlay)
    controller.setCapturedSurfaceVisible(model.showCapturedSurface)
    controller.setBoundingBoxVisible(model.showBoundingBox)
    return arView
  }

  func updateUIView(_ uiView: ARView, context: Context) {
    context.coordinator.controller?.setMeshOverlayVisible(model.showMeshOverlay)
    context.coordinator.controller?.setCapturedSurfaceVisible(model.showCapturedSurface)
    context.coordinator.controller?.setBoundingBoxVisible(model.showBoundingBox)
  }

  final class Coordinator {
    weak var model: ScannerViewModel?
    var controller: ARScannerController?

    init(model: ScannerViewModel) {
      self.model = model
    }
  }
}

private struct SurfacePreviewData {
  let positions: [SIMD3<Float>]
  let indices: [UInt32]
  let triangleCount: Int
  let dimensionsMM: SIMD3<Double>?
  let componentCount: Int
  let detectedCenterWorld: SIMD3<Float>?
  let detectedHalfExtentsM: SIMD3<Float>?
}

private struct MeshCropContext {
  /// Lower-left corner of the ground footprint in the selected local X/Y/Z coordinate system.
  let referenceOriginWorld: SIMD3<Float>
  let basisWorld: simd_float3x3
  /// Convex 2D polygon in local X/Z coordinates relative to referenceOriginWorld.
  let footprintPolygonXZ: [SIMD2<Float>]
  let footprintWidthM: Float
  let footprintDepthM: Float
  let footprintPaddingM: Float
  let maximumHeightM: Float
  let groundClearanceM: Float
  let minimumObjectHeightM: Float
  let mergeDistanceM: Float
  let removeSupportSurface: Bool
}

private struct CandidateTriangle {
  let world0: SIMD3<Float>
  let world1: SIMD3<Float>
  let world2: SIMD3<Float>
  let local0: SIMD3<Float>
  let local1: SIMD3<Float>
  let local2: SIMD3<Float>
  let centroid: SIMD3<Float>
  let areaM2: Float

  var localMin: SIMD3<Float> {
    simd_min(local0, simd_min(local1, local2))
  }

  var localMax: SIMD3<Float> {
    simd_max(local0, simd_max(local1, local2))
  }
}

private struct SpatialKey: Hashable {
  let x: Int
  let y: Int
  let z: Int
}

private struct VertexLink {
  let triangleIndex: Int
  let point: SIMD3<Float>
}

private struct ComponentInfo {
  let root: Int
  let triangleIndices: [Int]
  let surfaceAreaM2: Float
  let minPoint: SIMD3<Float>
  let maxPoint: SIMD3<Float>
  let centroid: SIMD3<Float>

  var heightM: Float { maxPoint.y - minPoint.y }
  var triangleCount: Int { triangleIndices.count }
}

private struct UnionFind {
  private var parent: [Int]
  private var rank: [UInt8]

  init(count: Int) {
    parent = Array(0..<count)
    rank = Array(repeating: 0, count: count)
  }

  mutating func find(_ value: Int) -> Int {
    if parent[value] != value {
      parent[value] = find(parent[value])
    }
    return parent[value]
  }

  mutating func union(_ a: Int, _ b: Int) {
    var rootA = find(a)
    var rootB = find(b)
    guard rootA != rootB else { return }

    if rank[rootA] < rank[rootB] {
      swap(&rootA, &rootB)
    }
    parent[rootB] = rootA
    if rank[rootA] == rank[rootB] {
      rank[rootA] &+= 1
    }
  }
}

final class ARScannerController: NSObject, ARSessionDelegate {
  private weak var arView: ARView?
  private weak var model: ScannerViewModel?

  private let anchorQueue = DispatchQueue(label: "DimensionalScanner.ARMeshAnchors")
  private let previewQueue = DispatchQueue(
    label: "DimensionalScanner.SurfacePreview", qos: .userInitiated)
  private var meshAnchors: [UUID: ARMeshAnchor] = [:]
  private var captureActive = false

  /// Center used for camera-coverage guidance.
  private var objectCenterWorld: SIMD3<Float>?

  /// Ground datum and STL coordinate origin: lower-left corner of the selected footprint.
  private var objectReferenceOriginWorld: SIMD3<Float>?

  /// Columns are local X/right, local Y/ground-normal, and local Z/depth axes in world coordinates.
  private var partBasisWorld = simd_float3x3(
    SIMD3<Float>(1, 0, 0),
    SIMD3<Float>(0, 1, 0),
    SIMD3<Float>(0, 0, 1)
  )

  private var groundFootprintPolygonXZ: [SIMD2<Float>] = []
  private var groundFootprintWidthM: Float = 0
  private var groundFootprintDepthM: Float = 0
  private var footprintPaddingM: Float = 0.003
  private var maximumObjectHeightM: Float = 0.6
  private var groundClearanceM: Float = 0.003
  private var minimumObjectHeightM: Float = 0.008
  private var objectMergeDistanceM: Float = 0.018

  // RealityKit visual entities.
  private var referenceMarkerAnchors: [AnchorEntity] = []
  private var boundingBoxAnchor: AnchorEntity?
  private var detectedBoundsAnchor: AnchorEntity?
  private var capturedSurfaceAnchor: AnchorEntity?
  private var capturedSurfaceEntity: ModelEntity?
  private var capturedSurfaceVisible = true
  private var boundingBoxVisible = true

  // Live preview and guidance.
  private var previewGenerationInFlight = false
  private var lastPreviewRequestTime: CFTimeInterval = 0
  private var lastReticleUpdateTime: CFTimeInterval = 0
  private let previewInterval: CFTimeInterval = 0.65
  private let reticleInterval: CFTimeInterval = 0.12
  private let maxPreviewTriangles = 18_000
  private let coverageSectorCount = 16
  private var coveredCameraSectors: Set<Int> = []

  init(arView: ARView, model: ScannerViewModel) {
    self.arView = arView
    self.model = model
    super.init()
    arView.session.delegate = self
  }

  @MainActor
  func startSession(showMeshOverlay: Bool) {
    guard ARWorldTrackingConfiguration.isSupported else {
      postStatus("AR world tracking is not supported on this device.")
      return
    }
    guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
      postStatus("LiDAR scene reconstruction is unavailable on this device.")
      return
    }

    let configuration = ARWorldTrackingConfiguration()
    configuration.planeDetection = [.horizontal, .vertical]
    configuration.environmentTexturing = .automatic

    if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
      configuration.sceneReconstruction = .meshWithClassification
    } else {
      configuration.sceneReconstruction = .mesh
    }

    if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
      configuration.frameSemantics.insert(.smoothedSceneDepth)
    } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
      configuration.frameSemantics.insert(.sceneDepth)
    }

    anchorQueue.sync {
      meshAnchors.removeAll()
      captureActive = false
    }
    arView?.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    setMeshOverlayVisible(showMeshOverlay)
    postStatus("Capture four ground corners clockwise around the object.")
  }

  @MainActor
  func resetSession() {
    clearReferenceVisuals()
    coveredCameraSectors.removeAll()
    model?.scanCoveragePercent = 0
    model?.capturedSurfaceTriangleCount = 0
    startSession(showMeshOverlay: model?.showMeshOverlay ?? false)
  }

  @MainActor
  func setMeshOverlayVisible(_ visible: Bool) {
    guard let arView else { return }
    if visible {
      arView.debugOptions.insert(.showSceneUnderstanding)
    } else {
      arView.debugOptions.remove(.showSceneUnderstanding)
    }
  }

  @MainActor
  func setCapturedSurfaceVisible(_ visible: Bool) {
    capturedSurfaceVisible = visible
    capturedSurfaceAnchor?.isEnabled = visible
  }

  @MainActor
  func setBoundingBoxVisible(_ visible: Bool) {
    boundingBoxVisible = visible
    boundingBoxAnchor?.isEnabled = visible
    detectedBoundsAnchor?.isEnabled = visible
    for marker in referenceMarkerAnchors {
      marker.isEnabled = visible
    }
  }

  @MainActor
  func setObjectCenterFromScreenCenter() {
    guard let point = captureWorldPointFromScreenCenter() else {
      postStatus("Could not set a manual center. Aim at a visible surface and try again.")
      return
    }

    objectCenterWorld = point
    objectReferenceOriginWorld = point
    groundFootprintPolygonXZ = []
    groundFootprintWidthM = 0
    groundFootprintDepthM = 0
    updatePartBasisFromCurrentCamera()
    postStatus("Manual center set. Four ground corners give better object isolation.")
  }

  @MainActor
  func captureWorldPointFromScreenCenter() -> SIMD3<Float>? {
    guard let arView else { return nil }

    if let depthPoint = worldPointFromSceneDepthAtScreenCenter(in: arView) {
      return depthPoint
    }

    let screenPoint = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
    let raycastResults = arView.raycast(
      from: screenPoint,
      allowing: .estimatedPlane,
      alignment: .any
    )
    return raycastResults.first?.worldTransform.translationVector
  }

  @MainActor
  func showReferencePoint(at point: SIMD3<Float>, index: Int) {
    guard let arView else { return }

    let colors: [UIColor] = [
      .systemCyan,
      .systemBlue,
      .systemIndigo,
      .systemPurple,
    ]
    let color = colors.indices.contains(index) ? colors[index] : .white
    let sphere = ModelEntity(
      mesh: .generateSphere(radius: 0.0022),
      materials: [SimpleMaterial(color: color, isMetallic: false)]
    )
    let anchor = AnchorEntity(world: point)
    anchor.addChild(sphere)
    anchor.isEnabled = boundingBoxVisible
    arView.scene.addAnchor(anchor)
    referenceMarkerAnchors.append(anchor)
  }

  @MainActor
  func removeLastReferencePointMarker() {
    guard let arView, let anchor = referenceMarkerAnchors.popLast() else { return }
    arView.scene.removeAnchor(anchor)
  }

  @MainActor
  func clearReferenceVisuals() {
    guard let arView else { return }

    for anchor in referenceMarkerAnchors {
      arView.scene.removeAnchor(anchor)
    }
    referenceMarkerAnchors.removeAll()

    if let boundingBoxAnchor {
      arView.scene.removeAnchor(boundingBoxAnchor)
    }
    if let detectedBoundsAnchor {
      arView.scene.removeAnchor(detectedBoundsAnchor)
    }
    if let capturedSurfaceAnchor {
      arView.scene.removeAnchor(capturedSurfaceAnchor)
    }

    boundingBoxAnchor = nil
    detectedBoundsAnchor = nil
    capturedSurfaceAnchor = nil
    capturedSurfaceEntity = nil
    objectCenterWorld = nil
    objectReferenceOriginWorld = nil
    groundFootprintPolygonXZ = []
    groundFootprintWidthM = 0
    groundFootprintDepthM = 0
    coveredCameraSectors.removeAll()

    anchorQueue.sync {
      captureActive = false
    }
  }

  @MainActor
  func invalidateBoundingBox() {
    guard let arView else { return }

    if let boundingBoxAnchor {
      arView.scene.removeAnchor(boundingBoxAnchor)
    }
    if let detectedBoundsAnchor {
      arView.scene.removeAnchor(detectedBoundsAnchor)
    }
    if let capturedSurfaceAnchor {
      arView.scene.removeAnchor(capturedSurfaceAnchor)
    }
    boundingBoxAnchor = nil
    detectedBoundsAnchor = nil
    capturedSurfaceAnchor = nil
    capturedSurfaceEntity = nil
    objectCenterWorld = nil
    objectReferenceOriginWorld = nil
    groundFootprintPolygonXZ = []
    groundFootprintWidthM = 0
    groundFootprintDepthM = 0
    coveredCameraSectors.removeAll()
    model?.clearLiveMeshDimensions()
    model?.scanCoveragePercent = 0
  }

  /// Compatibility alias used by previous patches.
  @MainActor
  func clearSixPointReference() {
    clearReferenceVisuals()
  }

  /// Four points define a convex footprint on one ground/support plane.
  @MainActor
  func applyFourPointGroundArea(
    points: [SIMD3<Float>],
    paddingMM: Double,
    maximumHeightMM: Double,
    groundClearanceMM: Double,
    minimumObjectHeightMM: Double,
    mergeDistanceMM: Double
  ) -> GroundAreaSummary? {
    guard points.count >= 4 else { return nil }
    let input = Array(points.prefix(4))
    let centroid = input.reduce(SIMD3<Float>(repeating: 0), +) / Float(input.count)

    var rawNormal = SIMD3<Float>(repeating: 0)
    for index in input.indices {
      let current = input[index] - centroid
      let next = input[(index + 1) % input.count] - centroid
      rawNormal += simd_cross(current, next)
    }
    guard simd_length(rawNormal) > 0.0001 else { return nil }

    var upAxis = simd_normalize(rawNormal)
    let worldUp = SIMD3<Float>(0, 1, 0)
    if simd_dot(upAxis, worldUp) < 0 {
      upAxis = -upAxis
    }
    let upAlignment = max(min(simd_dot(upAxis, worldUp), 1), -1)
    let tiltDegrees = acos(Double(upAlignment)) * 180 / Double.pi
    guard tiltDegrees < 55 else { return nil }

    let projected = input.map { point in
      point - upAxis * simd_dot(point - centroid, upAxis)
    }
    let maximumResidual = zip(input, projected).map { pair in
      simd_length(pair.0 - pair.1)
    }.max() ?? 0
    guard maximumResidual < 0.025 else { return nil }

    var longestEdge = SIMD3<Float>(repeating: 0)
    var longestLength: Float = 0
    for index in projected.indices {
      let edge = projected[(index + 1) % projected.count] - projected[index]
      let planar = edge - upAxis * simd_dot(edge, upAxis)
      let length = simd_length(planar)
      if length > longestLength {
        longestLength = length
        longestEdge = planar
      }
    }
    guard longestLength > 0.015 else { return nil }

    var xAxis = simd_normalize(longestEdge)
    var zAxis = simd_cross(xAxis, upAxis)
    guard simd_length(zAxis) > 0.0001 else { return nil }
    zAxis = simd_normalize(zAxis)
    xAxis = simd_normalize(simd_cross(upAxis, zAxis))

    let localUnsorted = projected.map { point -> SIMD2<Float> in
      let delta = point - centroid
      return SIMD2<Float>(simd_dot(delta, xAxis), simd_dot(delta, zAxis))
    }
    guard let hull = Self.convexHull(localUnsorted), hull.count == 4 else { return nil }

    let minX = hull.map(\.x).min() ?? 0
    let maxX = hull.map(\.x).max() ?? 0
    let minZ = hull.map(\.y).min() ?? 0
    let maxZ = hull.map(\.y).max() ?? 0
    let widthM = maxX - minX
    let depthM = maxZ - minZ
    let areaM2 = abs(Self.signedArea(hull))
    guard widthM > 0.02, depthM > 0.02, areaM2 > 0.0004 else { return nil }

    let centerX = (minX + maxX) / 2
    let centerZ = (minZ + maxZ) / 2
    let groundCenterWorld = centroid + xAxis * centerX + zAxis * centerZ
    let originWorld = centroid + xAxis * minX + zAxis * minZ
    let polygonFromOrigin = hull.map { SIMD2<Float>($0.x - minX, $0.y - minZ) }

    partBasisWorld = simd_float3x3(xAxis, upAxis, zAxis)
    objectReferenceOriginWorld = originWorld
    objectCenterWorld = groundCenterWorld + upAxis * Float(maximumHeightMM / 2000)
    groundFootprintPolygonXZ = polygonFromOrigin
    groundFootprintWidthM = widthM
    groundFootprintDepthM = depthM
    footprintPaddingM = max(Float(paddingMM / 1000), 0)
    maximumObjectHeightM = max(Float(maximumHeightMM / 1000), 0.03)
    groundClearanceM = max(Float(groundClearanceMM / 1000), 0.001)
    minimumObjectHeightM = max(Float(minimumObjectHeightMM / 1000), 0.003)
    objectMergeDistanceM = max(Float(mergeDistanceMM / 1000), 0.006)

    renderGroundFootprint(polygon: polygonFromOrigin)
    requestSurfacePreview(force: true)

    return GroundAreaSummary(
      widthMM: Double(widthM * 1000),
      depthMM: Double(depthM * 1000),
      areaMM2: Double(areaM2 * 1_000_000),
      planeTiltDegrees: tiltDegrees,
      paddingMM: paddingMM
    )
  }

  @MainActor
  func beginCapture(resetCoverage: Bool) {
    if resetCoverage {
      coveredCameraSectors.removeAll()
      model?.scanCoveragePercent = 0
    }
    let currentMeshAnchors =
      arView?.session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
    anchorQueue.sync {
      captureActive = true
      for anchor in currentMeshAnchors {
        meshAnchors[anchor.identifier] = anchor
      }
    }
    requestSurfacePreview(force: true)
  }

  @MainActor
  func endCapture() {
    anchorQueue.sync {
      captureActive = false
    }
    requestSurfacePreview(force: true)
  }

  @MainActor
  func makeDetectedObjectMesh(
    volumeXMM: Double,
    maximumHeightMM: Double,
    volumeZMM: Double
  ) -> TriangleMesh? {
    guard
      let context = makeCropContext(
        volumeXMM: volumeXMM,
        maximumHeightMM: maximumHeightMM,
        volumeZMM: volumeZMM
      )
    else {
      return nil
    }

    let anchors = anchorQueue.sync { Array(meshAnchors.values) }
    guard !anchors.isEmpty else { return nil }
    let candidates = Self.collectCandidateTriangles(anchors: anchors, context: context)
    let isolation = Self.isolateObjectTriangles(candidates, context: context)
    guard !isolation.triangles.isEmpty else { return nil }

    var output = TriangleMesh()
    output.vertices.reserveCapacity(isolation.triangles.count * 3)
    output.faces.reserveCapacity(isolation.triangles.count)

    for triangle in isolation.triangles {
      let baseIndex = output.vertices.count
      output.vertices.append(
        Vector3D(
          x: Double(triangle.local0.x) * 1000,
          y: Double(triangle.local0.y) * 1000,
          z: Double(triangle.local0.z) * 1000))
      output.vertices.append(
        Vector3D(
          x: Double(triangle.local1.x) * 1000,
          y: Double(triangle.local1.y) * 1000,
          z: Double(triangle.local1.z) * 1000))
      output.vertices.append(
        Vector3D(
          x: Double(triangle.local2.x) * 1000,
          y: Double(triangle.local2.y) * 1000,
          z: Double(triangle.local2.z) * 1000))
      output.faces.append(TriangleFace(baseIndex, baseIndex + 1, baseIndex + 2))
    }
    return output
  }

  /// Compatibility alias used by earlier view-model code.
  @MainActor
  func makeCroppedObjectMesh(
    volumeXMM: Double,
    volumeYMM: Double,
    volumeZMM: Double
  ) -> TriangleMesh? {
    makeDetectedObjectMesh(
      volumeXMM: volumeXMM,
      maximumHeightMM: volumeYMM,
      volumeZMM: volumeZMM
    )
  }

  @MainActor
  private func makeCropContext(
    volumeXMM: Double,
    maximumHeightMM: Double,
    volumeZMM: Double
  ) -> MeshCropContext? {
    if let origin = objectReferenceOriginWorld, groundFootprintPolygonXZ.count >= 3 {
      return MeshCropContext(
        referenceOriginWorld: origin,
        basisWorld: partBasisWorld,
        footprintPolygonXZ: groundFootprintPolygonXZ,
        footprintWidthM: groundFootprintWidthM,
        footprintDepthM: groundFootprintDepthM,
        footprintPaddingM: footprintPaddingM,
        maximumHeightM: maximumObjectHeightM,
        groundClearanceM: groundClearanceM,
        minimumObjectHeightM: minimumObjectHeightM,
        mergeDistanceM: objectMergeDistanceM,
        removeSupportSurface: true
      )
    }

    guard let center = objectCenterWorld else { return nil }
    let widthM = max(Float(volumeXMM / 1000), 0.02)
    let depthM = max(Float(volumeZMM / 1000), 0.02)
    let heightM = max(Float(maximumHeightMM / 1000), 0.03)
    let origin = center
      - partBasisWorld.columns.0 * (widthM / 2)
      - partBasisWorld.columns.2 * (depthM / 2)
    return MeshCropContext(
      referenceOriginWorld: origin,
      basisWorld: partBasisWorld,
      footprintPolygonXZ: [
        SIMD2<Float>(0, 0),
        SIMD2<Float>(widthM, 0),
        SIMD2<Float>(widthM, depthM),
        SIMD2<Float>(0, depthM),
      ],
      footprintWidthM: widthM,
      footprintDepthM: depthM,
      footprintPaddingM: 0,
      maximumHeightM: heightM,
      groundClearanceM: 0,
      minimumObjectHeightM: 0.003,
      mergeDistanceM: objectMergeDistanceM,
      removeSupportSurface: false
    )
  }

  private static func collectCandidateTriangles(
    anchors: [ARMeshAnchor],
    context: MeshCropContext
  ) -> [CandidateTriangle] {
    var output: [CandidateTriangle] = []
    output.reserveCapacity(20_000)

    for anchor in anchors {
      let geometry = anchor.geometry
      let transform = anchor.transform

      for faceIndex in 0..<geometry.faces.count {
        guard let indices = geometry.triangleIndices(faceIndex: faceIndex) else { continue }

        let world0 = transform.transformPoint(geometry.vertex(at: indices.0))
        let world1 = transform.transformPoint(geometry.vertex(at: indices.1))
        let world2 = transform.transformPoint(geometry.vertex(at: indices.2))

        let local0 = worldToLocal(
          world0, center: context.referenceOriginWorld, basis: context.basisWorld)
        let local1 = worldToLocal(
          world1, center: context.referenceOriginWorld, basis: context.basisWorld)
        let local2 = worldToLocal(
          world2, center: context.referenceOriginWorld, basis: context.basisWorld)
        let centroid = (local0 + local1 + local2) / 3

        let centroidXZ = SIMD2<Float>(centroid.x, centroid.z)
        guard pointInsidePolygon(centroidXZ, polygon: context.footprintPolygonXZ) else {
          continue
        }

        let paddedInside = [local0, local1, local2].allSatisfy { point in
          pointInsideOrNearPolygon(
            SIMD2<Float>(point.x, point.z),
            polygon: context.footprintPolygonXZ,
            margin: context.footprintPaddingM
          )
        }
        guard paddedInside else { continue }

        let minimumY = min(local0.y, min(local1.y, local2.y))
        let maximumY = max(local0.y, max(local1.y, local2.y))
        guard centroid.y <= context.maximumHeightM,
          maximumY <= context.maximumHeightM + max(context.footprintPaddingM, 0.004),
          minimumY >= -max(context.groundClearanceM * 2, 0.008)
        else {
          continue
        }

        let classification = geometry.classificationOf(faceWithIndex: faceIndex)
        if shouldRejectSupportTriangle(
          local0,
          local1,
          local2,
          classification: classification,
          context: context
        ) {
          continue
        }

        let cross = simd_cross(local1 - local0, local2 - local0)
        let areaM2 = simd_length(cross) * 0.5
        guard areaM2 > 0.0000001 else { continue }

        output.append(
          CandidateTriangle(
            world0: world0,
            world1: world1,
            world2: world2,
            local0: local0,
            local1: local1,
            local2: local2,
            centroid: centroid,
            areaM2: areaM2
          ))
      }
    }
    return output
  }

  private static func shouldRejectSupportTriangle(
    _ a: SIMD3<Float>,
    _ b: SIMD3<Float>,
    _ c: SIMD3<Float>,
    classification: ARMeshClassification,
    context: MeshCropContext
  ) -> Bool {
    guard context.removeSupportSurface else { return false }

    let minY = min(a.y, min(b.y, c.y))
    let maxY = max(a.y, max(b.y, c.y))
    let centroidY = (a.y + b.y + c.y) / 3

    if maxY < context.groundClearanceM || minY < -max(context.groundClearanceM * 2, 0.008) {
      return true
    }

    if classification == .floor || classification == .table {
      if centroidY < max(context.groundClearanceM * 4, 0.018) {
        return true
      }
    }

    let normal = simd_cross(b - a, c - a)
    if simd_length(normal) > 0.000001 {
      let normalized = simd_normalize(normal)
      let isNearlyHorizontal = abs(normalized.y) > 0.88
      if isNearlyHorizontal && centroidY < max(context.groundClearanceM * 2.5, 0.010) {
        return true
      }
    }
    return false
  }

  private static func isolateObjectTriangles(
    _ candidates: [CandidateTriangle],
    context: MeshCropContext
  ) -> (triangles: [CandidateTriangle], componentCount: Int) {
    guard !candidates.isEmpty else { return ([], 0) }
    guard candidates.count >= 4 else {
      return (candidates, candidates.isEmpty ? 0 : 1)
    }

    var unionFind = UnionFind(count: candidates.count)
    let tolerance = max(context.mergeDistanceM, 0.008)
    let cellSize = max(min(tolerance * 0.65, 0.014), 0.005)
    let neighborRadius = max(Int(ceil(tolerance / cellSize)), 1)
    let toleranceSquared = tolerance * tolerance
    var cells: [SpatialKey: [VertexLink]] = [:]
    cells.reserveCapacity(candidates.count * 2)

    for (triangleIndex, triangle) in candidates.enumerated() {
      for point in [triangle.local0, triangle.local1, triangle.local2] {
        let key = spatialKey(for: point, cellSize: cellSize)
        for dx in -neighborRadius...neighborRadius {
          for dy in -neighborRadius...neighborRadius {
            for dz in -neighborRadius...neighborRadius {
              let neighbor = SpatialKey(x: key.x + dx, y: key.y + dy, z: key.z + dz)
              guard let links = cells[neighbor] else { continue }
              for link in links.prefix(16)
              where simd_length_squared(link.point - point) <= toleranceSquared
              {
                unionFind.union(triangleIndex, link.triangleIndex)
              }
            }
          }
        }
        if cells[key, default: []].count < 20 {
          cells[key, default: []].append(VertexLink(triangleIndex: triangleIndex, point: point))
        }
      }
    }

    var grouped: [Int: [Int]] = [:]
    grouped.reserveCapacity(candidates.count / 3)
    for index in candidates.indices {
      grouped[unionFind.find(index), default: []].append(index)
    }

    var components: [ComponentInfo] = []
    components.reserveCapacity(grouped.count)
    for (root, indices) in grouped {
      var minPoint = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
      var maxPoint = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
      var area: Float = 0
      var weightedCentroid = SIMD3<Float>(repeating: 0)

      for index in indices {
        let triangle = candidates[index]
        minPoint = simd_min(minPoint, triangle.localMin)
        maxPoint = simd_max(maxPoint, triangle.localMax)
        area += triangle.areaM2
        weightedCentroid += triangle.centroid * triangle.areaM2
      }
      let centroid = area > 0 ? weightedCentroid / area : (minPoint + maxPoint) / 2
      components.append(
        ComponentInfo(
          root: root,
          triangleIndices: indices,
          surfaceAreaM2: area,
          minPoint: minPoint,
          maxPoint: maxPoint,
          centroid: centroid
        ))
    }

    let valid = components.filter { component in
      component.triangleCount >= 3
        && component.surfaceAreaM2 > 0.000005
        && component.maxPoint.y >= context.minimumObjectHeightM
        && component.heightM >= context.minimumObjectHeightM * 0.45
    }

    guard !valid.isEmpty else {
      let totalMin = candidates.reduce(SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)) {
        simd_min($0, $1.localMin)
      }
      let totalMax = candidates.reduce(SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)) {
        simd_max($0, $1.localMax)
      }
      guard totalMax.y - totalMin.y >= context.minimumObjectHeightM else { return ([], 0) }
      return (candidates, 1)
    }

    let footprintCenter = SIMD2<Float>(context.footprintWidthM / 2, context.footprintDepthM / 2)
    let footprintDiagonal = max(hypot(context.footprintWidthM, context.footprintDepthM), 0.03)

    guard let primary = valid.max(by: { lhs, rhs in
      componentScore(lhs, footprintCenter: footprintCenter, footprintDiagonal: footprintDiagonal)
        < componentScore(rhs, footprintCenter: footprintCenter, footprintDiagonal: footprintDiagonal)
    }) else {
      return ([], 0)
    }

    var selectedRoots: Set<Int> = [primary.root]
    var changed = true
    while changed {
      changed = false
      for component in valid where !selectedRoots.contains(component.root) {
        let shouldMerge = valid.contains { selected in
          selectedRoots.contains(selected.root)
            && componentBoxDistance(component, selected) <= context.mergeDistanceM * 1.5
        }
        let meaningful = component.surfaceAreaM2 >= primary.surfaceAreaM2 * 0.008
          || component.heightM >= context.minimumObjectHeightM
        if shouldMerge && meaningful {
          selectedRoots.insert(component.root)
          changed = true
        }
      }
    }

    let selectedIndices = valid
      .filter { selectedRoots.contains($0.root) }
      .flatMap(\.triangleIndices)
    let selectedSet = Set(selectedIndices)
    let selectedTriangles = candidates.enumerated().compactMap { index, triangle in
      selectedSet.contains(index) ? triangle : nil
    }
    return (selectedTriangles, selectedRoots.count)
  }

  private static func componentScore(
    _ component: ComponentInfo,
    footprintCenter: SIMD2<Float>,
    footprintDiagonal: Float
  ) -> Float {
    let horizontal = SIMD2<Float>(component.centroid.x, component.centroid.z)
    let distance = simd_length(horizontal - footprintCenter)
    let centerWeight = max(0.35, 1 - distance / (footprintDiagonal * 0.8))
    let heightWeight = 1 + min(component.heightM / 0.10, 2.5)
    return component.surfaceAreaM2 * heightWeight * centerWeight
  }

  private static func componentBoxDistance(_ a: ComponentInfo, _ b: ComponentInfo) -> Float {
    let dx = max(max(a.minPoint.x - b.maxPoint.x, b.minPoint.x - a.maxPoint.x), 0)
    let dy = max(max(a.minPoint.y - b.maxPoint.y, b.minPoint.y - a.maxPoint.y), 0)
    let dz = max(max(a.minPoint.z - b.maxPoint.z, b.minPoint.z - a.maxPoint.z), 0)
    return sqrt(dx * dx + dy * dy + dz * dz)
  }

  private static func spatialKey(for point: SIMD3<Float>, cellSize: Float) -> SpatialKey {
    SpatialKey(
      x: Int(floor(point.x / cellSize)),
      y: Int(floor(point.y / cellSize)),
      z: Int(floor(point.z / cellSize))
    )
  }

  private static func worldToLocal(
    _ point: SIMD3<Float>,
    center: SIMD3<Float>,
    basis: simd_float3x3
  ) -> SIMD3<Float> {
    let delta = point - center
    return SIMD3<Float>(
      simd_dot(delta, basis.columns.0),
      simd_dot(delta, basis.columns.1),
      simd_dot(delta, basis.columns.2)
    )
  }

  @MainActor
  private func requestSurfacePreview(force: Bool = false) {
    guard
      let context = makeCropContext(
        volumeXMM: model?.scanVolumeXMM ?? 200,
        maximumHeightMM: model?.maximumObjectHeightMM ?? 600,
        volumeZMM: model?.scanVolumeZMM ?? 200
      )
    else {
      return
    }

    let now = CACurrentMediaTime()
    guard force || now - lastPreviewRequestTime >= previewInterval else { return }
    guard !previewGenerationInFlight else { return }

    lastPreviewRequestTime = now
    previewGenerationInFlight = true
    let anchors = anchorQueue.sync { Array(meshAnchors.values) }
    let maxTriangles = maxPreviewTriangles

    previewQueue.async { [weak self] in
      let data = Self.buildSurfacePreview(
        anchors: anchors,
        context: context,
        maxTriangles: maxTriangles
      )

      Task { @MainActor [weak self] in
        guard let self else { return }
        self.previewGenerationInFlight = false
        self.applySurfacePreview(data)
      }
    }
  }

  private static func buildSurfacePreview(
    anchors: [ARMeshAnchor],
    context: MeshCropContext,
    maxTriangles: Int
  ) -> SurfacePreviewData {
    let candidates = collectCandidateTriangles(anchors: anchors, context: context)
    let isolation = isolateObjectTriangles(candidates, context: context)
    let triangles = isolation.triangles

    guard !triangles.isEmpty else {
      return SurfacePreviewData(
        positions: [],
        indices: [],
        triangleCount: 0,
        dimensionsMM: nil,
        componentCount: 0,
        detectedCenterWorld: nil,
        detectedHalfExtentsM: nil
      )
    }

    var minReference = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
    var maxReference = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
    for triangle in triangles {
      minReference = simd_min(minReference, triangle.localMin)
      maxReference = simd_max(maxReference, triangle.localMax)
    }

    let outputCount = min(triangles.count, maxTriangles)
    let step = Double(triangles.count) / Double(outputCount)
    var positions: [SIMD3<Float>] = []
    var indices: [UInt32] = []
    positions.reserveCapacity(outputCount * 3)
    indices.reserveCapacity(outputCount * 3)

    for outputIndex in 0..<outputCount {
      let sourceIndex = min(Int(Double(outputIndex) * step), triangles.count - 1)
      let triangle = triangles[sourceIndex]
      let base = UInt32(positions.count)
      positions.append(triangle.world0)
      positions.append(triangle.world1)
      positions.append(triangle.world2)
      indices.append(base)
      indices.append(base + 1)
      indices.append(base + 2)
    }

    let sizeM = maxReference - minReference
    let dimensionsMM = SIMD3<Double>(
      Double(sizeM.x) * 1000,
      Double(max(maxReference.y, sizeM.y)) * 1000,
      Double(sizeM.z) * 1000
    )
    let centerLocal = (minReference + maxReference) / 2
    let centerWorld = localToWorld(
      centerLocal,
      origin: context.referenceOriginWorld,
      basis: context.basisWorld
    )

    return SurfacePreviewData(
      positions: positions,
      indices: indices,
      triangleCount: triangles.count,
      dimensionsMM: dimensionsMM,
      componentCount: isolation.componentCount,
      detectedCenterWorld: centerWorld,
      detectedHalfExtentsM: sizeM / 2
    )
  }

  @MainActor
  private func applySurfacePreview(_ data: SurfacePreviewData) {
    if let dimensions = data.dimensionsMM {
      model?.updateLiveMeshDimensions(
        widthMM: dimensions.x,
        heightMM: dimensions.y,
        depthMM: dimensions.z,
        triangleCount: data.triangleCount,
        componentCount: data.componentCount
      )
    } else {
      model?.clearLiveMeshDimensions()
    }
    guard let arView else { return }

    if let center = data.detectedCenterWorld, let half = data.detectedHalfExtentsM {
      renderDetectedBounds(center: center, halfExtents: half)
    } else if let detectedBoundsAnchor {
      arView.scene.removeAnchor(detectedBoundsAnchor)
      self.detectedBoundsAnchor = nil
    }

    if data.positions.isEmpty {
      capturedSurfaceEntity?.removeFromParent()
      capturedSurfaceEntity = nil
      return
    }

    do {
      var descriptor = MeshDescriptor(name: "DetectedObjectSurface")
      descriptor.positions = MeshBuffers.Positions(data.positions)
      descriptor.primitives = .triangles(data.indices)
      let mesh = try MeshResource.generate(from: [descriptor])
      let material = SimpleMaterial(
        color: UIColor.systemTeal.withAlphaComponent(0.50),
        isMetallic: false
      )
      let entity = ModelEntity(mesh: mesh, materials: [material])

      let anchor: AnchorEntity
      if let existing = capturedSurfaceAnchor {
        anchor = existing
        capturedSurfaceEntity?.removeFromParent()
      } else {
        anchor = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
        capturedSurfaceAnchor = anchor
        arView.scene.addAnchor(anchor)
      }

      anchor.addChild(entity)
      anchor.isEnabled = capturedSurfaceVisible
      capturedSurfaceEntity = entity
    } catch {
      postStatus("Object surface preview could not be rendered: \(error.localizedDescription)")
    }
  }

  @MainActor
  private func renderGroundFootprint(polygon: [SIMD2<Float>]) {
    guard let arView, let origin = objectReferenceOriginWorld, polygon.count >= 3 else { return }
    if let boundingBoxAnchor {
      arView.scene.removeAnchor(boundingBoxAnchor)
    }

    let root = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
    let edgeMaterial = SimpleMaterial(
      color: UIColor.systemBlue.withAlphaComponent(0.95),
      isMetallic: false
    )
    let cornerMaterial = SimpleMaterial(color: .white, isMetallic: false)
    let thickness: Float = 0.0010

    let worldCorners = polygon.map { point in
      Self.localToWorld(
        SIMD3<Float>(point.x, 0.001, point.y),
        origin: origin,
        basis: partBasisWorld
      )
    }

    for index in worldCorners.indices {
      let start = worldCorners[index]
      let end = worldCorners[(index + 1) % worldCorners.count]
      addLine(
        from: start,
        to: end,
        thickness: thickness,
        material: edgeMaterial,
        parent: root
      )
    }

    for corner in worldCorners {
      let dot = ModelEntity(
        mesh: .generateSphere(radius: 0.0016),
        materials: [cornerMaterial]
      )
      dot.position = corner
      root.addChild(dot)
    }

    // A faint fill makes the selected 2D scan area visible without blocking the camera.
    if worldCorners.count == 4 {
      do {
        var descriptor = MeshDescriptor(name: "GroundScanArea")
        descriptor.positions = MeshBuffers.Positions(worldCorners)
        descriptor.primitives = .triangles([UInt32(0), 1, 2, 0, 2, 3])
        let mesh = try MeshResource.generate(from: [descriptor])
        let fill = SimpleMaterial(
          color: UIColor.systemBlue.withAlphaComponent(0.08),
          isMetallic: false
        )
        root.addChild(ModelEntity(mesh: mesh, materials: [fill]))
      } catch {
        // The outline remains usable even if the optional translucent fill cannot be generated.
      }
    }

    root.isEnabled = boundingBoxVisible
    arView.scene.addAnchor(root)
    boundingBoxAnchor = root
  }

  @MainActor
  private func renderDetectedBounds(center: SIMD3<Float>, halfExtents: SIMD3<Float>) {
    guard let arView else { return }
    if let detectedBoundsAnchor {
      arView.scene.removeAnchor(detectedBoundsAnchor)
    }

    let root = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
    let material = SimpleMaterial(
      color: UIColor.systemGreen.withAlphaComponent(0.90),
      isMetallic: false
    )
    let smallest = max(min(halfExtents.x, min(halfExtents.y, halfExtents.z)), 0.005)
    let thickness = max(smallest * 0.010, 0.0008)

    let signs: [Float] = [-1, 1]
    var corners: [SIMD3<Float>] = []
    for sx in signs {
      for sy in signs {
        for sz in signs {
          let local = SIMD3<Float>(sx * halfExtents.x, sy * halfExtents.y, sz * halfExtents.z)
          corners.append(
            center
              + partBasisWorld.columns.0 * local.x
              + partBasisWorld.columns.1 * local.y
              + partBasisWorld.columns.2 * local.z
          )
        }
      }
    }

    let edgePairs = [
      (0, 1), (0, 2), (0, 4),
      (1, 3), (1, 5),
      (2, 3), (2, 6),
      (3, 7),
      (4, 5), (4, 6),
      (5, 7), (6, 7),
    ]
    for pair in edgePairs {
      addLine(
        from: corners[pair.0],
        to: corners[pair.1],
        thickness: thickness,
        material: material,
        parent: root
      )
    }

    root.isEnabled = boundingBoxVisible
    arView.scene.addAnchor(root)
    detectedBoundsAnchor = root
  }

  private func addLine(
    from start: SIMD3<Float>,
    to end: SIMD3<Float>,
    thickness: Float,
    material: SimpleMaterial,
    parent: Entity
  ) {
    let delta = end - start
    let length = simd_length(delta)
    guard length > 0.0001 else { return }

    let edge = ModelEntity(
      mesh: .generateBox(size: SIMD3<Float>(thickness, length, thickness)),
      materials: [material]
    )
    edge.position = (start + end) / 2
    edge.orientation = simd_quatf(
      from: SIMD3<Float>(0, 1, 0),
      to: simd_normalize(delta)
    )
    parent.addChild(edge)
  }

  @MainActor
  private func updateReticleState() {
    guard let arView else { return }
    let point = captureWorldPointFromScreenCenter()
    model?.reticleHasSurface = point != nil

    if let point, let frame = arView.session.currentFrame {
      let camera = frame.camera.transform.translationVector
      model?.reticleDistanceMM = Double(simd_length(point - camera) * 1000)
    } else {
      model?.reticleDistanceMM = nil
    }
  }

  @MainActor
  private func updateCoverage(cameraPosition: SIMD3<Float>) {
    guard let center = objectCenterWorld else { return }
    let delta = cameraPosition - center
    let x = simd_dot(delta, partBasisWorld.columns.0)
    let z = simd_dot(delta, partBasisWorld.columns.2)
    guard abs(x) + abs(z) > 0.02 else { return }

    var angle = atan2(Double(z), Double(x))
    if angle < 0 { angle += 2 * Double.pi }
    let sector = min(
      Int(angle / (2 * Double.pi) * Double(coverageSectorCount)),
      coverageSectorCount - 1
    )
    coveredCameraSectors.insert(sector)
    model?.scanCoveragePercent =
      Double(coveredCameraSectors.count) / Double(coverageSectorCount) * 100
  }

  private func updatePartBasisFromCurrentCamera() {
    guard let frame = arView?.session.currentFrame else { return }
    let cameraTransform = frame.camera.transform
    var right = SIMD3<Float>(cameraTransform.columns.0.x, 0, cameraTransform.columns.0.z)
    if simd_length(right) < 0.0001 {
      right = SIMD3<Float>(1, 0, 0)
    } else {
      right = simd_normalize(right)
    }

    let up = SIMD3<Float>(0, 1, 0)
    var depth = simd_cross(right, up)
    if simd_length(depth) < 0.0001 {
      depth = SIMD3<Float>(0, 0, 1)
    } else {
      depth = simd_normalize(depth)
    }
    right = simd_normalize(simd_cross(up, depth))
    partBasisWorld = simd_float3x3(right, up, depth)
  }

  @MainActor
  private func worldPointFromSceneDepthAtScreenCenter(in arView: ARView) -> SIMD3<Float>? {
    guard let frame = arView.session.currentFrame else { return nil }
    guard let depthMap = (frame.smoothedSceneDepth ?? frame.sceneDepth)?.depthMap else {
      return nil
    }

    CVPixelBufferLockBaseAddress(depthMap, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
    let width = CVPixelBufferGetWidth(depthMap)
    let height = CVPixelBufferGetHeight(depthMap)
    let rowBytes = CVPixelBufferGetBytesPerRow(depthMap)
    let centerX = width / 2
    let centerY = height / 2
    let radius = 2
    var samples: [Float] = []

    for y in max(0, centerY - radius)...min(height - 1, centerY + radius) {
      for x in max(0, centerX - radius)...min(width - 1, centerX + radius) {
        let offset = y * rowBytes + x * MemoryLayout<Float32>.size
        let value =
          baseAddress
          .advanced(by: offset)
          .assumingMemoryBound(to: Float32.self)
          .pointee
        let depth = Float(value)
        if depth.isFinite && depth > 0.05 && depth < 5.0 {
          samples.append(depth)
        }
      }
    }

    guard !samples.isEmpty else { return nil }
    samples.sort()
    let depth = samples[samples.count / 2]

    let cameraTransform = frame.camera.transform
    let cameraPosition = cameraTransform.translationVector
    let forward = -cameraTransform.zAxis
    return cameraPosition + simd_normalize(forward) * depth
  }

  private static func convexHull(_ points: [SIMD2<Float>]) -> [SIMD2<Float>]? {
    let unique = Array(Set(points.map { QuantizedPoint2D($0) })).map(\.point)
    guard unique.count >= 3 else { return nil }
    let sorted = unique.sorted {
      if abs($0.x - $1.x) > 0.000001 { return $0.x < $1.x }
      return $0.y < $1.y
    }

    func cross(_ origin: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
      let oa = a - origin
      let ob = b - origin
      return oa.x * ob.y - oa.y * ob.x
    }

    var lower: [SIMD2<Float>] = []
    for point in sorted {
      while lower.count >= 2
        && cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0
      {
        lower.removeLast()
      }
      lower.append(point)
    }

    var upper: [SIMD2<Float>] = []
    for point in sorted.reversed() {
      while upper.count >= 2
        && cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0
      {
        upper.removeLast()
      }
      upper.append(point)
    }

    lower.removeLast()
    upper.removeLast()
    let hull = lower + upper
    return hull.count >= 3 ? hull : nil
  }

  private static func signedArea(_ polygon: [SIMD2<Float>]) -> Float {
    guard polygon.count >= 3 else { return 0 }
    var area: Float = 0
    for index in polygon.indices {
      let current = polygon[index]
      let next = polygon[(index + 1) % polygon.count]
      area += current.x * next.y - next.x * current.y
    }
    return area * 0.5
  }

  private static func pointInsidePolygon(
    _ point: SIMD2<Float>,
    polygon: [SIMD2<Float>]
  ) -> Bool {
    guard polygon.count >= 3 else { return false }
    var inside = false
    var previous = polygon.last!
    for current in polygon {
      let crosses = (current.y > point.y) != (previous.y > point.y)
      if crosses {
        let denominator = previous.y - current.y
        let safeDenominator = abs(denominator) < 0.0000001 ? 0.0000001 : denominator
        let intersectionX =
          (previous.x - current.x) * (point.y - current.y) / safeDenominator + current.x
        if point.x < intersectionX {
          inside.toggle()
        }
      }
      previous = current
    }
    return inside
  }

  private static func pointInsideOrNearPolygon(
    _ point: SIMD2<Float>,
    polygon: [SIMD2<Float>],
    margin: Float
  ) -> Bool {
    if pointInsidePolygon(point, polygon: polygon) { return true }
    guard margin > 0 else { return false }
    var minimumDistance = Float.greatestFiniteMagnitude
    for index in polygon.indices {
      let start = polygon[index]
      let end = polygon[(index + 1) % polygon.count]
      minimumDistance = min(minimumDistance, distance(point, toSegmentFrom: start, to: end))
    }
    return minimumDistance <= margin
  }

  private static func distance(
    _ point: SIMD2<Float>,
    toSegmentFrom start: SIMD2<Float>,
    to end: SIMD2<Float>
  ) -> Float {
    let segment = end - start
    let lengthSquared = simd_length_squared(segment)
    guard lengthSquared > 0.0000001 else { return simd_length(point - start) }
    let t = max(0, min(1, simd_dot(point - start, segment) / lengthSquared))
    return simd_length(point - (start + segment * t))
  }

  private static func localToWorld(
    _ point: SIMD3<Float>,
    origin: SIMD3<Float>,
    basis: simd_float3x3
  ) -> SIMD3<Float> {
    origin
      + basis.columns.0 * point.x
      + basis.columns.1 * point.y
      + basis.columns.2 * point.z
  }

  private func postStatus(_ message: String) {
    Task { @MainActor [weak model] in
      model?.status = message
    }
  }

  private func postTracking(_ message: String) {
    Task { @MainActor [weak model] in
      model?.trackingSummary = message
    }
  }

  func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
    storeMeshAnchors(anchors)
  }

  func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
    storeMeshAnchors(anchors)
  }

  func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
    let ids = anchors.compactMap { ($0 as? ARMeshAnchor)?.identifier }
    guard !ids.isEmpty else { return }
    anchorQueue.async {
      for id in ids {
        self.meshAnchors.removeValue(forKey: id)
      }
    }
  }

  func session(_ session: ARSession, didUpdate frame: ARFrame) {
    let now = CACurrentMediaTime()
    if now - lastReticleUpdateTime >= reticleInterval {
      lastReticleUpdateTime = now
      Task { @MainActor [weak self] in
        self?.updateReticleState()
      }
    }

    let active = anchorQueue.sync { captureActive }
    if active {
      let cameraPosition = frame.camera.transform.translationVector
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.updateCoverage(cameraPosition: cameraPosition)
        self.requestSurfacePreview()
      }
    }
  }

  func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
    switch camera.trackingState {
    case .normal:
      postTracking("Tracking normal")
    case .notAvailable:
      postTracking("Tracking unavailable")
    case .limited(let reason):
      postTracking("Tracking limited: \(reason.description)")
    }
  }

  private func storeMeshAnchors(_ anchors: [ARAnchor]) {
    let updates = anchors.compactMap { $0 as? ARMeshAnchor }
    guard !updates.isEmpty else { return }

    anchorQueue.async {
      for anchor in updates {
        self.meshAnchors[anchor.identifier] = anchor
      }
      if self.captureActive {
        Task { @MainActor [weak self] in
          self?.requestSurfacePreview()
        }
      }
    }
  }
}

private struct QuantizedPoint2D: Hashable {
  let qx: Int
  let qy: Int
  let point: SIMD2<Float>

  init(_ point: SIMD2<Float>) {
    self.point = point
    qx = Int((point.x * 100_000).rounded())
    qy = Int((point.y * 100_000).rounded())
  }

  static func == (lhs: QuantizedPoint2D, rhs: QuantizedPoint2D) -> Bool {
    lhs.qx == rhs.qx && lhs.qy == rhs.qy
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(qx)
    hasher.combine(qy)
  }
}

extension ARCamera.TrackingState.Reason {
  fileprivate var description: String {
    switch self {
    case .initializing: return "initializing"
    case .excessiveMotion: return "move more slowly"
    case .insufficientFeatures: return "not enough surface detail"
    case .relocalizing: return "relocalizing"
    @unknown default: return "unknown"
    }
  }
}

extension simd_float4x4 {
  fileprivate var translationVector: SIMD3<Float> {
    SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
  }

  fileprivate var zAxis: SIMD3<Float> {
    SIMD3<Float>(columns.2.x, columns.2.y, columns.2.z)
  }

  fileprivate func transformPoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
    let result = self * SIMD4<Float>(point.x, point.y, point.z, 1)
    return SIMD3<Float>(result.x, result.y, result.z)
  }
}

extension ARMeshGeometry {
  fileprivate func vertex(at index: Int) -> SIMD3<Float> {
    let source = vertices
    let address = source.buffer.contents().advanced(by: source.offset + source.stride * index)
    let pointer = address.assumingMemoryBound(to: Float.self)
    return SIMD3<Float>(pointer[0], pointer[1], pointer[2])
  }

  fileprivate func triangleIndices(faceIndex: Int) -> (Int, Int, Int)? {
    let faces = self.faces
    guard faces.indexCountPerPrimitive == 3 else { return nil }
    let byteOffset = faceIndex * faces.indexCountPerPrimitive * faces.bytesPerIndex
    let address = faces.buffer.contents().advanced(by: byteOffset)

    if faces.bytesPerIndex == MemoryLayout<UInt16>.size {
      let pointer = address.assumingMemoryBound(to: UInt16.self)
      return (Int(pointer[0]), Int(pointer[1]), Int(pointer[2]))
    }

    let pointer = address.assumingMemoryBound(to: UInt32.self)
    return (Int(pointer[0]), Int(pointer[1]), Int(pointer[2]))
  }

  fileprivate func classificationOf(faceWithIndex index: Int) -> ARMeshClassification {
    guard let classification else { return .none }
    let address = classification.buffer.contents().advanced(
      by: classification.offset + classification.stride * index
    )
    let rawValue = address.assumingMemoryBound(to: UInt8.self).pointee
    return ARMeshClassification(rawValue: Int(rawValue)) ?? .none
  }
}
