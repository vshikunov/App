import Foundation
import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var model: ScannerViewModel

  @State private var showSettings = false
  @State private var showTolerances = false
  @State private var showHelp = false
  @State private var statusExpanded = false
  @State private var controlsHidden = false

  var body: some View {
    ZStack {
      ARScannerView()
        .ignoresSafeArea()

      MeasurementReticle(
        hasSurface: model.reticleHasSurface,
        distanceMM: model.reticleDistanceMM,
        isScanning: model.isScanning
      )
      .allowsHitTesting(false)

      if controlsHidden {
        hiddenControlsButton
      } else {
        visibleChrome
      }
    }
    .sheet(isPresented: $showSettings) {
      ScanSettingsView()
        .environmentObject(model)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showTolerances) {
      ToleranceEditorView()
        .environmentObject(model)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showHelp) {
      GroundAreaHelpView()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    .animation(.snappy(duration: 0.25), value: model.workflowPhase)
    .animation(.snappy(duration: 0.2), value: statusExpanded)
    .animation(.snappy(duration: 0.2), value: controlsHidden)
  }

  private var visibleChrome: some View {
    VStack(spacing: 12) {
      HStack(alignment: .top, spacing: 10) {
        statusChip
        Spacer(minLength: 4)
        FloatingIconButton(
          systemImage: "eye.slash",
          accessibilityLabel: "Hide controls"
        ) {
          controlsHidden = true
        }
        optionsMenu
      }

      Spacer(minLength: 0)

      phaseControls
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    .padding(.horizontal, 14)
    .padding(.top, 8)
    .padding(.bottom, 10)
  }

  private var hiddenControlsButton: some View {
    VStack {
      HStack {
        Spacer()
        FloatingIconButton(
          systemImage: "eye",
          accessibilityLabel: "Show controls"
        ) {
          controlsHidden = false
        }
      }
      Spacer()
    }
    .padding(.horizontal, 14)
    .padding(.top, 8)
  }

  private var statusChip: some View {
    Button {
      statusExpanded.toggle()
    } label: {
      HStack(alignment: .top, spacing: 9) {
        Image(systemName: statusIcon)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(statusColor)
          .frame(width: 20, height: 20)

        VStack(alignment: .leading, spacing: 3) {
          Text(model.compactStatusTitle)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)

          if statusExpanded {
            Text(model.status)
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 7) {
              Text(model.trackingSummary)
              if let summary = model.groundAreaSummary {
                Text("•")
                Text("Area \(summary.compactDescription)")
              }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            if model.groundAreaReady {
              Label(model.objectIsolationMessage, systemImage: "viewfinder.circle")
                .font(.caption2)
                .foregroundStyle(.cyan)
                .lineLimit(2)
            }

            if let meshDimensions = model.exportedSTLDimensions ?? model.liveMeshDimensions {
              Label(
                "Object \(meshDimensions.compactDescription)",
                systemImage: "cube.fill"
              )
              .font(.caption2.monospacedDigit().weight(.semibold))
              .foregroundStyle(.green)
            }
          }
        }

        Image(systemName: statusExpanded ? "chevron.up" : "chevron.down")
          .font(.caption2.weight(.bold))
          .foregroundStyle(.secondary)
          .padding(.top, 3)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(maxWidth: 320, alignment: .leading)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(.white.opacity(0.15), lineWidth: 0.8)
      }
    }
    .buttonStyle(.plain)
  }

  private var optionsMenu: some View {
    Menu {
      Section("Display") {
        Toggle(isOn: $model.showCapturedSurface) {
          Label("Detected object surface", systemImage: "square.3.layers.3d")
        }
        Toggle(isOn: $model.showBoundingBox) {
          Label("Ground area and object bounds", systemImage: "viewfinder")
        }
        Toggle(isOn: $model.showMeshOverlay) {
          Label("Full-room debug mesh", systemImage: "point.3.filled.connected.trianglepath.dotted")
        }
      }

      Section("Configuration") {
        Button {
          showSettings = true
        } label: {
          Label("Scan settings", systemImage: "slider.horizontal.3")
        }
        Button {
          showTolerances = true
        } label: {
          Label("Tolerances", systemImage: "checklist")
        }
        Button {
          showHelp = true
        } label: {
          Label("How the four ground points work", systemImage: "questionmark.circle")
        }
      }

      Section("Fallback") {
        Button {
          model.setObjectCenter()
        } label: {
          Label("Set manual crop center", systemImage: "scope")
        }
      }

      Section {
        Button {
          model.clearReferencePoints()
        } label: {
          Label("Clear ground area", systemImage: "trash")
        }
        .disabled(model.referencePoints.isEmpty)

        Button(role: .destructive) {
          model.resetScan()
        } label: {
          Label("Reset AR session", systemImage: "arrow.counterclockwise")
        }
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.headline.weight(.bold))
        .frame(width: 44, height: 44)
        .background(.ultraThinMaterial, in: Circle())
        .overlay {
          Circle().stroke(.white.opacity(0.15), lineWidth: 0.8)
        }
    }
    .foregroundStyle(.primary)
    .accessibilityLabel("More options")
  }

  @ViewBuilder
  private var phaseControls: some View {
    switch model.workflowPhase {
    case .definingArea:
      definingAreaControls
    case .readyToScan:
      readyToScanControls
    case .scanning:
      scanningControls
    case .review:
      reviewControls
    case .processing:
      processingControls
    case .exported:
      exportedControls
    }
  }

  private var definingAreaControls: some View {
    VStack(spacing: 10) {
      VStack(spacing: 5) {
        Text(model.nextReferencePointLabel)
          .font(.headline)
        Text(model.nextReferencePointInstruction)
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(2)
        ReferenceProgressDots(capturedCount: model.referencePoints.count)
      }

      HStack(alignment: .center, spacing: 26) {
        BottomCircleButton(
          title: "Undo",
          systemImage: "arrow.uturn.backward",
          enabled: !model.referencePoints.isEmpty
        ) {
          model.undoReferencePoint()
        }

        Button {
          model.captureReferencePoint()
        } label: {
          ZStack {
            Circle()
              .fill(model.reticleHasSurface ? Color.white : Color.secondary.opacity(0.55))
              .frame(width: 70, height: 70)
              .shadow(color: .black.opacity(0.24), radius: 8, y: 3)
            Circle()
              .stroke(.black.opacity(0.2), lineWidth: 1)
              .frame(width: 60, height: 60)
            Image(systemName: "plus")
              .font(.system(size: 29, weight: .medium))
              .foregroundStyle(model.reticleHasSurface ? .black : .white.opacity(0.65))
          }
        }
        .buttonStyle(.plain)
        .disabled(!model.canCaptureMoreReferencePoints || !model.reticleHasSurface)
        .accessibilityLabel("Capture \(model.nextReferencePointLabel)")

        BottomCircleButton(
          title: "Help",
          systemImage: "questionmark",
          enabled: true
        ) {
          showHelp = true
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(maxWidth: 390)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .stroke(.white.opacity(0.15), lineWidth: 0.8)
    }
  }

  private var readyToScanControls: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Label("Ground area ready", systemImage: "checkmark.seal.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.green)
        if let summary = model.groundAreaSummary {
          Text("\(summary.compactDescription) • \(summary.areaDescription)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }

      Spacer()

      Button {
        model.undoReferencePoint()
      } label: {
        Image(systemName: "pencil")
          .frame(width: 40, height: 40)
      }
      .buttonStyle(.bordered)
      .accessibilityLabel("Edit ground area")

      Button {
        model.startSurfaceScan()
      } label: {
        Label("Scan Object", systemImage: "viewfinder")
          .fontWeight(.semibold)
      }
      .buttonStyle(.borderedProminent)
    }
    .padding(12)
    .frame(maxWidth: 430)
    .background(.ultraThinMaterial, in: Capsule())
  }

  private var scanningControls: some View {
    VStack(spacing: 9) {
      if let dimensions = model.liveMeshDimensions {
        STLDimensionPanel(title: "Detected object size", summary: dimensions, compact: true)
      }

      HStack(spacing: 12) {
        SurfaceScanProgressRing(progress: model.scanCoveragePercent / 100)
          .frame(width: 46, height: 46)

        VStack(alignment: .leading, spacing: 2) {
          Text(model.liveMeshDimensions == nil ? "Finding object in the area" : "Object isolated — capture all sides")
            .font(.subheadline.weight(.semibold))
          Text(
            "\(Int(model.scanCoveragePercent.rounded()))% views • \(model.capturedSurfaceTriangleCount.formatted()) triangles"
          )
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)
        }

        Spacer(minLength: 2)

        Button {
          model.stopSurfaceScan()
        } label: {
          Image(systemName: "pause.fill")
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Pause object scan")

        Button {
          model.finishSurfaceScanAndCreateSTL()
        } label: {
          Label("Finish & Measure", systemImage: "checkmark.circle.fill")
            .fontWeight(.semibold)
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.capturedSurfaceTriangleCount == 0)
      }
    }
    .padding(11)
    .frame(maxWidth: 480)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  private var reviewControls: some View {
    VStack(spacing: 9) {
      if let dimensions = model.liveMeshDimensions {
        STLDimensionPanel(title: "Detected object bounds", summary: dimensions, compact: true)
      } else {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Object surface preview")
              .font(.subheadline.weight(.semibold))
            Text(
              "\(model.capturedSurfaceTriangleCount.formatted()) triangles • \(Int(model.scanCoveragePercent.rounded()))% views"
            )
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
          }
          Spacer()
        }
      }

      HStack(spacing: 10) {
        Button {
          model.resumeSurfaceScan()
        } label: {
          Label("Resume", systemImage: "record.circle")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)

        Button {
          model.finishSurfaceScanAndCreateSTL()
        } label: {
          Label("Create STL & Measure", systemImage: "cube.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.capturedSurfaceTriangleCount == 0)
      }
    }
    .padding(12)
    .frame(maxWidth: 440)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  private var processingControls: some View {
    HStack(spacing: 12) {
      ProgressView()
        .controlSize(.large)

      VStack(alignment: .leading, spacing: 2) {
        Text("Identifying object and building STL")
          .font(.subheadline.weight(.semibold))
        Text("Removing the ground, selecting the connected object surface, and measuring the mesh…")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Spacer()
    }
    .padding(.horizontal, 15)
    .padding(.vertical, 12)
    .frame(maxWidth: 450)
    .background(.ultraThinMaterial, in: Capsule())
  }

  private var exportedControls: some View {
    VStack(spacing: 9) {
      HStack {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
        VStack(alignment: .leading, spacing: 2) {
          Text("Object STL complete")
            .font(.subheadline.weight(.semibold))
          Text("\(model.lastTriangleCount.formatted()) triangles • \(model.lastVertexCount.formatted()) vertices")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }

      if let dimensions = model.exportedSTLDimensions {
        STLDimensionPanel(title: "Dimensional display from STL data", summary: dimensions, compact: false)
      }

      if !model.toleranceResults.isEmpty {
        ResultSummaryView(results: model.toleranceResults)
      }

      HStack(spacing: 8) {
        if let stlURL = model.lastSTLURL {
          ShareLink(item: stlURL) {
            Label("STL", systemImage: "cube")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
        }

        if let dimensionsURL = model.lastMeasurementsURL {
          ShareLink(item: dimensionsURL) {
            Label("Dims", systemImage: "ruler")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
        }

        if let reportURL = model.lastReportURL {
          ShareLink(item: reportURL) {
            Label("Tol.", systemImage: "checklist")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
        }

        Button {
          model.resetScan()
        } label: {
          Label("New", systemImage: "plus")
        }
        .buttonStyle(.bordered)
      }
    }
    .padding(12)
    .frame(maxWidth: 450)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  private var statusIcon: String {
    switch model.workflowPhase {
    case .definingArea: return "square.dashed"
    case .readyToScan: return "viewfinder"
    case .scanning: return "wave.3.right.circle.fill"
    case .review: return "eye.circle.fill"
    case .processing: return "gearshape.2.fill"
    case .exported: return "checkmark.circle.fill"
    }
  }

  private var statusColor: Color {
    switch model.workflowPhase {
    case .definingArea: return model.reticleHasSurface ? .cyan : .orange
    case .readyToScan: return .green
    case .scanning: return .cyan
    case .review: return .blue
    case .processing: return .orange
    case .exported: return .green
    }
  }
}

private struct MeasurementReticle: View {
  let hasSurface: Bool
  let distanceMM: Double?
  let isScanning: Bool

  private var tint: Color {
    hasSurface ? .cyan : .orange
  }

  var body: some View {
    VStack(spacing: 7) {
      ZStack {
        Circle()
          .stroke(.black.opacity(0.5), lineWidth: 4)
          .frame(width: 50, height: 50)
        Circle()
          .stroke(tint, lineWidth: 2)
          .frame(width: 50, height: 50)

        Rectangle()
          .fill(tint)
          .frame(width: 18, height: 1.5)
        Rectangle()
          .fill(tint)
          .frame(width: 1.5, height: 18)

        Circle()
          .fill(tint)
          .frame(width: 5, height: 5)
      }
      .shadow(color: .black.opacity(0.5), radius: 2)

      if let distanceMM, !isScanning {
        Text(distanceText(distanceMM))
          .font(.caption2.monospacedDigit().weight(.semibold))
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(.black.opacity(0.55), in: Capsule())
          .foregroundStyle(.white)
      }
    }
  }

  private func distanceText(_ millimeters: Double) -> String {
    if millimeters < 1000 {
      return String(format: "%.0f mm", millimeters)
    }
    return String(format: "%.2f m", millimeters / 1000)
  }
}

private struct ReferenceProgressDots: View {
  let capturedCount: Int

  var body: some View {
    HStack(spacing: 8) {
      ForEach(0..<4, id: \.self) { index in
        Circle()
          .fill(dotColor(index))
          .frame(width: index == capturedCount ? 8 : 6, height: index == capturedCount ? 8 : 6)
          .overlay {
            Circle()
              .stroke(.white.opacity(index < capturedCount ? 0.7 : 0.3), lineWidth: 1)
          }
      }
    }
    .accessibilityLabel("\(capturedCount) of 4 ground points captured")
  }

  private func dotColor(_ index: Int) -> Color {
    guard index < capturedCount else {
      return index == capturedCount ? .white.opacity(0.75) : .secondary.opacity(0.35)
    }
    switch index {
    case 0: return .cyan
    case 1: return .blue
    case 2: return .indigo
    default: return .purple
    }
  }
}

private struct SurfaceScanProgressRing: View {
  let progress: Double

  var body: some View {
    ZStack {
      Circle()
        .stroke(.white.opacity(0.2), lineWidth: 5)
      Circle()
        .trim(from: 0, to: min(max(progress, 0), 1))
        .stroke(.cyan, style: StrokeStyle(lineWidth: 5, lineCap: .round))
        .rotationEffect(.degrees(-90))
      Text("\(Int((progress * 100).rounded()))")
        .font(.caption2.monospacedDigit().bold())
    }
  }
}

private struct STLDimensionPanel: View {
  let title: String
  let summary: STLDimensionSummary
  let compact: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 5 : 8) {
      HStack(spacing: 7) {
        Label(title, systemImage: "cube.fill")
          .font((compact ? Font.caption : Font.subheadline).weight(.semibold))
          .foregroundStyle(.cyan)
        Spacer()
        Text("\(summary.triangleCount.formatted()) tris")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
      }

      HStack(spacing: compact ? 7 : 10) {
        axisValue("W / X", value: summary.widthMM, color: .purple)
        axisValue("H / Y", value: summary.heightMM, color: .orange)
        axisValue("D / Z", value: summary.depthMM, color: .green)
      }
    }
    .padding(.horizontal, compact ? 9 : 11)
    .padding(.vertical, compact ? 7 : 9)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
  }

  private func axisValue(_ axis: String, value: Double, color: Color) -> some View {
    VStack(spacing: 2) {
      Text(axis)
        .font(.caption2.bold())
        .foregroundStyle(color)
      HStack(spacing: 3) {
        Text(value, format: .number.precision(.fractionLength(1)))
          .font(.caption.monospacedDigit().weight(.semibold))
        Text("mm")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity)
  }
}

private struct FloatingIconButton: View {
  let systemImage: String
  let accessibilityLabel: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.headline)
        .frame(width: 44, height: 44)
        .background(.ultraThinMaterial, in: Circle())
        .overlay {
          Circle().stroke(.white.opacity(0.15), lineWidth: 0.8)
        }
    }
    .buttonStyle(.plain)
    .foregroundStyle(.primary)
    .accessibilityLabel(accessibilityLabel)
  }
}

private struct BottomCircleButton: View {
  let title: String
  let systemImage: String
  let enabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 5) {
        Image(systemName: systemImage)
          .font(.headline)
          .frame(width: 42, height: 42)
          .background(.thinMaterial, in: Circle())
        Text(title)
          .font(.caption2.weight(.semibold))
      }
      .frame(width: 62)
    }
    .buttonStyle(.plain)
    .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.5))
    .disabled(!enabled)
  }
}

private struct GroundAreaHelpStep: Identifiable {
  let id: Int
  let title: String
  let detail: String
  let color: Color
}

private struct GroundAreaHelpView: View {
  @Environment(\.dismiss) private var dismiss

  private let steps = [
    GroundAreaHelpStep(
      id: 1,
      title: "First ground corner",
      detail: "Aim at the flat support surface just outside one corner of the object.",
      color: .cyan),
    GroundAreaHelpStep(
      id: 2,
      title: "Second corner",
      detail: "Move clockwise around the object and capture the next ground corner.",
      color: .blue),
    GroundAreaHelpStep(
      id: 3,
      title: "Third corner",
      detail: "Continue clockwise. Keep every point on the same table or floor plane.",
      color: .indigo),
    GroundAreaHelpStep(
      id: 4,
      title: "Final corner",
      detail: "Close the 2D footprint around the object. 3D scanning starts immediately.",
      color: .purple),
  ]

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text(
            "The four points define only the ground area. ARKit then scans upward inside that footprint, removes the table/floor, and selects the largest connected 3D surface cluster as the object."
          )
          .font(.subheadline)
          .foregroundStyle(.secondary)

          ForEach(steps) { step in
            HStack(alignment: .top, spacing: 12) {
              Text("\(step.id)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(step.color, in: Circle())

              VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                  .font(.headline)
                Text(step.detail)
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }
            }
          }

          Label(
            "After corner 4, move around all sides. The blue shape is the selected ground area, the teal mesh is the detected object, and the green box is its live measured extent.",
            systemImage: "sparkles"
          )
          .font(.subheadline)
          .padding(12)
          .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

          Label(
            "Only one object should sit inside the selected area. Nearby objects or a footprint that is too large can be merged into the scan.",
            systemImage: "exclamationmark.triangle"
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
        .padding()
      }
      .navigationTitle("Four-Point Ground Area")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}

struct ResultSummaryView: View {
  let results: [ToleranceResult]

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      ForEach(results) { result in
        HStack(spacing: 7) {
          Circle()
            .fill(result.status == .pass ? Color.green : Color.red)
            .frame(width: 7, height: 7)
          Text(result.name)
            .font(.caption)
          Spacer()
          if let measured = result.measuredMM {
            Text("\(measured, format: .number.precision(.fractionLength(2))) mm")
              .font(.caption.monospacedDigit())
          } else {
            Text("missing")
              .font(.caption)
          }
          Text(result.status.rawValue)
            .font(.caption2.bold())
            .foregroundStyle(result.status == .pass ? .green : .red)
        }
      }
    }
    .padding(9)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
  }
}
