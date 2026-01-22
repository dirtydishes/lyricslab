import Foundation
import SwiftData

@Model
final class Composition: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var lyrics: String
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?

    // A lightweight, denormalized field to make Home search fast.
    // Updated whenever title/lyrics change.
    var searchBlob: String

    init(
        id: UUID = UUID(),
        title: String = "",
        lyrics: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastOpenedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.lyrics = lyrics
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
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
