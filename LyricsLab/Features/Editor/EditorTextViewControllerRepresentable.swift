import SwiftUI

#if canImport(UIKit)

struct EditorTextViewControllerRepresentable: UIViewControllerRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var isFocused: Bool
    @Binding var endRhymeTailLength: Int

    var highlights: [TextHighlight]
    var suggestions: [String]
    var isLoadingSuggestions: Bool
    var barPosition: BarPosition?
    var onSuggestionAccepted: ((String) -> Void)?

    var preferredColorScheme: ColorScheme? = nil
    var preferredTextColor: Color? = nil
    var preferredTintColor: Color? = nil

    func makeUIViewController(context: Context) -> EditorTextViewController {
        let vc = EditorTextViewController()
        vc.onTextChanged = { next in
            if text != next {
                text = next
            }
        }
        vc.onSelectionChanged = { next in
            if selectedRange != next {
                selectedRange = next
            }
        }
        vc.onFocusChanged = { focused in
            if isFocused != focused {
                isFocused = focused
            }
        }
        vc.onSuggestionAccepted = { word in
            onSuggestionAccepted?(word)
        }
        vc.onEndRhymeTailLengthChanged = { next in
            if endRhymeTailLength != next {
                endRhymeTailLength = next
            }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: EditorTextViewController, context: Context) {
        uiViewController.update(
            text: text,
            selectedRange: selectedRange,
            isFocused: isFocused,
            highlights: highlights,
            suggestions: suggestions,
            isLoadingSuggestions: isLoadingSuggestions,
            barPosition: barPosition,
            endRhymeTailLength: endRhymeTailLength,
            preferredColorScheme: preferredColorScheme,
            preferredTextColor: preferredTextColor,
            preferredTintColor: preferredTintColor
        )
    }
}

#endif
