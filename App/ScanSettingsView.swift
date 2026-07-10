import SwiftUI

struct ScanSettingsView: View {
  @EnvironmentObject private var model: ScannerViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("Four-point ground area") {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("Footprint edge margin")
              Spacer()
              Text("\(model.footprintMarginMM, format: .number.precision(.fractionLength(1))) mm")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Slider(value: $model.footprintMarginMM, in: 0...6, step: 0.5)
          }

          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("Maximum object height")
              Spacer()
              Text("\(model.maximumObjectHeightMM, format: .number.precision(.fractionLength(0))) mm")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Slider(value: $model.maximumObjectHeightMM, in: 50...1500, step: 10)
          }

          Text(
            "The four points define a 2D polygon on the support surface. Edge margin is capture-only and no longer increases the measured X/Z size. Keep Maximum Object Height just above the expected part height."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }

        Section("Automatic object isolation") {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("Ground clearance")
              Spacer()
              Text("\(model.groundClearanceMM, format: .number.precision(.fractionLength(1))) mm")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Slider(value: $model.groundClearanceMM, in: 1...15, step: 0.5)
          }

          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("Minimum object height")
              Spacer()
              Text("\(model.minimumObjectHeightMM, format: .number.precision(.fractionLength(1))) mm")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Slider(value: $model.minimumObjectHeightMM, in: 3...50, step: 1)
          }

          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("Surface merge distance")
              Spacer()
              Text("\(model.objectMergeDistanceMM, format: .number.precision(.fractionLength(0))) mm")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Slider(value: $model.objectMergeDistanceMM, in: 3...15, step: 0.5)
          }

          Text(
            "The scanner removes the support plane and follows the 3D component selected by the reticle. Merge distance is deliberately conservative so unrelated fragments cannot chain into the object."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }

        Section("Tap-to-lock subject selection") {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("Object lock radius")
              Spacer()
              Text("\(model.objectLockRadiusMM, format: .number.precision(.fractionLength(0))) mm")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Slider(value: $model.objectLockRadiusMM, in: 15...250, step: 5)
          }

          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("Outlier trimming")
              Spacer()
              Text("\(model.outlierTrimPercent, format: .number.precision(.fractionLength(1)))%")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Slider(value: $model.outlierTrimPercent, in: 0.5...8, step: 0.5)
          }

          Toggle("Use coarse AR room mesh as fallback", isOn: $model.useSceneMeshFallback)

          Text(
            "After the four ground points, aim at the object and tap Select Object. The app follows the touched 3D component, trims sparse depth rays with robust percentiles, and uses a rolling median for the displayed dimensions. Leave the room-mesh fallback off for small calibration parts."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }

        Section("LiDAR depth fusion") {
          Toggle("Fuse per-frame LiDAR depth", isOn: $model.depthFusionEnabled)

          Picker("Depth sampling density", selection: $model.depthSamplingStride) {
            Text("High").tag(3)
            Text("Balanced").tag(4)
            Text("Fast").tag(6)
          }

          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("Maximum depth-triangle edge")
              Spacer()
              Text("\(model.depthMaximumEdgeMM, format: .number.precision(.fractionLength(0))) mm")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Slider(value: $model.depthMaximumEdgeMM, in: 15...70, step: 5)
          }

          Toggle("Include low-confidence depth", isOn: $model.includeLowConfidenceDepth)

          Text(
            "Depth fusion converts sceneDepth from several camera views into surface triangles inside the four-point area. Low-confidence depth is enabled by default so small objects produce geometry. Turn it off if the teal surface becomes noisy or includes nearby clutter."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }

        Section("Surface visualization") {
          Toggle("Show detected object surface", isOn: $model.showCapturedSurface)
          Toggle("Show ground area and object bounds", isOn: $model.showBoundingBox)
          Toggle("Show full-room debug mesh", isOn: $model.showMeshOverlay)

          Text(
            "The teal overlay is the selected subject surface. The blue outline is the ground area. The cyan marker is the subject lock. The green wireframe is the stabilized dimensional extent."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }

        Section("Scale calibration") {
          numberField(
            "Scale correction factor", value: $model.scaleCorrectionFactor, fractionDigits: 5)
          Text(
            "Leave at 1.0 until you validate the app with a known standard. Example: 100.000 mm known ÷ 99.200 mm measured = 1.00806."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }

        Section("Manual fallback crop") {
          numberField("X width mm", value: $model.scanVolumeXMM)
          numberField("Y height mm", value: $model.scanVolumeYMM)
          numberField("Z depth mm", value: $model.scanVolumeZMM)
          Text(
            "These values are used only with Manual Crop Center. A completed four-point ground area overrides X and Z and uses Maximum Object Height for Y."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Scan Settings")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  private func numberField(
    _ title: String,
    value: Binding<Double>,
    fractionDigits: Int = 1
  ) -> some View {
    TextField(
      title,
      value: value,
      format: .number.precision(.fractionLength(fractionDigits))
    )
    .keyboardType(.decimalPad)
  }
}
