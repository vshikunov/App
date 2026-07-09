import SwiftUI
import RealityKit
import ARKit
import CoreVideo
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
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.controller?.setMeshOverlayVisible(model.showMeshOverlay)
    }

    final class Coordinator {
        weak var model: ScannerViewModel?
        var controller: ARScannerController?

        init(model: ScannerViewModel) {
            self.model = model
        }
    }
}

final class ARScannerController: NSObject, ARSessionDelegate {
    private weak var arView: ARView?
    private weak var model: ScannerViewModel?
    private let anchorQueue = DispatchQueue(label: "DimensionalScanner.ARMeshAnchors")
    private var meshAnchors: [UUID: ARMeshAnchor] = [:]
    private var captureActive = false

    /// Crop center in world space.
    private var objectCenterWorld: SIMD3<Float>?

    /// Output/reference origin. In 6-point mode this is the captured ground-zero datum.
    private var objectReferenceOriginWorld: SIMD3<Float>?

    /// Columns are local X, local Y/up, local Z/depth axes in world coordinates.
    private var partBasisWorld = simd_float3x3(
        SIMD3<Float>(1, 0, 0),
        SIMD3<Float>(0, 1, 0),
        SIMD3<Float>(0, 0, 1)
    )

    /// Stored half extents for the automatically detected 6-point object volume, in meters.
    private var sixPointHalfExtentsM: SIMD3<Float>?

    /// Drops flat table/floor mesh immediately at the zero plane when 6-point mode is active.
    private var groundRemovalHeightM: Float = 0.002

    init(arView: ARView, model: ScannerViewModel) {
        self.arView = arView
        self.model = model
        super.init()
        arView.session.delegate = self
    }

    func startSession(showMeshOverlay: Bool) {
        guard ARWorldTrackingConfiguration.isSupported else {
            postStatus("AR world tracking is not supported on this device.")
            return
        }
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            postStatus("This iPhone does not support ARKit scene reconstruction. Use an iPhone/iPad with LiDAR.")
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

        arView?.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        setMeshOverlayVisible(showMeshOverlay)
        postStatus("ARKit mesh reconstruction is running. Aim the reticle at ground zero and capture point 1.")
    }

    @MainActor
    func resetSession() {
        anchorQueue.sync {
            meshAnchors.removeAll()
            captureActive = false
        }
        objectCenterWorld = nil
        objectReferenceOriginWorld = nil
        sixPointHalfExtentsM = nil
        startSession(showMeshOverlay: model?.showMeshOverlay ?? true)
    }

    func setMeshOverlayVisible(_ visible: Bool) {
        guard let arView else { return }
        if visible {
            arView.debugOptions.insert(.showSceneUnderstanding)
        } else {
            arView.debugOptions.remove(.showSceneUnderstanding)
        }
    }

    @MainActor
    func setObjectCenterFromScreenCenter() {
        guard let point = captureWorldPointFromScreenCenter() else {
            postStatus("Could not set center. Aim at a visible surface and try again.")
            return
        }

        objectCenterWorld = point
        objectReferenceOriginWorld = point
        sixPointHalfExtentsM = nil
        updatePartBasisFromCurrentCamera()
        postStatus("Manual object center set. For better object detection, use the 6-point reference workflow.")
    }

    @MainActor
    func captureWorldPointFromScreenCenter() -> SIMD3<Float>? {
        guard let arView else { return nil }

        if let depthPoint = worldPointFromSceneDepthAtScreenCenter(in: arView) {
            return depthPoint
        }

        let screenPoint = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        let raycastResults = arView.raycast(from: screenPoint, allowing: .estimatedPlane, alignment: .any)
        if let first = raycastResults.first {
            return first.worldTransform.translationVector
        }

        if let frame = arView.session.currentFrame {
            let cameraTransform = frame.camera.transform
            let cameraPosition = cameraTransform.translationVector
            let forward = -cameraTransform.zAxis
            return cameraPosition + simd_normalize(forward) * 0.60
        }

        return nil
    }

