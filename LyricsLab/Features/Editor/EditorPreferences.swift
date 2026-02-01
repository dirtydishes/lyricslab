import Foundation

enum EditorPreferenceKeys {
    static let textAlignment = "editorTextAlignment"
    static let ruledLinesEnabled = "editorRuledLinesEnabled"
}

enum EditorTextAlignment: String, CaseIterable, Identifiable {
    case left
    case center

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left: return "Left"
        case .center: return "Center"
        }
    }
}

#if canImport(UIKit)
import UIKit

extension EditorTextAlignment {
    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        }
    }
}
#endif
