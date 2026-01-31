import Foundation
import SwiftData

@Model
final class Composition: Identifiable {
    // NOTE: Avoid `@Attribute(.unique)` here; CloudKit-backed SwiftData sync has
    // strict requirements and unique constraints can prevent syncing.
    // CloudKit-backed SwiftData requires either optional attributes or default values.
    var id: UUID = UUID()
    var title: String = ""
    var lyrics: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastOpenedAt: Date?

    // Per-song lexicon metadata (pinned words, overrides later).
    var lexiconState: CompositionLexiconState?

    // End-rhyme target strength.
    // 1 = tail1 (last vowel nucleus), 2 = tail2 (last 2 vowel nuclei), etc.
    // Default stays conservative for compatibility.
    var endRhymeTailLength: Int = 1

    // JSON-encoded user overrides for inferred section/bracket labels.
    // Stored as a blob to keep SwiftData + CloudKit sync simple.
    var sectionOverridesBlob: String = ""

    // A lightweight, denormalized field to make Home search fast.
    // Updated whenever title/lyrics change.
    var searchBlob: String = ""

    init(
        id: UUID = UUID(),
        title: String = "",
        lyrics: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastOpenedAt: Date? = nil,
        lexiconState: CompositionLexiconState? = nil,
        endRhymeTailLength: Int = 1,
        sectionOverridesBlob: String = ""
    ) {
        self.id = id
        self.title = title
        self.lyrics = lyrics
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
        self.lexiconState = lexiconState
        self.endRhymeTailLength = endRhymeTailLength
        self.sectionOverridesBlob = sectionOverridesBlob
        self.searchBlob = Composition.makeSearchBlob(title: title, lyrics: lyrics)
    }

    func touch() {
        updatedAt = Date()
        searchBlob = Composition.makeSearchBlob(title: title, lyrics: lyrics)
    }

    static func makeSearchBlob(title: String, lyrics: String) -> String {
        (title + "\n" + lyrics).lowercased()
    }
}