    @MainActor
    func applySixPointReference(points: [SIMD3<Float>], paddingMM: Double) -> SixPointReferenceSummary? {
        guard points.count >= 6 else { return nil }

        let ground = points[0]
        let top = points[1]
        let boundaryPoints = Array(points[2..<6])
        let rawUp = top - ground
        let heightM = simd_length(rawUp)
        guard heightM > 0.005 else { return nil }

        let upAxis = simd_normalize(rawUp)
        let projectedBoundary = boundaryPoints.map { point in
            point - upAxis * simd_dot(point - ground, upAxis)
        }

        var xAxis = farthestPairAxis(points: projectedBoundary)
        if simd_length(xAxis) < 0.0001 {
            xAxis = cameraRightProjected(perpendicularTo: upAxis)
        }
        xAxis = simd_normalize(xAxis - upAxis * simd_dot(xAxis, upAxis))

        var depthAxis = simd_cross(xAxis, upAxis)
        if simd_length(depthAxis) < 0.0001 {
            depthAxis = SIMD3<Float>(0, 0, 1)
        } else {
            depthAxis = simd_normalize(depthAxis)
        }
        xAxis = simd_normalize(simd_cross(upAxis, depthAxis))

        partBasisWorld = simd_float3x3(xAxis, upAxis, depthAxis)
        objectReferenceOriginWorld = ground

        let planarPoints = boundaryPoints + [ground]
        let locals = planarPoints.map { localReferenceCoordinate(for: $0, origin: ground) }

        guard let first = locals.first else { return nil }
        var minX = first.x
        var maxX = first.x
        var minZ = first.z
        var maxZ = first.z

        for local in locals.dropFirst() {
            minX = min(minX, local.x)
            maxX = max(maxX, local.x)
            minZ = min(minZ, local.z)
            maxZ = max(maxZ, local.z)
        }

        let paddingM = max(Float(paddingMM / 1000.0), 0.0)
        let widthM = max(maxX - minX, 0.010)
        let depthM = max(maxZ - minZ, 0.010)
        let centerLocal = SIMD3<Float>(
            (minX + maxX) / 2.0,
            heightM / 2.0,
            (minZ + maxZ) / 2.0
        )

        let centerWorld = ground
            + xAxis * centerLocal.x
            + upAxis * centerLocal.y
            + depthAxis * centerLocal.z

        objectCenterWorld = centerWorld
        sixPointHalfExtentsM = SIMD3<Float>(
            widthM / 2.0 + paddingM,
            heightM / 2.0 + paddingM,
            depthM / 2.0 + paddingM
        )

        return SixPointReferenceSummary(
            widthMM: Double(widthM * 1000.0),
            heightMM: Double(heightM * 1000.0),
            depthMM: Double(depthM * 1000.0),
            paddingMM: paddingMM
        )
    }

    @MainActor
    func clearSixPointReference() {
        objectCenterWorld = nil
        objectReferenceOriginWorld = nil
        sixPointHalfExtentsM = nil
    }

    func beginCapture() {
        anchorQueue.sync {
            meshAnchors.removeAll()
            captureActive = true
        }
        postStatus("Capturing mesh anchors. Move slowly around all sides of the object.")
    }

    func endCapture() {
        anchorQueue.sync {
            captureActive = false
        }
    }

    func makeCroppedObjectMesh(volumeXMM: Double, volumeYMM: Double, volumeZMM: Double) -> TriangleMesh? {
        guard let center = objectCenterWorld else { return nil }
        let anchors = anchorQueue.sync { Array(meshAnchors.values) }
        guard !anchors.isEmpty else { return nil }

        let halfExtents = sixPointHalfExtentsM ?? SIMD3<Float>(
            Float(volumeXMM / 2000.0),
            Float(volumeYMM / 2000.0),
            Float(volumeZMM / 2000.0)
        )

        var output = TriangleMesh()
        for anchor in anchors {
            appendCropped(anchor: anchor, center: center, halfExtents: halfExtents, into: &output)
        }

        return output
    }

    private func appendCropped(
        anchor: ARMeshAnchor,
        center: SIMD3<Float>,
        halfExtents: SIMD3<Float>,
        into output: inout TriangleMesh
    ) {
        let geometry = anchor.geometry
        let transform = anchor.transform
        let faceCount = geometry.faces.count
        let usingGroundDatum = objectReferenceOriginWorld != nil && sixPointHalfExtentsM != nil

        for faceIndex in 0..<faceCount {
            guard let indices = geometry.triangleIndices(faceIndex: faceIndex) else { continue }

            let local0 = geometry.vertex(at: indices.0)
            let local1 = geometry.vertex(at: indices.1)
            let local2 = geometry.vertex(at: indices.2)

            let world0 = transform.transformPoint(local0)
            let world1 = transform.transformPoint(local1)
            let world2 = transform.transformPoint(local2)

            let crop0 = worldToCropCoordinate(world0, center: center)
            let crop1 = worldToCropCoordinate(world1, center: center)
            let crop2 = worldToCropCoordinate(world2, center: center)

            guard isInside(crop0, halfExtents: halfExtents),
                  isInside(crop1, halfExtents: halfExtents),
                  isInside(crop2, halfExtents: halfExtents) else {
                continue
            }

            let ref0 = worldToReferenceCoordinate(world0, fallbackCenter: center)
            let ref1 = worldToReferenceCoordinate(world1, fallbackCenter: center)
            let ref2 = worldToReferenceCoordinate(world2, fallbackCenter: center)

            if usingGroundDatum {
                let highestVertex = max(ref0.y, max(ref1.y, ref2.y))
                let lowestVertex = min(ref0.y, min(ref1.y, ref2.y))
                if highestVertex < groundRemovalHeightM || lowestVertex < -groundRemovalHeightM {
                    continue
                }
            }

            let baseIndex = output.vertices.count
            output.vertices.append(Vector3D(x: Double(ref0.x) * 1000.0, y: Double(ref0.y) * 1000.0, z: Double(ref0.z) * 1000.0))
            output.vertices.append(Vector3D(x: Double(ref1.x) * 1000.0, y: Double(ref1.y) * 1000.0, z: Double(ref1.z) * 1000.0))
            output.vertices.append(Vector3D(x: Double(ref2.x) * 1000.0, y: Double(ref2.y) * 1000.0, z: Double(ref2.z) * 1000.0))
            output.faces.append(TriangleFace(baseIndex, baseIndex + 1, baseIndex + 2))
        }
    }

