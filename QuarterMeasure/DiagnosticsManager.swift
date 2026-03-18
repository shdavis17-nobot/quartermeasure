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

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            // Log locally for debugging — never transmitted externally
            print("[MetricKit] Received metric payload: \(payload.timeStampBegin) – \(payload.timeStampEnd)")
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            print("[MetricKit] Received diagnostic payload: \(payload.timeStampBegin) – \(payload.timeStampEnd)")
        }
    }
}
