import Foundation

// MARK: - Duration Formatting

enum DurationFormatter {
    /// Format duration as "M:SS" (e.g., "1:23", "0:05")
    static func format(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Format duration as "Xh Ym" for longer durations (e.g., "2h 15m")
    static func formatLong(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - File Size Formatting

enum FileSizeFormatter {
    // nonisolated(unsafe) suppresses Swift 6 concurrency warning
    // Safe because ByteCountFormatter is only used for formatting (read-only after init)
    nonisolated(unsafe) private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    static func format(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }
}
