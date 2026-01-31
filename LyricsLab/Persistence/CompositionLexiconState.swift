import Foundation
import SwiftData

@Model
final class CompositionLexiconState {
    // CloudKit-backed SwiftData requires either optional attributes or default values.
    var id: UUID = UUID()

    // Newline-separated list of pinned display words.
    // (Kept as a single String to avoid SwiftData array/transformable gotchas.)
    var pinnedWordsBlob: String = ""

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(inverse: \Composition.lexiconState)
    var composition: Composition?

    init(
        id: UUID = UUID(),
        pinnedWordsBlob: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        composition: Composition? = nil
    ) {
        self.id = id
        self.pinnedWordsBlob = pinnedWordsBlob
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.composition = composition
    }

    func touch() {
        updatedAt = Date()
    }

    var pinnedWords: [String] {
        pinnedWordsBlob
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
