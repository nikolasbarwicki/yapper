import os

/// Centralized loggers for the app.
/// Use appropriate log levels:
/// - `.debug` for detailed debugging info
/// - `.info` for normal operations
/// - `.warning` for recoverable issues
/// - `.error` for failures
enum AppLogger {
    static let app = Logger(subsystem: "com.yapper", category: "App")
    static let audio = Logger(subsystem: "com.yapper", category: "Audio")
    static let transcription = Logger(subsystem: "com.yapper", category: "Transcription")
    static let llm = Logger(subsystem: "com.yapper", category: "LLM")
    static let history = Logger(subsystem: "com.yapper", category: "History")
    static let hotkeys = Logger(subsystem: "com.yapper", category: "Hotkeys")
}
