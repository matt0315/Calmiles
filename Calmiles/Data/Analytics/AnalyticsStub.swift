import Foundation
import os.log

/// Privacy-conscious analytics / crash protocol stubs — no-op beyond os_log.
enum AnalyticsStub {
    private static let logger = Logger(subsystem: "studio.botland.calmiles", category: "Analytics")

    static func log(_ event: String, _ params: [String: String] = [:]) {
        #if DEBUG
        logger.debug("event=\(event, privacy: .public) params=\(String(describing: params), privacy: .public)")
        #else
        logger.info("event=\(event, privacy: .public)")
        #endif
        // Production: wire to privacy-first provider later. No PII.
    }

    static func screen(_ name: String) {
        log("screen_view", ["screen": name])
    }
}

enum CrashProtocolStub {
    private static let logger = Logger(subsystem: "studio.botland.calmiles", category: "Crash")

    static func record(_ error: Error, file: String = #fileID, line: Int = #line) {
        logger.error("error=\(error.localizedDescription, privacy: .public) at \(file, privacy: .public):\(line, privacy: .public)")
        // Production: wire to crash reporter. No secrets / tokens.
    }

    static func breadcrumb(_ message: String) {
        logger.info("breadcrumb=\(message, privacy: .public)")
    }
}
