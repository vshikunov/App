import SwiftUI

@main
struct DimensionalScannerApp: App {
    @StateObject private var model = ScannerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}
