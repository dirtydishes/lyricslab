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
        lexiconState: CompositionLexiconState? = nil
    ) {
        self.id = id
        self.title = title
        self.lyrics = lyrics
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
        self.lexiconState = lexiconState
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
