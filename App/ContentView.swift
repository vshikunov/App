import Foundation
import ModelIO
import RealityKit
import SwiftUI

// MARK: - Precision Object Capture UI

struct ContentView: View {
  @EnvironmentObject private var appSettings: ScannerViewModel
  @StateObject private var captureModel = PrecisionObjectCaptureModel()

  @State private var showSettings = false
  @State private var showTolerances = false
  @State private var showHelp = false

  var body: some View {
    ZStack {
      content
    }
    .ignoresSafeArea(edges: captureModel.showsCamera ? .all : [])
    .sheet(isPresented: $showSettings) {
      PrecisionScanSettingsView()
        .environmentObject(appSettings)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showTolerances) {
      ToleranceEditorView()
        .environmentObject(appSettings)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showHelp) {
      PrecisionCaptureHelpView()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    .onAppear {
      captureModel.setAnalysisSettings(
        specs: appSettings.specs,
        scaleCorrectionFactor: appSettings.scaleCorrectionFactor
      )
      captureModel.prepareIfNeeded()
    }
    .onChange(of: appSettings.specs) { _, newSpecs in
      captureModel.setAnalysisSettings(
        specs: newSpecs,
        scaleCorrectionFactor: appSettings.scaleCorrectionFactor
      )
    }
    .onChange(of: appSettings.scaleCorrectionFactor) { _, newFactor in
      captureModel.setAnalysisSettings(
        specs: appSettings.specs,
        scaleCorrectionFactor: newFactor
      )
    }
  }

  @ViewBuilder
  private var content: some View {
    switch captureModel.phase {
    case .unsupported:
      unsupportedView
    case .failed:
      failureView
    case .reconstructing:
      reconstructionView
    case .result:
      resultView
    default:
      captureView
    }
  }

  private var captureView: some View {
    ZStack {
      if let session = captureModel.captureSession {
        ObjectCaptureView(session: session)
          .ignoresSafeArea()
      } else {
        Color.black.ignoresSafeArea()
        ProgressView("Preparing precision scanner…")
          .tint(.white)
          .foregroundStyle(.white)
      }

      VStack(spacing: 12) {
        HStack(alignment: .top, spacing: 10) {
          precisionStatusChip
          Spacer(minLength: 4)
          captureMenu
        }

        Spacer(minLength: 0)

        captureControls
      }
      .padding(.horizontal, 14)
      .padding(.top, 8)
      .padding(.bottom, 12)
    }
  }

  private var precisionStatusChip: some View {
    VStack(alignment: .leading, spacing: 5) {
      Label(captureModel.shortStatus, systemImage: captureModel.statusIcon)
        .font(.subheadline.weight(.semibold))
        .lineLimit(2)

      Text("OBJECT CAPTURE • COHERENT MESH")
        .font(.caption2.weight(.heavy))
        .foregroundStyle(.cyan)

      if captureModel.phase == .capturing {
        HStack(spacing: 8) {
          Label("\(captureModel.shotCount) photos", systemImage: "camera.fill")
          Text("•")
          Text("pass \(captureModel.scanPassNumber)")
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
      }

      if !captureModel.feedbackText.isEmpty {
        Text(captureModel.feedbackText)
          .font(.caption)
          .foregroundStyle(captureModel.feedbackIsWarning ? .orange : .secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .frame(maxWidth: 330, alignment: .leading)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(.white.opacity(0.16), lineWidth: 0.8)
    }
  }

  private var captureMenu: some View {
    Menu {
      Section("Measurement") {
        Button {
          showSettings = true
        } label: {
          Label("Scale calibration", systemImage: "ruler")
        }

        Button {
          showTolerances = true
        } label: {
          Label("Tolerances", systemImage: "checklist")
        }
      }

      Section("Capture") {
        Button {
          showHelp = true
        } label: {
          Label("How precision capture works", systemImage: "questionmark.circle")
        }

        Button(role: .destructive) {
          captureModel.startNewScan()
        } label: {
          Label("Discard and start over", systemImage: "arrow.counterclockwise")
        }
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.headline.weight(.bold))
        .frame(width: 44, height: 44)
        .background(.ultraThinMaterial, in: Circle())
        .overlay {
          Circle().stroke(.white.opacity(0.16), lineWidth: 0.8)
        }
    }
    .foregroundStyle(.primary)
    .accessibilityLabel("More options")
  }

  @ViewBuilder
  private var captureControls: some View {
    switch captureModel.phase {
    case .preparing:
      compactActionPanel {
        HStack(spacing: 12) {
          ProgressView()
          Text("Starting Apple guided capture…")
            .font(.subheadline.weight(.semibold))
        }
      }

    case .ready:
      compactActionPanel {
        VStack(spacing: 9) {
          Text("Center the object in the reticle")
            .font(.headline)
          Text("Apple’s scanner will detect the subject and create an editable 3D selection box.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

          Button {
            captureModel.startDetecting()
          } label: {
            Label("Select Object", systemImage: "viewfinder.circle.fill")
              .fontWeight(.semibold)
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
        }
      }

    case .detecting:
      compactActionPanel {
        VStack(spacing: 9) {
          Text("Adjust the box tightly around the object")
            .font(.headline)
          Text("The system box—not accumulated room depth—defines the subject used for reconstruction.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

          HStack(spacing: 10) {
            Button {
              captureModel.resetDetection()
            } label: {
              Label("Select Again", systemImage: "arrow.counterclockwise")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
              captureModel.startCapturing()
            } label: {
              Label("Use This Box", systemImage: "camera.fill")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
          }
          .controlSize(.large)
        }
      }

    case .capturing:
      compactActionPanel {
        VStack(spacing: 10) {
          if captureModel.scanPassComplete {
            Label("Scan pass complete", systemImage: "checkmark.circle.fill")
              .font(.headline)
              .foregroundStyle(.green)
            Text("For small parts, a second orbit at a different height usually improves edges and the top surface.")
              .font(.caption)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          } else {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text("Move slowly around every side")
                  .font(.headline)
                Text("Let the capture dial fill. Keep the selected object inside the frame.")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Text("\(captureModel.shotCount)")
                .font(.title2.monospacedDigit().weight(.bold))
                .foregroundStyle(.cyan)
            }
          }

          HStack(spacing: 10) {
            if captureModel.scanPassComplete {
              Button {
                captureModel.beginAnotherPass()
              } label: {
                Label("More Angles", systemImage: "arrow.triangle.2.circlepath.camera")
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.bordered)
            }

            Button {
              captureModel.finishCapture(
                specs: appSettings.specs,
                scaleCorrectionFactor: appSettings.scaleCorrectionFactor
              )
            } label: {
              Label(
                captureModel.scanPassComplete ? "Build 3D Model" : "Complete the Orbit",
                systemImage: "cube.fill"
              )
              .fontWeight(.semibold)
              .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!captureModel.canFinishCapture)
          }
          .controlSize(.large)
        }
      }

    case .finishing:
      compactActionPanel {
        HStack(spacing: 12) {
          ProgressView()
            .controlSize(.large)
          VStack(alignment: .leading, spacing: 2) {
            Text("Saving photos and LiDAR data")
              .font(.subheadline.weight(.semibold))
            Text("Keep the app open. Reconstruction starts automatically.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
        }
      }

    default:
      EmptyView()
    }
  }

  private func compactActionPanel<Panel: View>(@ViewBuilder content: () -> Panel) -> some View {
    content()
      .padding(13)
      .frame(maxWidth: 470)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .stroke(.white.opacity(0.16), lineWidth: 0.8)
      }
  }

  private var reconstructionView: some View {
    ZStack {
      LinearGradient(
        colors: [Color.black, Color.indigo.opacity(0.62), Color.black],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      VStack(spacing: 24) {
        Image(systemName: "cube.transparent.fill")
          .font(.system(size: 68, weight: .light))
          .foregroundStyle(.cyan)
          .symbolEffect(.pulse)

        VStack(spacing: 8) {
          Text(captureModel.reconstructionTitle)
            .font(.title2.weight(.bold))
            .multilineTextAlignment(.center)
          Text(captureModel.status)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }

        ProgressView(value: captureModel.reconstructionProgress)
          .progressViewStyle(.linear)
          .frame(maxWidth: 330)

        Text("\(Int((captureModel.reconstructionProgress * 100).rounded()))%")
          .font(.title3.monospacedDigit().weight(.semibold))

        Text("Object Capture combines high-resolution photos with LiDAR, then reconstructs one coherent surface instead of stacking noisy depth sheets.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 360)
      }
      .padding(28)
    }
  }

  private var resultView: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          resultHeader

          if let dimensions = captureModel.dimensions {
            PrecisionDimensionCard(dimensions: dimensions)
          }

          if !captureModel.toleranceResults.isEmpty {
            PrecisionToleranceCard(results: captureModel.toleranceResults)
          }

          calibrationCard
          exportCard

          Button {
            captureModel.startNewScan()
          } label: {
            Label("New Precision Scan", systemImage: "plus.circle.fill")
              .fontWeight(.semibold)
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
        }
        .padding(16)
      }
      .background(Color(uiColor: .systemGroupedBackground))
      .navigationTitle("3D Scan Result")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button {
              showSettings = true
            } label: {
              Label("Scale calibration", systemImage: "ruler")
            }
            Button {
              showTolerances = true
            } label: {
              Label("Tolerances", systemImage: "checklist")
            }
            Button {
              showHelp = true
            } label: {
              Label("Capture guidance", systemImage: "questionmark.circle")
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
        }
      }
    }
  }

  private var resultHeader: some View {
    HStack(spacing: 12) {
      Image(systemName: "checkmark.seal.fill")
        .font(.largeTitle)
        .foregroundStyle(.green)
      VStack(alignment: .leading, spacing: 3) {
        Text("Coherent object mesh created")
          .font(.headline)
        Text("\(captureModel.triangleCount.formatted()) triangles • scale ×\(appSettings.scaleCorrectionFactor, specifier: "%.5f")")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(14)
    .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private var calibrationCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Scale calibration", systemImage: "ruler")
        .font(.headline)

      Text("Calibration changes uniform scale only; it cannot repair missing geometry. Use it after the reconstructed shape looks correct.")
        .font(.caption)
        .foregroundStyle(.secondary)

      if let dimensions = captureModel.dimensions {
        Button {
          let measuredMean = dimensions.meanMM
          guard measuredMean > 0 else { return }
          let newFactor = appSettings.scaleCorrectionFactor * (25.4 / measuredMean)
          appSettings.scaleCorrectionFactor = newFactor
          captureModel.regenerateSTLAndReports(
            specs: appSettings.specs,
            scaleCorrectionFactor: newFactor
          )
        } label: {
          Label("Calibrate this result as a 25.4 mm cube", systemImage: "cube")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
      }

      Button {
        showSettings = true
      } label: {
        Label("Enter a scale factor manually", systemImage: "slider.horizontal.3")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)
    }
    .padding(14)
    .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private var exportCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Files", systemImage: "square.and.arrow.up")
        .font(.headline)

      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
        if let url = captureModel.stlURL {
          ShareLink(item: url) {
            Label("STL (mm)", systemImage: "cube")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
        }

        if let url = captureModel.usdzURL {
          ShareLink(item: url) {
            Label("USDZ", systemImage: "arkit")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
        }

        if let url = captureModel.measurementsURL {
          ShareLink(item: url) {
            Label("Dimensions", systemImage: "ruler")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
        }

        if let url = captureModel.toleranceReportURL {
          ShareLink(item: url) {
            Label("Tolerance", systemImage: "checklist")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
        }
      }
    }
    .padding(14)
    .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private var failureView: some View {
    VStack(spacing: 18) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 58))
        .foregroundStyle(.orange)

      Text("Precision scan stopped")
        .font(.title2.weight(.bold))

      Text(captureModel.errorMessage)
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 430)

      Button {
        captureModel.startNewScan()
      } label: {
        Label("Start a New Scan", systemImage: "arrow.counterclockwise")
          .frame(maxWidth: 300)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
    }
    .padding(28)
  }

  private var unsupportedView: some View {
    VStack(spacing: 18) {
      Image(systemName: "iphone.slash")
        .font(.system(size: 58))
        .foregroundStyle(.orange)
      Text("Object Capture is unavailable")
        .font(.title2.weight(.bold))
      Text("This precision mode requires a supported LiDAR iPhone or iPad and on-device photogrammetry support.")
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)
    }
    .padding(28)
  }
}

// MARK: - Precision capture model

private enum PrecisionCapturePhase: Equatable {
  case preparing
  case ready
  case detecting
  case capturing
  case finishing
  case reconstructing
  case result
  case failed
  case unsupported
}

@MainActor
private final class PrecisionObjectCaptureModel: ObservableObject {
  @Published private(set) var captureSession: ObjectCaptureSession?
  @Published private(set) var phase: PrecisionCapturePhase = .preparing
  @Published private(set) var status: String = "Preparing the precision scanner…"
  @Published private(set) var feedbackText: String = ""
  @Published private(set) var feedbackIsWarning: Bool = false
  @Published private(set) var shotCount: Int = 0
  @Published private(set) var scanPassNumber: Int = 1
  @Published private(set) var scanPassComplete: Bool = false
  @Published private(set) var reconstructionProgress: Double = 0
  @Published private(set) var reconstructionTitle: String = "Reconstructing the object"
  @Published private(set) var errorMessage: String = ""

  @Published private(set) var usdzURL: URL?
  @Published private(set) var stlURL: URL?
  @Published private(set) var measurementsURL: URL?
  @Published private(set) var toleranceReportURL: URL?
  @Published private(set) var dimensions: PrecisionDimensions?
  @Published private(set) var triangleCount: Int = 0
  @Published private(set) var toleranceResults: [ToleranceResult] = []

  private var scanRootURL: URL?
  private var imagesURL: URL?
  private var snapshotsURL: URL?
  private var photogrammetrySession: PhotogrammetrySession?
  private var listenerTasks: [Task<Void, Never>] = []
  private var hasPrepared = false
  private var pendingSpecs: [ToleranceSpec] = ToleranceSpec.defaultObjectSpecs
  private var pendingScaleCorrectionFactor: Double = 1.0

  var showsCamera: Bool {
    switch phase {
    case .preparing, .ready, .detecting, .capturing, .finishing:
      return true
    default:
      return false
    }
  }

  var canFinishCapture: Bool {
    scanPassComplete && shotCount >= 20
  }

  var shortStatus: String {
    switch phase {
    case .preparing:
      return "Starting guided capture"
    case .ready:
      return "Aim at the object"
    case .detecting:
      return "Confirm the detected object box"
    case .capturing:
      return scanPassComplete ? "Scan pass complete" : "Automatic photo + LiDAR capture"
    case .finishing:
      return "Saving capture data"
    case .reconstructing:
      return "Building coherent 3D surface"
    case .result:
      return "STL and dimensions ready"
    case .failed:
      return "Capture failed"
    case .unsupported:
      return "Precision mode unsupported"
    }
  }

  var statusIcon: String {
    switch phase {
    case .ready, .detecting:
      return "viewfinder.circle"
    case .capturing:
      return "camera.fill"
    case .finishing, .reconstructing, .preparing:
      return "waveform.path.ecg"
    case .result:
      return "checkmark.circle.fill"
    case .failed, .unsupported:
      return "exclamationmark.triangle.fill"
    }
  }

  func setAnalysisSettings(specs: [ToleranceSpec], scaleCorrectionFactor: Double) {
    pendingSpecs = specs
    pendingScaleCorrectionFactor = max(0.000_001, scaleCorrectionFactor)
  }

  func prepareIfNeeded() {
    guard !hasPrepared else { return }
    hasPrepared = true
    startNewScan()
  }

  func startNewScan() {
    detachCaptureListeners()
    captureSession?.cancel()
    captureSession = nil
    photogrammetrySession = nil

    usdzURL = nil
    stlURL = nil
    measurementsURL = nil
    toleranceReportURL = nil
    dimensions = nil
    triangleCount = 0
    toleranceResults = []
    shotCount = 0
    scanPassNumber = 1
    scanPassComplete = false
    reconstructionProgress = 0
    feedbackText = ""
    feedbackIsWarning = false
    errorMessage = ""

    guard ObjectCaptureSession.isSupported, PhotogrammetrySession.isSupported else {
      phase = .unsupported
      status = "This device does not support Apple Object Capture."
      return
    }

    do {
      let folderSet = try PrecisionScanFolders.make()
      scanRootURL = folderSet.root
      imagesURL = folderSet.images
      snapshotsURL = folderSet.snapshots
      usdzURL = folderSet.usdz

      let session = ObjectCaptureSession()
      captureSession = session
      attachCaptureListeners(to: session)

      var configuration = ObjectCaptureSession.Configuration()
      configuration.checkpointDirectory = folderSet.snapshots
      configuration.isOverCaptureEnabled = false

      phase = .preparing
      status = "Starting Apple guided object detection…"
      session.start(imagesDirectory: folderSet.images, configuration: configuration)

      if case let .failed(error) = session.state {
        fail("Object Capture could not start: \(error.localizedDescription)")
      }
    } catch {
      fail("Could not create scan folders: \(error.localizedDescription)")
    }
  }

  func startDetecting() {
    guard let captureSession else { return }
    status = "Detecting the object in the center of the camera."
    captureSession.startDetecting()
  }

  func resetDetection() {
    guard let captureSession else { return }
    _ = captureSession.resetDetection()
    status = "Object selection reset. Center the intended object again."
  }

  func startCapturing() {
    guard let captureSession else { return }
    status = "Move slowly around the object. Automatic capture selects useful views."
    captureSession.startCapturing()
  }

  func beginAnotherPass() {
    guard let captureSession else { return }
    scanPassNumber += 1
    scanPassComplete = false
    feedbackText = "Capture from a different height while keeping the object box unchanged."
    feedbackIsWarning = false
    captureSession.beginNewScanPass()
  }

  func finishCapture(specs: [ToleranceSpec], scaleCorrectionFactor: Double) {
    guard let captureSession else { return }
    guard canFinishCapture else {
      feedbackText = "Complete the capture dial and collect at least 20 automatic photos before reconstruction."
      feedbackIsWarning = true
      return
    }

    setAnalysisSettings(specs: specs, scaleCorrectionFactor: scaleCorrectionFactor)
    phase = .finishing
    status = "Saving high-resolution photos and LiDAR data…"
    captureSession.finish()
  }

  func regenerateSTLAndReports(specs: [ToleranceSpec], scaleCorrectionFactor: Double) {
    guard usdzURL != nil else { return }
    setAnalysisSettings(specs: specs, scaleCorrectionFactor: scaleCorrectionFactor)
    phase = .reconstructing
    reconstructionTitle = "Applying dimensional calibration"
    reconstructionProgress = 1.0
    status = "Regenerating the millimeter STL and tolerance reports without repeating reconstruction."

    Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        try await self.generateSTLAndReports()
      } catch {
        self.fail("Could not regenerate calibrated STL: \(error.localizedDescription)")
      }
    }
  }

  private func attachCaptureListeners(to session: ObjectCaptureSession) {
    listenerTasks.append(Task { @MainActor [weak self, weak session] in
      guard let session else { return }
      for await newState in session.stateUpdates {
        guard !Task.isCancelled else { return }
        self?.handleCaptureState(newState)
      }
    })

    listenerTasks.append(Task { @MainActor [weak self, weak session] in
      guard let session else { return }
      for await feedback in session.feedbackUpdates {
        guard !Task.isCancelled else { return }
        self?.handleFeedback(feedback)
      }
    })

    listenerTasks.append(Task { @MainActor [weak self, weak session] in
      guard let session else { return }
      while !Task.isCancelled {
        self?.shotCount = session.numberOfShotsTaken
        self?.scanPassComplete = session.userCompletedScanPass
        try? await Task.sleep(nanoseconds: 250_000_000)
      }
    })
  }

  private func detachCaptureListeners() {
    for task in listenerTasks {
      task.cancel()
    }
    listenerTasks.removeAll()
  }

  private func handleCaptureState(_ newState: ObjectCaptureSession.CaptureState) {
    switch newState {
    case .initializing:
      phase = .preparing
      status = "Initializing camera, LiDAR, and object guidance…"

    case .ready:
      phase = .ready
      status = "Center one object in the reticle, then select it."

    case .detecting:
      phase = .detecting
      status = "Adjust Apple’s detected 3D box so it tightly contains only the object."

    case .capturing:
      phase = .capturing
      status = "Automatic capture is collecting sharp photos and LiDAR from useful angles."

    case .finishing:
      phase = .finishing
      status = "Finishing the capture and writing all sensor data…"

    case .completed:
      phase = .reconstructing
      reconstructionTitle = "Reconstructing a coherent object mesh"
      reconstructionProgress = 0
      status = "Photogrammetry is fusing the selected photos and LiDAR points."
      detachCaptureListeners()
      captureSession = nil
      Task { @MainActor [weak self] in
        await self?.runReconstruction()
      }

    case let .failed(error):
      fail("Object Capture failed: \(error.localizedDescription)")

    @unknown default:
      status = "Object Capture changed to an unknown state."
    }
  }

  private func handleFeedback(_ feedback: Set<ObjectCaptureSession.Feedback>) {
    feedbackIsWarning = true

    if feedback.contains(.environmentTooDark) {
      feedbackText = "Increase diffuse lighting; automatic capture is paused in darkness."
    } else if feedback.contains(.movingTooFast) {
      feedbackText = "Move more slowly so the camera can capture sharp images."
    } else if feedback.contains(.objectTooClose) {
      feedbackText = "Move the phone slightly farther from the object."
    } else if feedback.contains(.objectTooFar) {
      feedbackText = "Move closer while keeping the complete object box in frame."
    } else if feedback.contains(.outOfFieldOfView) {
      feedbackText = "Point back toward the selected object; its box left the camera view."
    } else if #available(iOS 17.4, *), feedback.contains(.objectNotDetected) {
      feedbackText = "Automatic subject detection was uncertain. Adjust the manual box tightly."
    } else {
      feedbackIsWarning = false
      feedbackText = phase == .capturing
        ? "Automatic capture is choosing sharp, well-exposed views."
        : ""
    }
  }

  private func runReconstruction() async {
    guard let imagesURL, let snapshotsURL, let usdzURL else {
      fail("The capture folders are unavailable.")
      return
    }

    do {
      if FileManager.default.fileExists(atPath: usdzURL.path) {
        try FileManager.default.removeItem(at: usdzURL)
      }

      var configuration = PhotogrammetrySession.Configuration()
      configuration.checkpointDirectory = snapshotsURL

      let session = try PhotogrammetrySession(input: imagesURL, configuration: configuration)
      photogrammetrySession = session
      try session.process(requests: [.modelFile(url: usdzURL)])

      var completed = false
      for try await output in session.outputs {
        switch output {
        case let .requestProgress(_, fractionComplete: fraction):
          reconstructionProgress = min(max(fraction, 0), 1)
          status = "Reconstructing the selected subject from \(shotCount) captured views."

        case let .requestError(_, error):
          throw error

        case .processingComplete:
          completed = true
          reconstructionProgress = 1
          status = "3D reconstruction complete. Converting to millimeter STL…"
          try await generateSTLAndReports()

        default:
          break
        }
      }

      if !completed && phase == .reconstructing {
        throw PrecisionCaptureError("Photogrammetry ended before producing a model.")
      }
    } catch {
      fail("3D reconstruction failed: \(error.localizedDescription)")
    }
  }

  private func generateSTLAndReports() async throws {
    guard let usdzURL, let scanRootURL else {
      throw PrecisionCaptureError("The reconstructed model location is unavailable.")
    }

    let specs = pendingSpecs
    let correction = pendingScaleCorrectionFactor

    let output = try await Task.detached(priority: .userInitiated) {
      try PrecisionOutputBuilder.build(
        usdzURL: usdzURL,
        outputDirectory: scanRootURL,
        scaleCorrectionFactor: correction,
        specs: specs
      )
    }.value

    stlURL = output.stlURL
    measurementsURL = output.measurementsURL
    toleranceReportURL = output.toleranceReportURL
    dimensions = output.dimensions
    triangleCount = output.dimensions.triangleCount
    toleranceResults = output.toleranceResults
    reconstructionProgress = 1
    status = "The coherent model was converted to STL in millimeters and measured."
    phase = .result
  }

  private func fail(_ message: String) {
    detachCaptureListeners()
    errorMessage = message
    status = message
    phase = .failed
  }
}

// MARK: - Output creation and STL scaling

private struct PrecisionScanFolders {
  let root: URL
  let images: URL
  let snapshots: URL
  let usdz: URL

  static func make() throws -> PrecisionScanFolders {
    let fileManager = FileManager.default
    let documents = try fileManager.url(
      for: .documentDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )

    let root = documents
      .appendingPathComponent("PrecisionObjectScans", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let images = root.appendingPathComponent("Images", isDirectory: true)
    let snapshots = root.appendingPathComponent("Snapshots", isDirectory: true)
    let usdz = root.appendingPathComponent("object.usdz")

    try fileManager.createDirectory(at: images, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: snapshots, withIntermediateDirectories: true)

    return PrecisionScanFolders(root: root, images: images, snapshots: snapshots, usdz: usdz)
  }
}

private struct PrecisionDimensions: Equatable, Sendable {
  let xMM: Double
  let yMM: Double
  let zMM: Double
  let triangleCount: Int

  var meanMM: Double {
    (xMM + yMM + zMM) / 3.0
  }

  var compactDescription: String {
    String(format: "%.2f × %.2f × %.2f mm", xMM, yMM, zMM)
  }
}

private struct PrecisionOutputBundle: Sendable {
  let stlURL: URL
  let measurementsURL: URL
  let toleranceReportURL: URL
  let dimensions: PrecisionDimensions
  let toleranceResults: [ToleranceResult]
}

private enum PrecisionOutputBuilder {
  static func build(
    usdzURL: URL,
    outputDirectory: URL,
    scaleCorrectionFactor: Double,
    specs: [ToleranceSpec]
  ) throws -> PrecisionOutputBundle {
    guard FileManager.default.fileExists(atPath: usdzURL.path) else {
      throw PrecisionCaptureError("The reconstructed USDZ file does not exist.")
    }

    guard MDLAsset.canImportFileExtension(usdzURL.pathExtension) else {
      throw PrecisionCaptureError("Model I/O cannot import the reconstructed USDZ file.")
    }
    guard MDLAsset.canExportFileExtension("stl") else {
      throw PrecisionCaptureError("This iOS build cannot export STL through Model I/O.")
    }

    let asset = MDLAsset(url: usdzURL)
    guard asset.count > 0 else {
      throw PrecisionCaptureError("The reconstructed USDZ contains no mesh objects.")
    }

    let rawSTLURL = outputDirectory.appendingPathComponent("object_meters_raw.stl")
    let finalSTLURL = outputDirectory.appendingPathComponent("object_mm.stl")
    let measurementsURL = outputDirectory.appendingPathComponent("object_dimensions.csv")
    let toleranceURL = outputDirectory.appendingPathComponent("object_tolerance.csv")

    for url in [rawSTLURL, finalSTLURL, measurementsURL, toleranceURL] {
      if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
    }

    try asset.export(to: rawSTLURL)

    // Object Capture / RealityKit uses meters. Convert the STL coordinates to
    // millimeters, apply the user's calibration factor, and translate the model so
    // its minimum corner is the STL origin.
    let scale = 1_000.0 * max(scaleCorrectionFactor, 0.000_001)
    let dimensions = try STLPostProcessor.scaleTranslateAndMeasure(
      inputURL: rawSTLURL,
      outputURL: finalSTLURL,
      scale: scale
    )

    let measurements: [MeshMeasurement] = [
      MeshMeasurement(name: "triangle_count", value: Double(dimensions.triangleCount), unit: "count"),
      MeshMeasurement(name: "bbox_x_mm", value: dimensions.xMM, unit: "mm"),
      MeshMeasurement(name: "bbox_y_mm", value: dimensions.yMM, unit: "mm"),
      MeshMeasurement(name: "bbox_z_mm", value: dimensions.zMM, unit: "mm"),
      MeshMeasurement(name: "scale_correction_factor", value: scaleCorrectionFactor, unit: "ratio"),
    ]

    let measurementDictionary = Dictionary(uniqueKeysWithValues: measurements.map { ($0.name, $0.value) })
    let toleranceResults = ToleranceAnalyzer.analyze(
      measurements: measurementDictionary,
      specs: specs
    )

    try CSVExporter.measurementsCSV(measurements: measurements)
      .write(to: measurementsURL, atomically: true, encoding: .utf8)
    try CSVExporter.toleranceReportCSV(results: toleranceResults)
      .write(to: toleranceURL, atomically: true, encoding: .utf8)

    return PrecisionOutputBundle(
      stlURL: finalSTLURL,
      measurementsURL: measurementsURL,
      toleranceReportURL: toleranceURL,
      dimensions: dimensions,
      toleranceResults: toleranceResults
    )
  }
}

private enum STLPostProcessor {
  static func scaleTranslateAndMeasure(
    inputURL: URL,
    outputURL: URL,
    scale: Double
  ) throws -> PrecisionDimensions {
    let data = try Data(contentsOf: inputURL)
    guard !data.isEmpty else {
      throw PrecisionCaptureError("Model I/O produced an empty STL file.")
    }

    if isBinarySTL(data) {
      return try processBinary(data: data, outputURL: outputURL, scale: scale)
    }
    return try processASCII(data: data, outputURL: outputURL, scale: scale)
  }

  private static func isBinarySTL(_ data: Data) -> Bool {
    guard data.count >= 84 else { return false }
    let bytes = [UInt8](data)
    let triangleCount = Int(readUInt32LE(bytes, offset: 80))
    guard triangleCount >= 0 else { return false }
    return 84 + triangleCount * 50 == data.count
  }

  private static func processBinary(
    data: Data,
    outputURL: URL,
    scale: Double
  ) throws -> PrecisionDimensions {
    var bytes = [UInt8](data)
    let triangleCount = Int(readUInt32LE(bytes, offset: 80))
    guard triangleCount > 0 else {
      throw PrecisionCaptureError("The STL contains no triangles.")
    }

    var minimum = SIMD3<Double>(repeating: .infinity)
    var maximum = SIMD3<Double>(repeating: -.infinity)

    for triangleIndex in 0..<triangleCount {
      let recordStart = 84 + triangleIndex * 50
      for vertexIndex in 0..<3 {
        let vertexStart = recordStart + 12 + vertexIndex * 12
        let point = SIMD3<Double>(
          Double(readFloatLE(bytes, offset: vertexStart)) * scale,
          Double(readFloatLE(bytes, offset: vertexStart + 4)) * scale,
          Double(readFloatLE(bytes, offset: vertexStart + 8)) * scale
        )
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite else { continue }
        minimum = SIMD3<Double>(
          Swift.min(minimum.x, point.x),
          Swift.min(minimum.y, point.y),
          Swift.min(minimum.z, point.z)
        )
        maximum = SIMD3<Double>(
          Swift.max(maximum.x, point.x),
          Swift.max(maximum.y, point.y),
          Swift.max(maximum.z, point.z)
        )
      }
    }

    guard minimum.x.isFinite, maximum.x.isFinite else {
      throw PrecisionCaptureError("The STL vertices are invalid.")
    }

    for triangleIndex in 0..<triangleCount {
      let recordStart = 84 + triangleIndex * 50
      for vertexIndex in 0..<3 {
        let vertexStart = recordStart + 12 + vertexIndex * 12
        let translated = SIMD3<Float>(
          Float(Double(readFloatLE(bytes, offset: vertexStart)) * scale - minimum.x),
          Float(Double(readFloatLE(bytes, offset: vertexStart + 4)) * scale - minimum.y),
          Float(Double(readFloatLE(bytes, offset: vertexStart + 8)) * scale - minimum.z)
        )
        writeFloatLE(translated.x, into: &bytes, offset: vertexStart)
        writeFloatLE(translated.y, into: &bytes, offset: vertexStart + 4)
        writeFloatLE(translated.z, into: &bytes, offset: vertexStart + 8)
      }
    }

    try Data(bytes).write(to: outputURL, options: .atomic)
    let size = maximum - minimum
    return PrecisionDimensions(
      xMM: size.x,
      yMM: size.y,
      zMM: size.z,
      triangleCount: triangleCount
    )
  }

  private static func processASCII(
    data: Data,
    outputURL: URL,
    scale: Double
  ) throws -> PrecisionDimensions {
    guard let text = String(data: data, encoding: .utf8) else {
      throw PrecisionCaptureError("The STL is neither valid binary nor UTF-8 ASCII.")
    }

    let lines = text.components(separatedBy: .newlines)
    var minimum = SIMD3<Double>(repeating: .infinity)
    var maximum = SIMD3<Double>(repeating: -.infinity)
    var triangleCount = 0

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.hasPrefix("facet normal") {
        triangleCount += 1
      }
      guard let point = parseASCIIVertex(trimmed, scale: scale) else { continue }
      minimum = SIMD3<Double>(
        Swift.min(minimum.x, point.x),
        Swift.min(minimum.y, point.y),
        Swift.min(minimum.z, point.z)
      )
      maximum = SIMD3<Double>(
        Swift.max(maximum.x, point.x),
        Swift.max(maximum.y, point.y),
        Swift.max(maximum.z, point.z)
      )
    }

    guard minimum.x.isFinite, maximum.x.isFinite else {
      throw PrecisionCaptureError("The ASCII STL contains no valid vertices.")
    }

    var outputLines: [String] = []
    outputLines.reserveCapacity(lines.count)
    var vertexCount = 0

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let point = parseASCIIVertex(trimmed, scale: scale) else {
        outputLines.append(line)
        continue
      }

      vertexCount += 1
      let indent = String(line.prefix { $0 == " " || $0 == "\t" })
      outputLines.append(
        indent + "vertex "
          + formatSTLNumber(point.x - minimum.x) + " "
          + formatSTLNumber(point.y - minimum.y) + " "
          + formatSTLNumber(point.z - minimum.z)
      )
    }

    if triangleCount == 0 {
      triangleCount = vertexCount / 3
    }
    guard triangleCount > 0 else {
      throw PrecisionCaptureError("The ASCII STL contains no triangles.")
    }

    try outputLines.joined(separator: "\n")
      .write(to: outputURL, atomically: true, encoding: .utf8)

    let size = maximum - minimum
    return PrecisionDimensions(
      xMM: size.x,
      yMM: size.y,
      zMM: size.z,
      triangleCount: triangleCount
    )
  }

  private static func parseASCIIVertex(_ line: String, scale: Double) -> SIMD3<Double>? {
    let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
    guard parts.count == 4, parts[0] == "vertex",
          let x = Double(parts[1]),
          let y = Double(parts[2]),
          let z = Double(parts[3]) else {
      return nil
    }
    return SIMD3<Double>(x * scale, y * scale, z * scale)
  }

  private static func formatSTLNumber(_ value: Double) -> String {
    String(format: "%.9g", locale: Locale(identifier: "en_US_POSIX"), value)
  }

  private static func readUInt32LE(_ bytes: [UInt8], offset: Int) -> UInt32 {
    UInt32(bytes[offset])
      | (UInt32(bytes[offset + 1]) << 8)
      | (UInt32(bytes[offset + 2]) << 16)
      | (UInt32(bytes[offset + 3]) << 24)
  }

  private static func readFloatLE(_ bytes: [UInt8], offset: Int) -> Float {
    Float(bitPattern: readUInt32LE(bytes, offset: offset))
  }

  private static func writeFloatLE(_ value: Float, into bytes: inout [UInt8], offset: Int) {
    let bits = value.bitPattern
    bytes[offset] = UInt8(bits & 0xff)
    bytes[offset + 1] = UInt8((bits >> 8) & 0xff)
    bytes[offset + 2] = UInt8((bits >> 16) & 0xff)
    bytes[offset + 3] = UInt8((bits >> 24) & 0xff)
  }
}

private struct PrecisionCaptureError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}

// MARK: - Result views

private struct PrecisionDimensionCard: View {
  let dimensions: PrecisionDimensions

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Dimensions from final STL", systemImage: "ruler.fill")
          .font(.headline)
        Spacer()
        Text("\(dimensions.triangleCount.formatted()) tris")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 8) {
        dimensionColumn(label: "X", value: dimensions.xMM, color: .pink)
        Divider()
        dimensionColumn(label: "Y", value: dimensions.yMM, color: .orange)
        Divider()
        dimensionColumn(label: "Z", value: dimensions.zMM, color: .green)
      }
      .frame(maxWidth: .infinity)
    }
    .padding(14)
    .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private func dimensionColumn(label: String, value: Double, color: Color) -> some View {
    VStack(spacing: 4) {
      Text(label)
        .font(.caption.weight(.bold))
        .foregroundStyle(color)
      Text(value, format: .number.precision(.fractionLength(2)))
        .font(.title3.monospacedDigit().weight(.semibold))
      Text("mm")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
  }
}

private struct PrecisionToleranceCard: View {
  let results: [ToleranceResult]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Tolerance analysis", systemImage: "checklist")
        .font(.headline)

