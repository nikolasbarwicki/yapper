import Foundation
import FluidAudio

// MARK: - Transcription Engine

/// The speech-to-text engine powering transcription.
/// Each engine wraps a different on-device ML model family.
enum TranscriptionEngine: String, CaseIterable, Codable, Sendable {
    case whisper   // OpenAI Whisper via WhisperKit
    case parakeet  // NVIDIA Parakeet via FluidAudio

    var displayName: String {
        switch self {
        case .whisper:  return "Whisper (OpenAI)"
        case .parakeet: return "Parakeet (NVIDIA)"
        }
    }
}

// MARK: - Model Identifier

/// A colon-prefixed model identifier: `"engine:variant"`.
/// Example: `"whisper:large-v3-turbo"`, `"parakeet:tdt-0.6b-v2"`.
struct ModelIdentifier: Equatable, Sendable {
    let engine: TranscriptionEngine
    let variant: String

    /// The persisted string form: `"engine:variant"`
    var persistedValue: String {
        "\(engine.rawValue):\(variant)"
    }

    /// Parse from a persisted `"engine:variant"` string.
    /// Returns nil if the format is invalid.
    init?(persistedValue: String) {
        let parts = persistedValue.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let engine = TranscriptionEngine(rawValue: String(parts[0])) else {
            return nil
        }
        self.engine = engine
        self.variant = String(parts[1])
    }

    init(engine: TranscriptionEngine, variant: String) {
        self.engine = engine
        self.variant = variant
    }

    /// Migrate a legacy (pre-multi-engine) model name to the new colon format.
    /// Legacy names like `"large-v3-turbo"` become `"whisper:large-v3-turbo"`.
    /// Already-migrated names are returned unchanged.
    static func migrateLegacy(_ raw: String) -> String {
        // Already has engine prefix
        if raw.contains(":") { return raw }
        // Legacy names are all Whisper variants
        return "whisper:\(raw)"
    }

    /// HuggingFace repo ID used by WhisperKit for CoreML models.
    /// The Hub client creates a nested path: `<downloadBase>/models/<repo>/`
    static let whisperKitHubRepo = "argmaxinc/whisperkit-coreml"

    /// Map a Whisper variant name to the WhisperKit repo folder name.
    /// Example: `"large-v3-turbo"` → `"openai_whisper-large-v3_turbo"`
    static func whisperKitModelName(for variant: String) -> String {
        switch variant {
        case "large-v3-turbo":
            return "openai_whisper-large-v3_turbo"
        case "large-v3":
            return "openai_whisper-large-v3"
        case "tiny":
            return "openai_whisper-tiny"
        default:
            if variant.hasSuffix("-turbo") {
                let base = String(variant.dropLast(6))
                return "openai_whisper-\(base)_turbo"
            } else {
                return "openai_whisper-\(variant)"
            }
        }
    }
}

// MARK: - Available Models

/// Metadata for a single downloadable model variant.
struct ModelInfo: Sendable {
    let id: ModelIdentifier
    let displayName: String
    let description: String
    /// Language codes this model supports, or nil for "all languages"
    let supportedLanguages: [String]?
    /// Approximate peak memory in MB
    let memoryEstimateMB: Int

    var persistedValue: String { id.persistedValue }

    /// Whether this model only supports English transcription
    var isEnglishOnly: Bool { supportedLanguages == ["en"] }

    /// Whether this model's files are already downloaded on disk.
    var isDownloaded: Bool {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

        switch id.engine {
        case .whisper:
            let folderName = ModelIdentifier.whisperKitModelName(for: id.variant)
            // HuggingFace Hub stores models at: <downloadBase>/models/<repo>/<variant>/
            let hubCacheDir = appSupport
                .appendingPathComponent("Yapper/models/models/\(ModelIdentifier.whisperKitHubRepo)", isDirectory: true)
                .appendingPathComponent(folderName, isDirectory: true)
            guard let contents = try? fm.contentsOfDirectory(atPath: hubCacheDir.path) else { return false }
            return !contents.isEmpty

        case .parakeet:
            let modelsDir = appSupport.appendingPathComponent("Yapper/parakeet-models", isDirectory: true)
            let version: AsrModelVersion
            switch id.variant {
            case "tdt-0.6b-v2": version = .v2
            case "tdt-0.6b-v3": version = .v3
            default: return false
            }
            return AsrModels.modelsExist(at: modelsDir, version: version)
        }
    }
}

