import Foundation

nonisolated enum CMUDictionaryStore {
    nonisolated private static let filename = "cmudict.index.plist"

    nonisolated static func loadCachedIndex() -> CMUDictionaryIndex? {
        guard let url = cacheURL else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListDecoder().decode(CMUDictionaryIndex.self, from: data)
    }

    nonisolated static func saveCachedIndex(_ index: CMUDictionaryIndex) {
        guard let url = cacheURL else { return }
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(index)

            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: Data.WritingOptions.atomic)
        } catch {
            // Cache is best-effort; ignore failures.
        }
    }

    nonisolated private static var cacheURL: URL? {
        let fm = FileManager.default

        // applicationSupportDirectory is sandbox-safe on iOS.
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        // Keep a stable subfolder even if bundle id changes in dev builds.
        let dir = base.appendingPathComponent("LyricsLab", isDirectory: true)
        return dir.appendingPathComponent(filename, isDirectory: false)
    }
}
