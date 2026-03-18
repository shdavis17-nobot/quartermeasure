import SwiftUI

@main
struct QuarterMeasureApp: App {
    @StateObject private var storeManager = StoreManager()
    @StateObject private var appearanceManager = AppearanceManager()

    // Boot MetricKit subscriber at app launch
    private let diagnostics = DiagnosticsManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(storeManager)
                .environmentObject(appearanceManager)
                .preferredColorScheme(appearanceManager.preferredScheme)
        }
    }
}