/// Static registry of all available transcription models.
enum AvailableModels {

    // MARK: - Whisper Models

    static let whisperModels: [ModelInfo] = [
        ModelInfo(
            id: ModelIdentifier(engine: .whisper, variant: "large-v3-turbo"),
            displayName: "Large v3 Turbo",
            description: "Best balance of speed and accuracy",
            supportedLanguages: nil,
            memoryEstimateMB: 1500
        ),
        ModelInfo(
            id: ModelIdentifier(engine: .whisper, variant: "large-v3"),
            displayName: "Large v3",
            description: "Highest accuracy, slower",
            supportedLanguages: nil,
            memoryEstimateMB: 3000
        ),
        ModelInfo(
            id: ModelIdentifier(engine: .whisper, variant: "small"),
            displayName: "Small",
            description: "Faster, moderate accuracy",
            supportedLanguages: nil,
            memoryEstimateMB: 500
        ),
        ModelInfo(
            id: ModelIdentifier(engine: .whisper, variant: "base"),
            displayName: "Base",
            description: "Fastest, lower accuracy",
            supportedLanguages: nil,
            memoryEstimateMB: 250
        ),
        ModelInfo(
            id: ModelIdentifier(engine: .whisper, variant: "tiny"),
            displayName: "Tiny",
            description: "Minimal memory, lowest accuracy",
            supportedLanguages: nil,
            memoryEstimateMB: 150
        ),
    ]

    // MARK: - Parakeet Models

    /// Languages supported by Parakeet TDT v3 (multilingual).
    /// 25 EU languages from https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
    static let parakeetV3Languages: [String] = [
        "bg", "hr", "cs", "da", "nl", "en", "et", "fi",
        "fr", "de", "el", "hu", "it", "lv", "lt", "mt",
        "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru",
        "uk"
    ]

    static let parakeetModels: [ModelInfo] = [
        ModelInfo(
            id: ModelIdentifier(engine: .parakeet, variant: "tdt-0.6b-v2"),
            displayName: "Parakeet TDT v2",
            description: "Fastest, English only, highest English accuracy",
            supportedLanguages: ["en"],
            memoryEstimateMB: 800
        ),
        ModelInfo(
            id: ModelIdentifier(engine: .parakeet, variant: "tdt-0.6b-v3"),
            displayName: "Parakeet TDT v3",
            description: "Fast, 25 languages, low memory",
            supportedLanguages: parakeetV3Languages,
            memoryEstimateMB: 800
        ),
    ]

    // MARK: - All Models

    static let allModels: [ModelInfo] = whisperModels + parakeetModels

    /// Look up a model by its persisted `"engine:variant"` string.
    static func find(_ persistedValue: String) -> ModelInfo? {
        allModels.first { $0.persistedValue == persistedValue }
    }

    /// Models grouped by engine, for use in Settings pickers.
    static let groupedByEngine: [(engine: TranscriptionEngine, models: [ModelInfo])] = [
        (.whisper, whisperModels),
        (.parakeet, parakeetModels),
    ]
}

// MARK: - Supported Languages

/// Centralized language metadata: code, display name, and flag emoji.
/// Single source of truth for all language pickers and display strings.
///
/// The curated list is a superset of:
/// - All 25 Parakeet v3 languages
/// - Popular Whisper-only languages (Arabic, Chinese, Hebrew, Hindi, etc.)
///
/// To add a new language, append a `LanguageEntry` here.
/// Whisper models (supportedLanguages == nil) show all entries.
/// Parakeet models filter to their `supportedLanguages` list.
enum SupportedLanguages {

    struct LanguageEntry: Sendable {
        let code: String
        let name: String
        let flag: String
    }

