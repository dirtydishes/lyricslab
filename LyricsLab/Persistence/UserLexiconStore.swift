import Foundation
import SwiftData

enum UserLexiconStore {
    static func normalizedKey(forWord word: String) -> String {
        // Keep this aligned with CMU dictionary normalization.
        CMUDictionary.normalizeWord(word)
    }

    @MainActor
    static func recordAcceptedWord(_ word: String, in modelContext: ModelContext) {
        let normalized = normalizedKey(forWord: word)
        guard !normalized.isEmpty else { return }

        let preferredCasing: String? = {
            // Keep a casing preference only if the user explicitly used uppercase.
            if word != word.lowercased() {
                return word
            }
            return nil
        }()

        let fetch = FetchDescriptor<UserLexiconEntry>(predicate: #Predicate { $0.normalized == normalized })

        let existing = (try? modelContext.fetch(fetch)) ?? []
        let entry: UserLexiconEntry
        if let first = existing.first {
            entry = first
        } else {
            entry = UserLexiconEntry(normalized: normalized)
            modelContext.insert(entry)
        }

        entry.acceptCount += 1
        entry.lastAcceptedAt = Date()
        if let preferredCasing {
            entry.preferredCasing = preferredCasing
        }
        entry.touch()
    }

    @MainActor
    static func fetchTopUserLexiconItems(in modelContext: ModelContext, limit: Int = 512) -> [UserLexiconItem] {
        var descriptor = FetchDescriptor<UserLexiconEntry>(sortBy: [
            SortDescriptor(\UserLexiconEntry.acceptCount, order: .reverse),
            SortDescriptor(\UserLexiconEntry.lastAcceptedAt, order: .reverse),
            SortDescriptor(\UserLexiconEntry.updatedAt, order: .reverse),
        ])
        descriptor.fetchLimit = limit

        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.map {
            UserLexiconItem(
                normalized: $0.normalized,
                display: $0.preferredCasing ?? $0.normalized,
                acceptCount: $0.acceptCount,
                lastAcceptedAt: $0.lastAcceptedAt
            )
        }
    }
}