    private func worldToCropCoordinate(_ point: SIMD3<Float>, center: SIMD3<Float>) -> SIMD3<Float> {
        let delta = point - center
        let x = simd_dot(delta, partBasisWorld.columns.0)
        let y = simd_dot(delta, partBasisWorld.columns.1)
        let z = simd_dot(delta, partBasisWorld.columns.2)
        return SIMD3<Float>(x, y, z)
    }

    private func worldToReferenceCoordinate(_ point: SIMD3<Float>, fallbackCenter: SIMD3<Float>) -> SIMD3<Float> {
        let origin = objectReferenceOriginWorld ?? fallbackCenter
        return localReferenceCoordinate(for: point, origin: origin)
    }

    private func localReferenceCoordinate(for point: SIMD3<Float>, origin: SIMD3<Float>) -> SIMD3<Float> {
        let delta = point - origin
        let x = simd_dot(delta, partBasisWorld.columns.0)
        let y = simd_dot(delta, partBasisWorld.columns.1)
        let z = simd_dot(delta, partBasisWorld.columns.2)
        return SIMD3<Float>(x, y, z)
    }

    private func isInside(_ point: SIMD3<Float>, halfExtents: SIMD3<Float>) -> Bool {
        abs(point.x) <= halfExtents.x && abs(point.y) <= halfExtents.y && abs(point.z) <= halfExtents.z
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

        partBasisWorld = simd_float3x3(right, up, depth)
        objectReferenceOriginWorld = objectCenterWorld
    }

    private func farthestPairAxis(points: [SIMD3<Float>]) -> SIMD3<Float> {
        guard points.count >= 2 else { return SIMD3<Float>(0, 0, 0) }
        var bestAxis = points[1] - points[0]
        var bestDistance = simd_length_squared(bestAxis)

        for i in 0..<points.count {
            for j in (i + 1)..<points.count {
                let candidate = points[j] - points[i]
                let distance = simd_length_squared(candidate)
                if distance > bestDistance {
                    bestDistance = distance
                    bestAxis = candidate
                }
            }
        }

        return bestAxis
    }

    private func cameraRightProjected(perpendicularTo upAxis: SIMD3<Float>) -> SIMD3<Float> {
        guard let frame = arView?.session.currentFrame else {
            return SIMD3<Float>(1, 0, 0)
        }
        let cameraRight = SIMD3<Float>(
            frame.camera.transform.columns.0.x,
            frame.camera.transform.columns.0.y,
            frame.camera.transform.columns.0.z
        )
        let projected = cameraRight - upAxis * simd_dot(cameraRight, upAxis)
        if simd_length(projected) < 0.0001 {
            return SIMD3<Float>(1, 0, 0)
        }
        return projected
    }

    @MainActor
    private func worldPointFromSceneDepthAtScreenCenter(in arView: ARView) -> SIMD3<Float>? {
        guard let frame = arView.session.currentFrame else { return nil }
        guard let depthMap = (frame.smoothedSceneDepth ?? frame.sceneDepth)?.depthMap else { return nil }

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
                let value = baseAddress.advanced(by: offset).assumingMemoryBound(to: Float32.self).pointee
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
        let meshUpdates = anchors.compactMap { $0 as? ARMeshAnchor }
        guard !meshUpdates.isEmpty else { return }
        anchorQueue.async {
            guard self.captureActive else { return }
            for anchor in meshUpdates {
                self.meshAnchors[anchor.identifier] = anchor
            }
        }
    }
}

private extension ARCamera.TrackingState.Reason {
    var description: String {
        switch self {
        case .initializing: return "initializing"
        case .excessiveMotion: return "excessive motion"
        case .insufficientFeatures: return "insufficient features"
        case .relocalizing: return "relocalizing"
        @unknown default: return "unknown"
        }
    }
}

private extension simd_float4x4 {
    var translationVector: SIMD3<Float> {
        SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }

    var zAxis: SIMD3<Float> {
        SIMD3<Float>(columns.2.x, columns.2.y, columns.2.z)
    }

    func transformPoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let result = self * SIMD4<Float>(point.x, point.y, point.z, 1.0)
        return SIMD3<Float>(result.x, result.y, result.z)
    }
}

private extension ARMeshGeometry {
    func vertex(at index: Int) -> SIMD3<Float> {
        let source = vertices
        let address = source.buffer.contents().advanced(by: source.offset + source.stride * index)
        let pointer = address.assumingMemoryBound(to: Float.self)
        return SIMD3<Float>(pointer[0], pointer[1], pointer[2])
    }

    func triangleIndices(faceIndex: Int) -> (Int, Int, Int)? {
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
}
