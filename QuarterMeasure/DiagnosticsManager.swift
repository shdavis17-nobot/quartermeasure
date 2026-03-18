import Foundation
import MetricKit

/// Subscribes to MetricKit payloads for anonymous, on-device diagnostics.
/// No data is sent to any server. Payloads are logged locally only.
class DiagnosticsManager: NSObject, MXMetricManagerSubscriber {
    static let shared = DiagnosticsManager()

    private override init() {
        super.init()
        MXMetricManager.shared.add(self)
    }

    deinit {
        MXMetricManager.shared.remove(self)
    }

    // MARK: - MXMetricManagerSubscriber
    // nonisolated required: MXMetricManagerSubscriber callbacks are dispatched on a
    // background queue; marking nonisolated avoids the Swift 6 main-actor warning.

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            // Log locally only — never transmitted externally
            print("[MetricKit] Received metric payload: \(payload.timeStampBegin) – \(payload.timeStampEnd)")
        }
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            print("[MetricKit] Received diagnostic payload: \(payload.timeStampBegin) – \(payload.timeStampEnd)")
        }
    }
}
