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
}

private struct MeshCropContext {
  let centerWorld: SIMD3<Float>
  let halfExtentsM: SIMD3<Float>
  let referenceOriginWorld: SIMD3<Float>
  let basisWorld: simd_float3x3
  let removeSupportSurface: Bool
  let groundRemovalHeightM: Float
}

final class ARScannerController: NSObject, ARSessionDelegate {
  private weak var arView: ARView?
  private weak var model: ScannerViewModel?

  private let anchorQueue = DispatchQueue(label: "DimensionalScanner.ARMeshAnchors")
  private let previewQueue = DispatchQueue(
    label: "DimensionalScanner.SurfacePreview", qos: .userInitiated)
  private var meshAnchors: [UUID: ARMeshAnchor] = [:]
  private var captureActive = false

  /// Center of the selected crop box in world space.
  private var objectCenterWorld: SIMD3<Float>?

  /// Lower-left-front corner of the exact six-face box. Export coordinates use this origin.
  private var objectReferenceOriginWorld: SIMD3<Float>?

  /// Columns are local X/right, local Y/up, and local Z/depth axes in world coordinates.
  private var partBasisWorld = simd_float3x3(
    SIMD3<Float>(1, 0, 0),
    SIMD3<Float>(0, 1, 0),
    SIMD3<Float>(0, 0, 1)
  )

  /// Padded half extents used to collect LiDAR triangles.
  private var sixPointHalfExtentsM: SIMD3<Float>?

  /// Exact half extents shown by the blue box.
  private var exactBoxHalfExtentsM: SIMD3<Float>?

  private let groundRemovalHeightM: Float = 0.003

