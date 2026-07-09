import SwiftUI

struct ToleranceEditorView: View {
    @EnvironmentObject private var model: ScannerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Measured dimensions") {
                    Text("The app currently tolerance-checks the cropped STL bounding box: bbox_x_mm, bbox_y_mm, and bbox_z_mm.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach($model.specs) { $spec in
                    Section(spec.name) {
                        Toggle("Enabled", isOn: $spec.enabled)
                        TextField("Nominal mm", value: $spec.nominalMM, format: .number.precision(.fractionLength(3)))
                            .keyboardType(.decimalPad)
                        TextField("Lower tolerance mm", value: $spec.lowerToleranceMM, format: .number.precision(.fractionLength(3)))
                            .keyboardType(.numbersAndPunctuation)
                        TextField("Upper tolerance mm", value: $spec.upperToleranceMM, format: .number.precision(.fractionLength(3)))
                            .keyboardType(.numbersAndPunctuation)
                    }
                }

                Section {
                    Button("Restore default 70 × 110 × 50 mm example") {
                        model.applyDefaultBoxSpecs()
                    }
                }
            }
            .navigationTitle("Tolerances")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