      ForEach(results) { result in
        HStack(spacing: 8) {
          Circle()
            .fill(statusColor(result.status))
            .frame(width: 8, height: 8)
          Text(result.name)
            .font(.caption.monospaced())
          Spacer()
          if let measured = result.measuredMM {
            Text(measured, format: .number.precision(.fractionLength(2)))
              .font(.caption.monospacedDigit())
            Text("mm")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          Text(result.status.rawValue)
            .font(.caption.weight(.bold))
            .foregroundStyle(statusColor(result.status))
        }
      }
    }
    .padding(14)
    .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private func statusColor(_ status: ToleranceStatus) -> Color {
    switch status {
    case .pass:
      return .green
    case .failLow, .failHigh:
      return .red
    case .missing:
      return .orange
    }
  }
}

private struct PrecisionScanSettingsView: View {
  @EnvironmentObject private var settings: ScannerViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("Dimensional scale") {
          TextField(
            "Scale correction factor",
            value: $settings.scaleCorrectionFactor,
            format: .number.precision(.fractionLength(6))
          )
          .keyboardType(.decimalPad)

          Text("Final STL coordinates are converted from meters to millimeters, then multiplied by this factor. Leave it at 1.000000 until you validate a coherent model against a gauge or calibration artifact.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        Section("Example") {
          Text("If a known 25.400 mm dimension reconstructs as 25.000 mm, use 25.400 ÷ 25.000 = 1.016000.")
            .font(.footnote.monospacedDigit())
        }
      }
      .navigationTitle("Precision Settings")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}

private struct PrecisionCaptureHelpView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section("Why this mode is different") {
          Text("It uses Apple Object Capture instead of accumulating raw AR depth triangles. The system selects the subject, captures high-resolution photos and LiDAR, and reconstructs one coherent model on the iPhone.")
        }

        Section("Recommended workflow") {
          Label("Place one stationary object on a textured, nonreflective surface.", systemImage: "1.circle.fill")
          Label("Select the object and tighten the automatic 3D box.", systemImage: "2.circle.fill")
          Label("Complete one full orbit slowly; add another pass from a different height for small parts.", systemImage: "3.circle.fill")
          Label("Finish, wait for reconstruction, then share STL or USDZ.", systemImage: "4.circle.fill")
        }

        Section("For a 25.4 mm calibration cube") {
          Text("Use bright diffuse light. A plain black or glossy cube may need temporary removable texture—small paper dots or a washable scanning spray—to give photogrammetry stable visual features. Do not move the cube during a pass.")
        }

        Section("Measurement caution") {
          Text("Object Capture is substantially better for a coherent surface, but it is still not an industrial CMM. Validate repeatability with calibrated gauges before using pass/fail results for production acceptance.")
        }
      }
      .navigationTitle("Precision Capture")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}