  // RealityKit visual entities.
  private var referenceMarkerAnchors: [AnchorEntity] = []
  private var boundingBoxAnchor: AnchorEntity?
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
    postStatus("Aim at the bottom face and tap Add.")
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
    sixPointHalfExtentsM = nil
    exactBoxHalfExtentsM = nil
    updatePartBasisFromCurrentCamera()
    postStatus("Manual center set. The six-face box gives better isolation and scale feedback.")
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
      .systemBlue,
      .systemOrange,
      .systemPurple,
      .systemPurple,
      .systemGreen,
      .systemGreen,
    ]
    let color = colors.indices.contains(index) ? colors[index] : .white
    // Keep the six reference points precise without obscuring the surface.
    let sphere = ModelEntity(
      mesh: .generateSphere(radius: 0.0028),
      materials: [SimpleMaterial(color: color.withAlphaComponent(0.96), isMetallic: false)]
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
    if let capturedSurfaceAnchor {
      arView.scene.removeAnchor(capturedSurfaceAnchor)
    }

    boundingBoxAnchor = nil
    capturedSurfaceAnchor = nil
    capturedSurfaceEntity = nil
    objectCenterWorld = nil
    objectReferenceOriginWorld = nil
    sixPointHalfExtentsM = nil
    exactBoxHalfExtentsM = nil
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
    if let capturedSurfaceAnchor {
      arView.scene.removeAnchor(capturedSurfaceAnchor)
    }
    boundingBoxAnchor = nil
    capturedSurfaceAnchor = nil
    capturedSurfaceEntity = nil
    objectCenterWorld = nil
    objectReferenceOriginWorld = nil
    sixPointHalfExtentsM = nil
    exactBoxHalfExtentsM = nil
    coveredCameraSectors.removeAll()
    model?.capturedSurfaceTriangleCount = 0
    model?.scanCoveragePercent = 0
  }

  /// Compatibility alias used by the earlier six-point patch.
  @MainActor
  func clearSixPointReference() {
    clearReferenceVisuals()
  }

  /// Six captured points represent opposite faces: bottom/top, left/right, and front/back.
  @MainActor
  func applySixPointReference(
    points: [SIMD3<Float>],
    paddingMM: Double
  ) -> SixPointReferenceSummary? {
    guard points.count >= 6 else { return nil }

    let bottom = points[0]
    let top = points[1]
    let left = points[2]
    let right = points[3]
    let front = points[4]
    let back = points[5]

    let rawUp = top - bottom
    guard simd_length(rawUp) > 0.005 else { return nil }
    let upAxis = simd_normalize(rawUp)

    let rawRight = right - left
    var xAxis = rawRight - upAxis * simd_dot(rawRight, upAxis)
    guard simd_length(xAxis) > 0.005 else { return nil }
    xAxis = simd_normalize(xAxis)

    let rawDepth = back - front
    var depthProjected =
      rawDepth
      - upAxis * simd_dot(rawDepth, upAxis)
      - xAxis * simd_dot(rawDepth, xAxis)

    if simd_length(depthProjected) < 0.005 {
      depthProjected = simd_cross(xAxis, upAxis)
    }
    guard simd_length(depthProjected) > 0.0001 else { return nil }

    var zAxis = simd_normalize(depthProjected)
    if simd_dot(simd_cross(xAxis, upAxis), zAxis) < 0 {
      zAxis = -zAxis
    }
    xAxis = simd_normalize(simd_cross(upAxis, zAxis))

    let minX = min(simd_dot(left, xAxis), simd_dot(right, xAxis))
    let maxX = max(simd_dot(left, xAxis), simd_dot(right, xAxis))
    let minY = min(simd_dot(bottom, upAxis), simd_dot(top, upAxis))
    let maxY = max(simd_dot(bottom, upAxis), simd_dot(top, upAxis))
    let minZ = min(simd_dot(front, zAxis), simd_dot(back, zAxis))
    let maxZ = max(simd_dot(front, zAxis), simd_dot(back, zAxis))

    let widthM = maxX - minX
    let heightM = maxY - minY
    let depthM = maxZ - minZ
    guard widthM > 0.005, heightM > 0.005, depthM > 0.005 else { return nil }

    let centerWorld =
      xAxis * ((minX + maxX) / 2)
      + upAxis * ((minY + maxY) / 2)
      + zAxis * ((minZ + maxZ) / 2)
    let lowerLeftFrontWorld = xAxis * minX + upAxis * minY + zAxis * minZ

    partBasisWorld = simd_float3x3(xAxis, upAxis, zAxis)
    objectCenterWorld = centerWorld
    objectReferenceOriginWorld = lowerLeftFrontWorld

    let exactHalf = SIMD3<Float>(widthM / 2, heightM / 2, depthM / 2)
    let paddingM = max(Float(paddingMM / 1000), 0)
    exactBoxHalfExtentsM = exactHalf
    sixPointHalfExtentsM = exactHalf + SIMD3<Float>(repeating: paddingM)

    renderBoundingBox(center: centerWorld, halfExtents: exactHalf)
    requestSurfacePreview(force: true)

    return SixPointReferenceSummary(
      widthMM: Double(widthM * 1000),
      heightMM: Double(heightM * 1000),
      depthMM: Double(depthM * 1000),
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
  func makeCroppedObjectMesh(
    volumeXMM: Double,
    volumeYMM: Double,
    volumeZMM: Double
  ) -> TriangleMesh? {
    guard
      let context = makeCropContext(
        volumeXMM: volumeXMM,
        volumeYMM: volumeYMM,
        volumeZMM: volumeZMM,
        useExactSixPointBounds: true
      )
    else {
      return nil
    }

    let anchors = anchorQueue.sync { Array(meshAnchors.values) }
    guard !anchors.isEmpty else { return nil }

    var output = TriangleMesh()
    for anchor in anchors {
      Self.appendCropped(anchor: anchor, context: context, into: &output)
    }
    return output
  }

  @MainActor
  private func makeCropContext(
    volumeXMM: Double,
    volumeYMM: Double,
    volumeZMM: Double,
    useExactSixPointBounds: Bool
  ) -> MeshCropContext? {
    guard let center = objectCenterWorld else { return nil }

    let manualHalfExtents = SIMD3<Float>(
      Float(volumeXMM / 2000),
      Float(volumeYMM / 2000),
      Float(volumeZMM / 2000)
    )

    let halfExtents: SIMD3<Float>
    if useExactSixPointBounds, let exactBoxHalfExtentsM {
      // A sub-millimeter numerical allowance prevents boundary triangles from being dropped,
      // while keeping the final STL inside the six-point box rather than the preview margin.
      halfExtents = exactBoxHalfExtentsM + SIMD3<Float>(repeating: 0.0005)
    } else {
      halfExtents = sixPointHalfExtentsM ?? manualHalfExtents
    }
    return MeshCropContext(
      centerWorld: center,
      halfExtentsM: halfExtents,
      referenceOriginWorld: objectReferenceOriginWorld ?? center,
      basisWorld: partBasisWorld,
      removeSupportSurface: objectReferenceOriginWorld != nil && sixPointHalfExtentsM != nil,
      groundRemovalHeightM: groundRemovalHeightM
    )
  }

  private static func appendCropped(
    anchor: ARMeshAnchor,
    context: MeshCropContext,
    into output: inout TriangleMesh
  ) {
    let geometry = anchor.geometry
    let transform = anchor.transform

    for faceIndex in 0..<geometry.faces.count {
      guard let indices = geometry.triangleIndices(faceIndex: faceIndex) else { continue }

      let world0 = transform.transformPoint(geometry.vertex(at: indices.0))
      let world1 = transform.transformPoint(geometry.vertex(at: indices.1))
      let world2 = transform.transformPoint(geometry.vertex(at: indices.2))

      let crop0 = worldToLocal(world0, center: context.centerWorld, basis: context.basisWorld)
      let crop1 = worldToLocal(world1, center: context.centerWorld, basis: context.basisWorld)
      let crop2 = worldToLocal(world2, center: context.centerWorld, basis: context.basisWorld)

      guard isInside(crop0, halfExtents: context.halfExtentsM),
        isInside(crop1, halfExtents: context.halfExtentsM),
        isInside(crop2, halfExtents: context.halfExtentsM)
      else {
        continue
      }

      let ref0 = worldToLocal(
        world0, center: context.referenceOriginWorld, basis: context.basisWorld)
      let ref1 = worldToLocal(
        world1, center: context.referenceOriginWorld, basis: context.basisWorld)
      let ref2 = worldToLocal(
        world2, center: context.referenceOriginWorld, basis: context.basisWorld)
      let classification = geometry.classificationOf(faceWithIndex: faceIndex)

      if shouldRejectSupportTriangle(
        ref0,
        ref1,
        ref2,
        classification: classification,
        context: context
      ) {
        continue
      }

      let baseIndex = output.vertices.count
      output.vertices.append(
        Vector3D(x: Double(ref0.x) * 1000, y: Double(ref0.y) * 1000, z: Double(ref0.z) * 1000))
      output.vertices.append(
        Vector3D(x: Double(ref1.x) * 1000, y: Double(ref1.y) * 1000, z: Double(ref1.z) * 1000))
      output.vertices.append(
        Vector3D(x: Double(ref2.x) * 1000, y: Double(ref2.y) * 1000, z: Double(ref2.z) * 1000))
      output.faces.append(TriangleFace(baseIndex, baseIndex + 1, baseIndex + 2))
    }
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
    if maxY < context.groundRemovalHeightM || minY < -context.groundRemovalHeightM {
      return true
    }

    if classification == .floor || classification == .table {
      let centroidY = (a.y + b.y + c.y) / 3
      if centroidY < 0.012 {
        return true
      }
    }
    return false
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

  private static func isInside(_ point: SIMD3<Float>, halfExtents: SIMD3<Float>) -> Bool {
    abs(point.x) <= halfExtents.x
      && abs(point.y) <= halfExtents.y
      && abs(point.z) <= halfExtents.z
  }

  @MainActor
  private func requestSurfacePreview(force: Bool = false) {
    guard
      let context = makeCropContext(
        volumeXMM: model?.scanVolumeXMM ?? 160,
        volumeYMM: model?.scanVolumeYMM ?? 160,
        volumeZMM: model?.scanVolumeZMM ?? 160,
        useExactSixPointBounds: false
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
    var triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
    triangles.reserveCapacity(min(maxTriangles * 2, 40_000))

    for anchor in anchors {
      let geometry = anchor.geometry
      let transform = anchor.transform

      for faceIndex in 0..<geometry.faces.count {
        guard let indices = geometry.triangleIndices(faceIndex: faceIndex) else { continue }

        let world0 = transform.transformPoint(geometry.vertex(at: indices.0))
        let world1 = transform.transformPoint(geometry.vertex(at: indices.1))
        let world2 = transform.transformPoint(geometry.vertex(at: indices.2))

        let crop0 = worldToLocal(world0, center: context.centerWorld, basis: context.basisWorld)
        let crop1 = worldToLocal(world1, center: context.centerWorld, basis: context.basisWorld)
        let crop2 = worldToLocal(world2, center: context.centerWorld, basis: context.basisWorld)

        guard isInside(crop0, halfExtents: context.halfExtentsM),
          isInside(crop1, halfExtents: context.halfExtentsM),
          isInside(crop2, halfExtents: context.halfExtentsM)
        else {
          continue
        }

        let ref0 = worldToLocal(
          world0, center: context.referenceOriginWorld, basis: context.basisWorld)
        let ref1 = worldToLocal(
          world1, center: context.referenceOriginWorld, basis: context.basisWorld)
        let ref2 = worldToLocal(
          world2, center: context.referenceOriginWorld, basis: context.basisWorld)
        let classification = geometry.classificationOf(faceWithIndex: faceIndex)

        if shouldRejectSupportTriangle(
          ref0,
          ref1,
          ref2,
          classification: classification,
          context: context
        ) {
          continue
        }

        triangles.append((world0, world1, world2))
      }
    }

    guard !triangles.isEmpty else {
      return SurfacePreviewData(positions: [], indices: [], triangleCount: 0)
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
      positions.append(triangle.0)
      positions.append(triangle.1)
      positions.append(triangle.2)
      indices.append(base)
      indices.append(base + 1)
      indices.append(base + 2)
    }

    return SurfacePreviewData(
      positions: positions,
      indices: indices,
      triangleCount: triangles.count
    )
  }

  @MainActor
  private func applySurfacePreview(_ data: SurfacePreviewData) {
    model?.capturedSurfaceTriangleCount = data.triangleCount
    guard let arView else { return }

    if data.positions.isEmpty {
      capturedSurfaceEntity?.removeFromParent()
      capturedSurfaceEntity = nil
      return
    }

    do {
      var descriptor = MeshDescriptor(name: "CapturedObjectSurface")
      descriptor.positions = MeshBuffers.Positions(data.positions)
      descriptor.primitives = .triangles(data.indices)
      let mesh = try MeshResource.generate(from: [descriptor])
      let material = SimpleMaterial(
        color: UIColor.systemTeal.withAlphaComponent(0.48),
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
      postStatus("Surface preview could not be rendered: \(error.localizedDescription)")
    }
  }

  @MainActor
  private func renderBoundingBox(center: SIMD3<Float>, halfExtents: SIMD3<Float>) {
    guard let arView else { return }
    if let boundingBoxAnchor {
      arView.scene.removeAnchor(boundingBoxAnchor)
    }

    let root = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
    let edgeMaterial = SimpleMaterial(
      color: UIColor.systemBlue.withAlphaComponent(0.92),
      isMetallic: false
    )
    let cornerMaterial = SimpleMaterial(color: .white, isMetallic: false)
    let thickness = max(
      min(min(halfExtents.x, min(halfExtents.y, halfExtents.z)) * 0.010, 0.0016),
      0.0008
    )

    let signs: [Float] = [-1, 1]
    var corners: [SIMD3<Float>] = []
    for sx in signs {
      for sy in signs {
        for sz in signs {
          let local = SIMD3<Float>(sx * halfExtents.x, sy * halfExtents.y, sz * halfExtents.z)
          corners.append(worldPoint(fromLocal: local, center: center))
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

    for (startIndex, endIndex) in edgePairs {
      let start = corners[startIndex]
      let end = corners[endIndex]
      let delta = end - start
      let length = simd_length(delta)
      guard length > 0.0001 else { continue }

      let edge = ModelEntity(
        mesh: .generateBox(size: SIMD3<Float>(thickness, length, thickness)),
        materials: [edgeMaterial]
      )
      edge.position = (start + end) / 2
      edge.orientation = simd_quatf(
        from: SIMD3<Float>(0, 1, 0),
        to: simd_normalize(delta)
      )
      root.addChild(edge)
    }

    for corner in corners {
      let dot = ModelEntity(
        mesh: .generateSphere(radius: max(thickness * 1.25, 0.0011)),
        materials: [cornerMaterial]
      )
      dot.position = corner
      root.addChild(dot)
    }

    root.isEnabled = boundingBoxVisible
    arView.scene.addAnchor(root)
    boundingBoxAnchor = root
  }

  private func worldPoint(fromLocal local: SIMD3<Float>, center: SIMD3<Float>) -> SIMD3<Float> {
    center
      + partBasisWorld.columns.0 * local.x
      + partBasisWorld.columns.1 * local.y
      + partBasisWorld.columns.2 * local.z
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
