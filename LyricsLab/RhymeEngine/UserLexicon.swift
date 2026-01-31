import Foundation

// A persistence-agnostic snapshot of a user's lexicon entry.
// This keeps RhymeEngine logic decoupled from SwiftData.
nonisolated struct UserLexiconItem: Equatable, Sendable {
    var normalized: String
    var display: String
    var acceptCount: Int
    var lastAcceptedAt: Date?
}
