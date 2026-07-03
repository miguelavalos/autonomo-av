import Foundation
import OSLog

enum AutonomoAVMacTelemetry {
    private static var subsystem: String {
        Bundle.main.bundleIdentifier ?? "com.avalsys.autonomoav.mac"
    }

    static let app = Logger(subsystem: subsystem, category: "App")
    static let intake = Logger(subsystem: subsystem, category: "Intake")
    static let services = Logger(subsystem: subsystem, category: "Services")
}
