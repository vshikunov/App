import SwiftUI

struct ScanSettingsView: View {
    @EnvironmentObject private var model: ScannerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Object crop volume") {
                    numberField("X width mm", value: $model.scanVolumeXMM)
                    numberField("Y height mm", value: $model.scanVolumeYMM)
                    numberField("Z depth mm", value: $model.scanVolumeZMM)
                    Text("Keep this box tight around the part. Anything inside the box can be exported to the STL, including table surfaces.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Scale calibration") {
                    numberField("Scale correction factor", value: $model.scaleCorrectionFactor)
                    Text("Use 1.0 unless you have checked against a known reference. Example: if a 100.000 mm gauge measures 99.200 mm, enter 100 / 99.2 = 1.0081.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("AR view") {
                    Toggle("Show mesh overlay", isOn: $model.showMeshOverlay)
                }
            }
            .navigationTitle("Scan Setup")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func numberField(_ title: String, value: Binding<Double>) -> some View {
        TextField(title, value: value, format: .number.precision(.fractionLength(1)))
            .keyboardType(.decimalPad)
    }
}
