import Foundation
import SwiftData

@Model
final class UserLexiconEntry {
    // NOTE: Avoid unique constraints; CloudKit-backed SwiftData sync can be strict.
    // CloudKit-backed SwiftData requires either optional attributes or default values.
    var id: UUID = UUID()

    // Normalized for lookup and de-dupe in app logic.
    var normalized: String = ""

    // Optional display preference (e.g. "LA").
    var preferredCasing: String?

    // Personalization signals.
    var acceptCount: Int = 0
    var lastAcceptedAt: Date?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        normalized: String,
        preferredCasing: String? = nil,
        acceptCount: Int = 0,
        lastAcceptedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.normalized = normalized
        self.preferredCasing = preferredCasing
        self.acceptCount = acceptCount
        self.lastAcceptedAt = lastAcceptedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func touch() {
        updatedAt = Date()
    }
}
