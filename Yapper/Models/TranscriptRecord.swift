import Foundation

// MARK: - Transcript Source Type

/// Indicates the source of a transcript
enum TranscriptSourceType: String, Codable {
    case live   // From live microphone recording
    case file   // From transcribing an audio file
}

// MARK: - Transcript Record

/// A single transcript record with metadata.
/// Stored in the transcript history for later reference.
struct TranscriptRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let timestamp: Date
    let duration: TimeInterval  // Recording duration in seconds
    let language: String        // Language code used for transcription

    // Source information (for file transcriptions)
    let sourceType: TranscriptSourceType
    let sourceFileName: String?
    let sourceFilePath: String?
    let sourceFileSize: Int64?

    // MARK: - Static Formatters (cached for performance)

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let timeOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Computed Properties

    /// Character count
    var characterCount: Int {
        text.count
    }

    /// Formatted duration string (e.g., "1:23" or "0:05")
    var formattedDuration: String {
        DurationFormatter.format(duration)
    }

    /// Formatted timestamp for display (e.g., "Jan 15, 2025 at 2:30 PM")
    var formattedTimestamp: String {
        Self.timestampFormatter.string(from: timestamp)
    }

    /// Short date for list display (e.g., "Jan 15")
    var shortDate: String {
        Self.shortDateFormatter.string(from: timestamp)
    }

    /// Time only for list display (e.g., "2:30 PM")
    var timeOnly: String {
        Self.timeOnlyFormatter.string(from: timestamp)
    }

    // MARK: - Formatted File Size

    /// Formatted file size for display (e.g., "1.2 MB")
    var formattedFileSize: String? {
        guard let size = sourceFileSize else { return nil }
        return FileSizeFormatter.format(size)
    }

    // MARK: - Initialization

    /// Create a new transcript record from live recording
    init(text: String, duration: TimeInterval, language: String) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.duration = duration
        self.language = language
        self.sourceType = .live
        self.sourceFileName = nil
        self.sourceFilePath = nil
        self.sourceFileSize = nil
    }

    /// Create a new transcript record from file transcription
    init(
        text: String,
        duration: TimeInterval,
        language: String,
        sourceFileName: String,
        sourceFilePath: String,
        sourceFileSize: Int64
    ) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.duration = duration
        self.language = language
        self.sourceType = .file
        self.sourceFileName = sourceFileName
        self.sourceFilePath = sourceFilePath
        self.sourceFileSize = sourceFileSize
    }

    // MARK: - Codable (backward compatibility)

    enum CodingKeys: String, CodingKey {
        case id, text, timestamp, duration, language
        case sourceType, sourceFileName, sourceFilePath, sourceFileSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        language = try container.decode(String.self, forKey: .language)

        // Backward compatibility: default to .live if sourceType is missing
        sourceType = try container.decodeIfPresent(TranscriptSourceType.self, forKey: .sourceType) ?? .live
        sourceFileName = try container.decodeIfPresent(String.self, forKey: .sourceFileName)
        sourceFilePath = try container.decodeIfPresent(String.self, forKey: .sourceFilePath)
        sourceFileSize = try container.decodeIfPresent(Int64.self, forKey: .sourceFileSize)
    }
}

// MARK: - Transcript History Container

/// Container for storing transcript history with metadata
struct TranscriptHistory: Codable {
    var records: [TranscriptRecord]
    var lastCleanup: Date?

    init(records: [TranscriptRecord] = [], lastCleanup: Date? = nil) {
        self.records = records
        self.lastCleanup = lastCleanup
    }
}
