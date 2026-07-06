import Foundation

// MARK: - Model Storage Manager

/// Manages on-disk storage for downloaded speech models (Whisper + Parakeet).
/// Stateless utility — all methods are static.
enum ModelStorageManager {

    /// All model directories under Application Support.
    /// Includes both the WhisperKit Hub cache and FluidAudio's Parakeet model directories.
    private static var modelDirectories: [URL] {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let yapperDir = appSupport.appendingPathComponent("Yapper", isDirectory: true)

        var dirs = [
            yapperDir.appendingPathComponent("models", isDirectory: true),
        ]

        // FluidAudio stores Parakeet models as sibling directories named "parakeet-tdt-*"
        if let contents = try? fm.contentsOfDirectory(
            at: yapperDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            for url in contents {
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir && url.lastPathComponent.hasPrefix("parakeet-") {
                    dirs.append(url)
                }
            }
        }

        return dirs
    }

    /// Total bytes consumed by all downloaded models.
    static func totalDiskUsage() -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0

        for dir in modelDirectories {
            guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
                continue
            }
            for case let fileURL as URL in enumerator {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
        }

        return total
    }

    /// Remove downloaded files for a specific model.
    /// Used to clean up partial downloads after cancellation.
    static func removeModelFiles(for modelId: String) {
        guard let id = ModelIdentifier(persistedValue: modelId) else { return }
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

        switch id.engine {
        case .whisper:
            let folderName = ModelIdentifier.whisperKitModelName(for: id.variant)
            let hubCacheDir = appSupport
                .appendingPathComponent("Yapper/models/models/\(ModelIdentifier.whisperKitHubRepo)", isDirectory: true)
                .appendingPathComponent(folderName, isDirectory: true)
            try? fm.removeItem(at: hubCacheDir)

        case .parakeet:
            let modelsDir = appSupport.appendingPathComponent("Yapper/parakeet-models", isDirectory: true)
            try? fm.removeItem(at: modelsDir)
        }
    }

    /// Remove all downloaded models from disk and re-create the empty directories.
    static func clearAllModels() throws {
        let fm = FileManager.default

        for dir in modelDirectories {
            if fm.fileExists(atPath: dir.path) {
                try fm.removeItem(at: dir)
            }
        }

        // Re-create the whisper models directory (needed on next download)
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = appSupport.appendingPathComponent("Yapper/models", isDirectory: true)
        try fm.createDirectory(at: modelsDir, withIntermediateDirectories: true)
    }
}
