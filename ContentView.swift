import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: ScannerViewModel
    @State private var showSettings = false
    @State private var showTolerances = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ARScannerView()
                .ignoresSafeArea()

            VStack(spacing: 12) {
                statusPanel
                Spacer()
                controlsPanel
            }
            .padding()
        }
        .sheet(isPresented: $showSettings) {
            ScanSettingsView()
                .environmentObject(model)
        }
        .sheet(isPresented: $showTolerances) {
            ToleranceEditorView()
                .environmentObject(model)
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.status)
                .font(.headline)
            Text(model.trackingSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.lastTriangleCount > 0 {
                Text("Last STL: \(model.lastTriangleCount) triangles, \(model.lastVertexCount) vertices")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var controlsPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    model.setObjectCenter()
                } label: {
                    Label("Set Center", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    model.toggleScan()
                } label: {
                    Label(model.isScanning ? "Stop" : "Scan", systemImage: model.isScanning ? "stop.circle" : "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 10) {
                Button {
                    model.exportCurrentScan()
                } label: {
                    Label("Export STL", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    showSettings = true
                } label: {
                    Label("Setup", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    showTolerances = true
                } label: {
                    Label("Tolerances", systemImage: "checklist")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if !model.toleranceResults.isEmpty {
                ResultSummaryView(results: model.toleranceResults)
            }

            HStack(spacing: 10) {
                if let stlURL = model.lastSTLURL {
                    ShareLink(item: stlURL) {
                        Label("Share STL", systemImage: "shippingbox")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let reportURL = model.lastReportURL {
                    ShareLink(item: reportURL) {
                        Label("Share CSV", systemImage: "tablecells")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Button(role: .destructive) {
                model.resetScan()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct ResultSummaryView: View {
    let results: [ToleranceResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(results) { result in
                HStack {
                    Text(result.name)
                        .font(.caption)
                    Spacer()
                    if let measured = result.measuredMM {
                        Text(measured, format: .number.precision(.fractionLength(2)))
                            .font(.caption.monospacedDigit())
                        Text("mm")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("missing")
                            .font(.caption)
                    }
                    Text(result.status.rawValue)
                        .font(.caption.bold())
                        .foregroundStyle(result.status == .pass ? .green : .red)
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
