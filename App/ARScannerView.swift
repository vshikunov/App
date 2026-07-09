import SwiftUI
import RealityKit
import ARKit
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
    private var objectCenterWorld: SIMD3<Float>?
    private var partBasisWorld = simd_float3x3(
        SIMD3<Float>(1, 0, 0),
        SIMD3<Float>(0, 1, 0),
        SIMD3<Float>(0, 0, 1)
    )

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

        arView?.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        setMeshOverlayVisible(showMeshOverlay)
        postStatus("ARKit mesh reconstruction is running. Aim at the object and tap Set Center.")
    }

    func resetSession() {
        anchorQueue.sync {
            meshAnchors.removeAll()
            captureActive = false
        }
        objectCenterWorld = nil
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

    func setObjectCenterFromScreenCenter() {
        guard let arView else { return }
        let screenPoint = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        let raycastResults = arView.raycast(from: screenPoint, allowing: .estimatedPlane, alignment: .any)

        if let first = raycastResults.first {
            objectCenterWorld = first.worldTransform.translationVector
        } else if let frame = arView.session.currentFrame {
            let cameraTransform = frame.camera.transform
            let cameraPosition = cameraTransform.translationVector
            let forward = -cameraTransform.zAxis
            objectCenterWorld = cameraPosition + forward * 0.60
        }

        updatePartBasisFromCurrentCamera()
        postStatus("Object center set. The crop box is aligned to the phone view and gravity.")
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

        let halfX = Float(volumeXMM / 2000.0)
        let halfY = Float(volumeYMM / 2000.0)
        let halfZ = Float(volumeZMM / 2000.0)
        var output = TriangleMesh()

        for anchor in anchors {
            appendCropped(anchor: anchor, center: center, halfX: halfX, halfY: halfY, halfZ: halfZ, into: &output)
        }

        return output
    }

    private func appendCropped(
        anchor: ARMeshAnchor,
        center: SIMD3<Float>,
        halfX: Float,
        halfY: Float,
        halfZ: Float,
        into output: inout TriangleMesh
    ) {
        let geometry = anchor.geometry
        let transform = anchor.transform
        let faceCount = geometry.faces.count

        for faceIndex in 0..<faceCount {
            guard let indices = geometry.triangleIndices(faceIndex: faceIndex) else { continue }

            let local0 = geometry.vertex(at: indices.0)
            let local1 = geometry.vertex(at: indices.1)
            let local2 = geometry.vertex(at: indices.2)

            let world0 = transform.transformPoint(local0)
            let world1 = transform.transformPoint(local1)
            let world2 = transform.transformPoint(local2)

            let part0 = worldToPart(world0, center: center)
            let part1 = worldToPart(world1, center: center)
            let part2 = worldToPart(world2, center: center)

            guard isInside(part0, halfX: halfX, halfY: halfY, halfZ: halfZ),
                  isInside(part1, halfX: halfX, halfY: halfY, halfZ: halfZ),
                  isInside(part2, halfX: halfX, halfY: halfY, halfZ: halfZ) else {
                continue
            }

            let baseIndex = output.vertices.count
            output.vertices.append(Vector3D(x: Double(part0.x) * 1000.0, y: Double(part0.y) * 1000.0, z: Double(part0.z) * 1000.0))
            output.vertices.append(Vector3D(x: Double(part1.x) * 1000.0, y: Double(part1.y) * 1000.0, z: Double(part1.z) * 1000.0))
            output.vertices.append(Vector3D(x: Double(part2.x) * 1000.0, y: Double(part2.y) * 1000.0, z: Double(part2.z) * 1000.0))
            output.faces.append(TriangleFace(baseIndex, baseIndex + 1, baseIndex + 2))
        }
    }

    private func worldToPart(_ point: SIMD3<Float>, center: SIMD3<Float>) -> SIMD3<Float> {
        let delta = point - center
        let x = simd_dot(delta, partBasisWorld.columns.0)
        let y = simd_dot(delta, partBasisWorld.columns.1)
        let z = simd_dot(delta, partBasisWorld.columns.2)
        return SIMD3<Float>(x, y, z)
    }

    private func isInside(_ point: SIMD3<Float>, halfX: Float, halfY: Float, halfZ: Float) -> Bool {
        abs(point.x) <= halfX && abs(point.y) <= halfY && abs(point.z) <= halfZ
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
