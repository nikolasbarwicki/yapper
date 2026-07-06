import Foundation

extension Bundle {
    /// App version string from Info.plist (e.g., "1.0.0")
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}
