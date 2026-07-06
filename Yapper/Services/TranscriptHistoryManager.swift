import Foundation
import Observation

// MARK: - Transcript History Manager

/// Manages persistence and retrieval of transcript history.
/// Stores transcripts as JSON in the Application Support directory.
@MainActor
@Observable
final class TranscriptHistoryManager {

    // MARK: - Singleton

    static let shared = TranscriptHistoryManager()

    // MARK: - Properties

    /// The loaded transcript history
    private(set) var history: TranscriptHistory

    /// File URL for persistent storage
    private let storageURL: URL

    // MARK: - Initialization

    private init() {
        // Setup storage path: ~/Library/Application Support/Yapper/transcript_history.json
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("❌ Failed to locate Application Support directory, using temp directory")
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Yapper", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            self.storageURL = tempDir.appendingPathComponent("transcript_history.json")
            self.history = TranscriptHistory()
            loadHistory()
            return
        }

        let yapperDir = appSupport.appendingPathComponent("Yapper", isDirectory: true)

        // Create directory if needed
        do {
            try FileManager.default.createDirectory(at: yapperDir, withIntermediateDirectories: true)
        } catch {
            print("⚠️ Failed to create Yapper directory: \(error)")
        }

        self.storageURL = yapperDir.appendingPathComponent("transcript_history.json")
        self.history = TranscriptHistory()

        // Load existing history
        loadHistory()
    }

    // MARK: - Public API

    /// Add a new transcript record
    func addRecord(_ record: TranscriptRecord) {
        history.records.insert(record, at: 0)  // Most recent first
        saveHistory()
    }

    /// Delete a transcript by ID
    func deleteRecord(id: UUID) {
        history.records.removeAll { $0.id == id }
        saveHistory()
    }

    /// Delete multiple transcripts by IDs
    func deleteRecords(ids: Set<UUID>) {
        history.records.removeAll { ids.contains($0.id) }
        saveHistory()
    }

    /// Clear all transcript history
    func clearAllHistory() {
        history.records.removeAll()
        history.lastCleanup = Date()
        saveHistory()
    }

    /// Get all records (most recent first)
    var allRecords: [TranscriptRecord] {
        history.records
    }

    /// Get record count
    var recordCount: Int {
        history.records.count
    }

    /// Search records by text content
    func search(query: String) -> [TranscriptRecord] {
        guard !query.isEmpty else { return history.records }

        let lowercasedQuery = query.lowercased()
        return history.records.filter { record in
            record.text.lowercased().contains(lowercasedQuery)
        }
    }

    /// Clean up old records based on retention days
    func cleanupOldRecords(retentionDays: Int) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()

        let originalCount = history.records.count
        history.records.removeAll { $0.timestamp < cutoffDate }
        history.lastCleanup = Date()

        let removedCount = originalCount - history.records.count
        if removedCount > 0 {
            print("🧹 Cleaned up \(removedCount) old transcript(s)")
        }
        // Always save to persist lastCleanup timestamp
        saveHistory()
    }

    /// Get records within a date range
    func records(from startDate: Date, to endDate: Date) -> [TranscriptRecord] {
        history.records.filter { record in
            record.timestamp >= startDate && record.timestamp <= endDate
        }
    }

    /// Get records for today
    var todayRecords: [TranscriptRecord] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        return history.records.filter { $0.timestamp >= startOfDay }
    }

    // MARK: - Persistence

    private func loadHistory() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            print("📂 No existing transcript history found")
            return
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            history = try decoder.decode(TranscriptHistory.self, from: data)
            print("📂 Loaded \(history.records.count) transcript(s) from history")
        } catch {
            print("❌ Failed to load transcript history: \(error)")
            // Start fresh if corrupted
            history = TranscriptHistory()
        }
    }

    private func saveHistory() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(history)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("❌ Failed to save transcript history: \(error)")
        }
    }

    // MARK: - Statistics

    /// Total duration of all transcripts
    var totalDuration: TimeInterval {
        history.records.reduce(0) { $0 + $1.duration }
    }

    /// Total character count across all transcripts
    var totalCharacters: Int {
        history.records.reduce(0) { $0 + $1.characterCount }
    }

    /// Formatted total duration (e.g., "12h 34m")
    var formattedTotalDuration: String {
        DurationFormatter.formatLong(totalDuration)
    }

    // MARK: - Time Saved Calculations

    /// Average typing speed: ~40 WPM with ~5 chars/word = 200 chars/min = 3.33 chars/sec
    /// This is the baseline we compare against - what users would spend typing manually
    private static let averageTypingCharsPerSecond: Double = 3.33

    /// Average speaking speed: ~150 WPM with ~5 chars/word = 750 chars/min = 12.5 chars/sec
    /// Speaking is ~3.75x faster than typing
    private static let averageSpeakingCharsPerSecond: Double = 12.5

    /// Estimated time (in seconds) it would take to type all transcribed text manually
    var estimatedTypingTime: TimeInterval {
        Double(totalCharacters) / Self.averageTypingCharsPerSecond
    }

    /// Estimated speaking time based on character count (more accurate than recording duration
    /// since recording may include pauses, thinking time, etc.)
    var estimatedSpeakingTime: TimeInterval {
        Double(totalCharacters) / Self.averageSpeakingCharsPerSecond
    }

    /// Time saved by using voice transcription instead of typing
    /// Compares estimated typing time vs estimated speaking time (based on content length)
    /// This gives users a more optimistic and accurate view of their time savings
    var timeSaved: TimeInterval {
        max(0, estimatedTypingTime - estimatedSpeakingTime)
    }

    /// Formatted time saved (e.g., "2h 15m saved")
    var formattedTimeSaved: String {
        let totalSeconds = Int(timeSaved)

        if totalSeconds < 60 {
            return "\(totalSeconds)s saved"
        }

        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m saved"
        } else {
            return "\(minutes)m saved"
        }
    }
}
