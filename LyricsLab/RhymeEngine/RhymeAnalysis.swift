import Foundation

struct RhymeToken: Equatable {
    var range: NSRange
    var rhymeKey: String
}

struct RhymeGroup: Equatable, Identifiable {
    var id: String { rhymeKey }
    var rhymeKey: String
    var tokens: [RhymeToken]
}

struct RhymeAnalysis: Equatable {
    var groups: [RhymeGroup]

    nonisolated static let empty = RhymeAnalysis(groups: [])
}
