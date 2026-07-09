import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: ScannerViewModel
    @State private var showSettings = false
    @State private var showTolerances = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ARScannerView()
                .ignoresSafeArea()

            crosshair
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .allowsHitTesting(false)

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

    private var crosshair: some View {
        ZStack {
            Circle()
                .stroke(.white, lineWidth: 2)
                .frame(width: 48, height: 48)
            Rectangle()
                .fill(.white)
                .frame(width: 58, height: 2)
            Rectangle()
                .fill(.white)
                .frame(width: 2, height: 58)
        }
        .shadow(radius: 4)
        .opacity(0.95)
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.status)
                .font(.headline)
            Text(model.trackingSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Reference: \(model.referenceProgressText)")
                .font(.caption)
                .foregroundStyle(model.sixPointReferenceReady ? .green : .secondary)
            if let summary = model.sixPointSummary {
                Text(summary.compactDescription)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("Ground zero is STL Y=0. Captured top point defines reference_height_mm.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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
        ScrollView {
            VStack(spacing: 12) {
                referencePanel
                scanPanel
                exportPanel
            }
            .padding(14)
        }
        .frame(maxHeight: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private var referencePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("6-point object reference")
                        .font(.headline)
                    Text("Aim the reticle, then capture: ground zero, top, and 4 boundary points around the part.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.referenceProgressText)
                    .font(.caption.monospacedDigit().bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(model.sixPointReferenceReady ? .green.opacity(0.18) : .secondary.opacity(0.12), in: Capsule())
            }

            if !model.sixPointReferenceReady {
                Text("Next: \(model.nextReferencePointLabel)")
                    .font(.subheadline.bold())
            } else {
                Label("Object detection volume is locked", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
            }

            HStack(spacing: 10) {
                Button {
                    model.captureReferencePoint()
                } label: {
                    Label("Capture Point", systemImage: "plus.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canCaptureMoreReferencePoints)

                Button {
                    model.undoReferencePoint()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.referencePoints.isEmpty)

                Button(role: .destructive) {
                    model.clearReferencePoints()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.referencePoints.isEmpty)
            }

            if !model.referencePoints.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.referencePoints) { point in
                        HStack(spacing: 6) {
                            Image(systemName: point.id < 2 ? "circle.fill" : "smallcircle.filled.circle")
                                .font(.caption2)
                            Text(point.displayText)
                                .font(.caption)
                            Spacer()
                        }
                        .foregroundStyle(point.id == 0 ? .blue : point.id == 1 ? .orange : .primary)
                    }
                }
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var scanPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    model.detectObjectAndStartScan()
                } label: {
                    Label("Detect + Scan", systemImage: "viewfinder.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.sixPointReferenceReady || model.isScanning)

                Button {
                    model.toggleScan()
                } label: {
                    Label(model.isScanning ? "Stop" : "Scan", systemImage: model.isScanning ? "stop.circle" : "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.objectCenterIsSet)
            }

            HStack(spacing: 10) {
                Button {
                    model.setObjectCenter()
                } label: {
                    Label("Manual Center", systemImage: "scope")
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
        }
    }

    private var exportPanel: some View {
        VStack(spacing: 10) {
            Button {
                model.exportCurrentScan()
            } label: {
                Label("Export STL + CSV", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!model.objectCenterIsSet)

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
