import SwiftUI

struct ScanSettingsView: View {
  @EnvironmentObject private var model: ScannerViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("Six-face bounding box") {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("Extra capture margin")
              Spacer()
              Text("\(model.boundingBoxMarginMM, format: .number.precision(.fractionLength(1))) mm")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Slider(value: $model.boundingBoxMarginMM, in: 0...15, step: 0.5)
          }

          Text(
            "The blue box uses the exact six captured faces. This small hidden margin helps retain edge triangles when a point is slightly inside the real surface."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }

        Section("Surface visualization") {
          Toggle("Show captured object surface", isOn: $model.showCapturedSurface)
          Toggle("Show blue bounding box", isOn: $model.showBoundingBox)
          Toggle("Show full-room debug mesh", isOn: $model.showMeshOverlay)

          Text(
            "The teal overlay is the filtered LiDAR surface inside your box. The full-room mesh is only a diagnostic view and is off by default."
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
            "These values are used only with Manual Crop Center. A completed six-face box overrides them."
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
