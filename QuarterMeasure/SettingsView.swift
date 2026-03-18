import SwiftUI
import StoreKit

struct SettingsView: View {
    @EnvironmentObject var storeManager: StoreManager
    @EnvironmentObject var appearanceManager: AppearanceManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Appearance
                Section("Appearance") {
                    Picker("Color Scheme", selection: $appearanceManager.preference) {
                        ForEach(AppearanceManager.ColorSchemePreference.allCases) { pref in
                            Text(pref.label).tag(pref)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // MARK: Pro Unlock
                Section("Pro Features") {
                    if storeManager.isProUnlocked {
                        Label("Pro Unlocked", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Measurement Labels & Export")
                                .font(.headline)
                            Text("One-time purchase of $0.99 to unlock measurement readouts and photo export.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            Task {
                                if let product = storeManager.products.first {
                                    try? await storeManager.purchase(product)
                                }
                            }
                        } label: {
                            Label("Unlock Pro – $0.99", systemImage: "lock.open.fill")
                        }
                        Button("Restore Purchases") {
                            Task { await storeManager.restore() }
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                // MARK: Privacy
                Section("Privacy") {
                    Label("No data collected or shared", systemImage: "hand.raised.fill")
                        .foregroundStyle(.secondary)
                    Label("All AI runs on-device", systemImage: "cpu")
                        .foregroundStyle(.secondary)
                }

                // MARK: About
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.shortVersionString)
                    LabeledContent("Build", value: Bundle.main.buildNumber)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private extension Bundle {
    var shortVersionString: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "—" }
    var buildNumber: String { infoDictionary?["CFBundleVersion"] as? String ?? "—" }
}
