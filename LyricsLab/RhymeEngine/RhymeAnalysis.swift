import Foundation

nonisolated struct RhymeToken: Equatable, Sendable {
    var range: NSRange
    var rhymeKey: String
}

nonisolated struct RhymeGroup: Equatable, Identifiable, Sendable {
    var id: String { rhymeKey }
    var rhymeKey: String
    var tokens: [RhymeToken]
}

nonisolated struct RhymeAnalysis: Equatable, Sendable {
    var groups: [RhymeGroup]

    nonisolated static let empty = RhymeAnalysis(groups: [])
}
