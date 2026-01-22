import Foundation

nonisolated struct RhymeOccurrence: Equatable, Sendable {
    var range: NSRange
    var rhymeKey: String
    var lineIndex: Int
    var isLineFinalToken: Bool
}

nonisolated enum RhymeGroupType: String, Codable, Sendable {
    case end
    case `internal`
    case near
}

nonisolated struct RhymeGroup: Equatable, Identifiable, Sendable {
    var id: String { "\(type.rawValue):\(rhymeKey):\(colorIndex)" }
    var type: RhymeGroupType
    // For end rhyme groups, this is the exact rhyme key.
    // For near rhyme groups, this is a representative key for the cluster.
    var rhymeKey: String
    // Stable palette index for rendering.
    var colorIndex: Int
    var occurrences: [RhymeOccurrence]
}

nonisolated struct RhymeAnalysis: Equatable, Sendable {
    var groups: [RhymeGroup]

    nonisolated static let empty = RhymeAnalysis(groups: [])
}
