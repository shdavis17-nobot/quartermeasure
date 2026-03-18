import SwiftUI
import Combine

/// Manages the user's color scheme preference, persisted via AppStorage.
class AppearanceManager: ObservableObject {
    enum ColorSchemePreference: String, CaseIterable, Identifiable {
        case automatic, light, dark
        var id: String { rawValue }
        var label: String {
            switch self {
            case .automatic: return "Automatic"
            case .light:     return "Light"
            case .dark:      return "Dark"
            }
        }
    }

    @AppStorage("colorSchemePreference") var preference: ColorSchemePreference = .automatic

    /// Returns the SwiftUI ColorScheme to apply, or nil for system default.
    var preferredScheme: ColorScheme? {
        switch preference {
        case .automatic: return nil
        case .light:     return .light
        case .dark:      return .dark
        }
    }
}
