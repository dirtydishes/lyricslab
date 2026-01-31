import Foundation

nonisolated struct BarPosition: Equatable, Sendable {
    // 0..15 for a 16-step grid.
    var step: Int
    var syllablesBeforeCaret: Int
    var totalSyllables: Int
    var lowConfidenceTokenCount: Int
}

nonisolated struct RhymeEditorAssistResult: Sendable {
    var suggestions: [String]
    var barPosition: BarPosition?
}
