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
      BoundingBoxHelpView()
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
              if let summary = model.sixPointSummary {
                Text("•")
                Text(summary.compactDescription)
              }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
          }
        }

        Image(systemName: statusExpanded ? "chevron.up" : "chevron.down")
          .font(.caption2.weight(.bold))
          .foregroundStyle(.secondary)
          .padding(.top, 3)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(maxWidth: 305, alignment: .leading)
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
          Label("Captured object surface", systemImage: "square.3.layers.3d")
        }
        Toggle(isOn: $model.showBoundingBox) {
          Label("Bounding box", systemImage: "cube.transparent")
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
          Label("How the six points work", systemImage: "questionmark.circle")
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
          Label("Clear bounding box", systemImage: "trash")
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
    case .definingBox:
      definingBoxControls
    case .readyToScan:
      readyToScanControls
    case .scanning:
      scanningControls
    case .review:
      reviewControls
    case .exported:
      exportedControls
    }
  }

  private var definingBoxControls: some View {
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
              .frame(width: 72, height: 72)
              .shadow(color: .black.opacity(0.24), radius: 8, y: 3)
            Circle()
              .stroke(.black.opacity(0.2), lineWidth: 1)
              .frame(width: 62, height: 62)
            Image(systemName: "plus")
              .font(.system(size: 30, weight: .medium))
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
        Label("Bounding box ready", systemImage: "checkmark.seal.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.green)
        if let summary = model.sixPointSummary {
          Text(summary.compactDescription)
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
      .accessibilityLabel("Edit bounding box")

      Button {
        model.startSurfaceScan()
      } label: {
        Label("Scan Surface", systemImage: "viewfinder")
          .fontWeight(.semibold)
      }
      .buttonStyle(.borderedProminent)
    }
    .padding(12)
    .frame(maxWidth: 430)
    .background(.ultraThinMaterial, in: Capsule())
  }

  private var scanningControls: some View {
    HStack(spacing: 13) {
      SurfaceScanProgressRing(progress: model.scanCoveragePercent / 100)
        .frame(width: 48, height: 48)

      VStack(alignment: .leading, spacing: 2) {
        Text("Move around every side")
          .font(.subheadline.weight(.semibold))
        Text(
          "\(Int(model.scanCoveragePercent.rounded()))% view coverage • \(model.capturedSurfaceTriangleCount.formatted()) triangles"
        )
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
      }

      Spacer(minLength: 4)

      Button {
        model.stopSurfaceScan()
      } label: {
        Label("Stop", systemImage: "stop.fill")
          .fontWeight(.semibold)
      }
      .buttonStyle(.borderedProminent)
      .tint(.red)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .frame(maxWidth: 470)
    .background(.ultraThinMaterial, in: Capsule())
  }

  private var reviewControls: some View {
    VStack(spacing: 9) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Surface preview")
            .font(.subheadline.weight(.semibold))
          Text(
            "\(model.capturedSurfaceTriangleCount.formatted()) captured triangles • \(Int(model.scanCoveragePercent.rounded()))% coverage"
          )
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
        }
        Spacer()
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
          model.exportCurrentScan()
        } label: {
          Label("Export STL", systemImage: "square.and.arrow.up")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.capturedSurfaceTriangleCount == 0)
      }
    }
    .padding(12)
    .frame(maxWidth: 430)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  private var exportedControls: some View {
    VStack(spacing: 9) {
      HStack {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
        VStack(alignment: .leading, spacing: 2) {
          Text("Export complete")
            .font(.subheadline.weight(.semibold))
          Text("\(model.lastTriangleCount.formatted()) STL triangles")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }

      if !model.toleranceResults.isEmpty {
        ResultSummaryView(results: model.toleranceResults)
      }

      HStack(spacing: 9) {
        if let stlURL = model.lastSTLURL {
          ShareLink(item: stlURL) {
            Label("STL", systemImage: "cube")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
        }

        if let reportURL = model.lastReportURL {
          ShareLink(item: reportURL) {
            Label("CSV", systemImage: "tablecells")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
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
    .frame(maxWidth: 430)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  private var statusIcon: String {
    switch model.workflowPhase {
    case .definingBox: return "plus.viewfinder"
    case .readyToScan: return "cube.transparent"
    case .scanning: return "wave.3.right.circle.fill"
    case .review: return "eye.circle.fill"
    case .exported: return "checkmark.circle.fill"
    }
  }

  private var statusColor: Color {
    switch model.workflowPhase {
    case .definingBox: return model.reticleHasSurface ? .cyan : .orange
    case .readyToScan: return .green
    case .scanning: return .cyan
    case .review: return .blue
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
          .frame(width: 18, height: 2)
        Rectangle()
          .fill(tint)
          .frame(width: 2, height: 18)
        Circle()
          .fill(tint)
          .frame(width: 6, height: 6)
      }
      .shadow(color: .black.opacity(0.45), radius: 2)

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
    HStack(spacing: 7) {
      ForEach(0..<6, id: \.self) { index in
        Circle()
          .fill(dotColor(index))
          .frame(width: index == capturedCount ? 10 : 8, height: index == capturedCount ? 10 : 8)
          .overlay {
            Circle()
              .stroke(.white.opacity(index < capturedCount ? 0.7 : 0.3), lineWidth: 1)
          }
      }
    }
    .accessibilityLabel("\(capturedCount) of 6 bounding box points captured")
  }

  private func dotColor(_ index: Int) -> Color {
    guard index < capturedCount else {
      return index == capturedCount ? .white.opacity(0.75) : .secondary.opacity(0.35)
    }
    switch index {
    case 0: return .blue
    case 1: return .orange
    case 2, 3: return .purple
    default: return .green
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
    .foregroundStyle(enabled ? .primary : .secondary.opacity(0.5))
    .disabled(!enabled)
  }
}

private struct BoundingBoxHelpStep: Identifiable {
  let id: Int
  let title: String
  let detail: String
  let color: Color
}

private struct BoundingBoxHelpView: View {
  @Environment(\.dismiss) private var dismiss

  private let steps = [
    BoundingBoxHelpStep(
      id: 1, title: "Bottom face",
      detail:
        "Aim near the center of the lowest face or the support plane at the bottom of the part.",
      color: .blue),
    BoundingBoxHelpStep(
      id: 2, title: "Top face",
      detail: "Aim at the highest opposite face. This pair defines height and the local up axis.",
      color: .orange),
    BoundingBoxHelpStep(
      id: 3, title: "Left face", detail: "Aim at the left-most side of the object.", color: .purple),
    BoundingBoxHelpStep(
      id: 4, title: "Right face",
      detail: "Aim at the opposite right side. This pair defines width.", color: .purple),
    BoundingBoxHelpStep(
      id: 5, title: "Front face", detail: "Aim at the face nearest the chosen front of the part.",
      color: .green),
    BoundingBoxHelpStep(
      id: 6, title: "Back face", detail: "Aim at the opposite rear face. This pair defines depth.",
      color: .green),
  ]

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text(
            "The six points are the centers of six opposite faces—not six arbitrary corners. The app builds an oriented 3D box from the three face pairs."
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
            "After the blue box appears, tap Scan Surface and move around the part. Teal geometry is the LiDAR surface selected for STL export.",
            systemImage: "sparkles"
          )
          .font(.subheadline)
          .padding(12)
          .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }
        .padding()
      }
      .navigationTitle("Six-Face Bounding Box")
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