    /// Curated language list sorted alphabetically by name.
    /// Covers all Parakeet v3 languages + popular Whisper-only languages.
    static let all: [LanguageEntry] = [
        LanguageEntry(code: "ar", name: "Arabic", flag: "🇸🇦"),
        LanguageEntry(code: "bg", name: "Bulgarian", flag: "🇧🇬"),
        LanguageEntry(code: "zh", name: "Chinese", flag: "🇨🇳"),
        LanguageEntry(code: "hr", name: "Croatian", flag: "🇭🇷"),
        LanguageEntry(code: "cs", name: "Czech", flag: "🇨🇿"),
        LanguageEntry(code: "da", name: "Danish", flag: "🇩🇰"),
        LanguageEntry(code: "nl", name: "Dutch", flag: "🇳🇱"),
        LanguageEntry(code: "en", name: "English", flag: "🇬🇧"),
        LanguageEntry(code: "et", name: "Estonian", flag: "🇪🇪"),
        LanguageEntry(code: "fi", name: "Finnish", flag: "🇫🇮"),
        LanguageEntry(code: "fr", name: "French", flag: "🇫🇷"),
        LanguageEntry(code: "de", name: "German", flag: "🇩🇪"),
        LanguageEntry(code: "el", name: "Greek", flag: "🇬🇷"),
        LanguageEntry(code: "he", name: "Hebrew", flag: "🇮🇱"),
        LanguageEntry(code: "hi", name: "Hindi", flag: "🇮🇳"),
        LanguageEntry(code: "hu", name: "Hungarian", flag: "🇭🇺"),
        LanguageEntry(code: "id", name: "Indonesian", flag: "🇮🇩"),
        LanguageEntry(code: "it", name: "Italian", flag: "🇮🇹"),
        LanguageEntry(code: "ja", name: "Japanese", flag: "🇯🇵"),
        LanguageEntry(code: "ko", name: "Korean", flag: "🇰🇷"),
        LanguageEntry(code: "lv", name: "Latvian", flag: "🇱🇻"),
        LanguageEntry(code: "lt", name: "Lithuanian", flag: "🇱🇹"),
        LanguageEntry(code: "ms", name: "Malay", flag: "🇲🇾"),
        LanguageEntry(code: "mt", name: "Maltese", flag: "🇲🇹"),
        LanguageEntry(code: "no", name: "Norwegian", flag: "🇳🇴"),
        LanguageEntry(code: "pl", name: "Polish", flag: "🇵🇱"),
        LanguageEntry(code: "pt", name: "Portuguese", flag: "🇵🇹"),
        LanguageEntry(code: "ro", name: "Romanian", flag: "🇷🇴"),
        LanguageEntry(code: "ru", name: "Russian", flag: "🇷🇺"),
        LanguageEntry(code: "sk", name: "Slovak", flag: "🇸🇰"),
        LanguageEntry(code: "sl", name: "Slovenian", flag: "🇸🇮"),
        LanguageEntry(code: "es", name: "Spanish", flag: "🇪🇸"),
        LanguageEntry(code: "sv", name: "Swedish", flag: "🇸🇪"),
        LanguageEntry(code: "th", name: "Thai", flag: "🇹🇭"),
        LanguageEntry(code: "tr", name: "Turkish", flag: "🇹🇷"),
        LanguageEntry(code: "uk", name: "Ukrainian", flag: "🇺🇦"),
        LanguageEntry(code: "vi", name: "Vietnamese", flag: "🇻🇳"),
    ]

    /// Code → display name lookup
    static let codeToName: [String: String] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.code, $0.name) })
    }()

    /// Code → flag emoji lookup
    static let codeToFlag: [String: String] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.code, $0.flag) })
    }()

    /// Display name for a language code, falling back to uppercased code
    static func displayName(for code: String) -> String {
        codeToName[code] ?? code.uppercased()
    }

    /// Flag emoji for a language code, falling back to globe
    static func flag(for code: String) -> String {
        codeToFlag[code] ?? "🌐"
    }
}
