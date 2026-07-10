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
            Slider(value: $model.footprintMarginMM, in: 0...12, step: 0.5)
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
            "The four points define a 2D polygon on the support surface. The app scans upward only to the maximum height. Keep that value just above the expected part height."
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
            Slider(value: $model.objectMergeDistanceMM, in: 6...40, step: 1)
          }

          Text(
            "The scanner removes floor/table triangles, builds connected surface clusters, selects the strongest object cluster, and merges nearby pieces within this distance. Reduce it when two separate objects are being joined."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }

        Section("Surface visualization") {
          Toggle("Show detected object surface", isOn: $model.showCapturedSurface)
          Toggle("Show ground area and object bounds", isOn: $model.showBoundingBox)
          Toggle("Show full-room debug mesh", isOn: $model.showMeshOverlay)

          Text(
            "The teal overlay is the automatically isolated object surface. The blue outline is the selected ground area. The green wireframe is the detected object's live dimensional extent."
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
