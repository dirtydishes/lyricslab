import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct TextHighlight: Equatable {
    var range: NSRange

    enum Style: Equatable {
        case end
        case `internal`
        case near
    }

    var style: Style

    #if canImport(UIKit)
    var color: UIColor
    #else
    var color: Color
    #endif
}

struct TextInsertion: Equatable {
    var id: UUID
    var text: String
}

#if canImport(UIKit)
struct LyricsTextView<Accessory: View>: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var insertion: TextInsertion?
    @Binding var isFocused: Bool
    var highlights: [TextHighlight]

    var preferredColorScheme: ColorScheme? = nil
    var preferredTextColor: Color? = nil
    var preferredTintColor: Color? = nil
    @ViewBuilder var accessory: () -> Accessory

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator

        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        if let preferredColorScheme {
            textView.keyboardAppearance = preferredColorScheme == .dark ? .dark : .light
        }
        if let preferredTextColor {
            textView.textColor = UIColor(preferredTextColor)
        }
        if let preferredTintColor {
            textView.tintColor = UIColor(preferredTintColor)
        }
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = true

        context.coordinator.configureAccessory(for: textView)

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self

        if let preferredColorScheme {
            uiView.keyboardAppearance = preferredColorScheme == .dark ? .dark : .light
        }
        if let preferredTextColor {
            uiView.textColor = UIColor(preferredTextColor)
        }
        if let preferredTintColor {
            uiView.tintColor = UIColor(preferredTintColor)
        }

        if uiView.text != text {
            context.coordinator.isApplyingSwiftUIText = true
            uiView.text = text
            context.coordinator.isApplyingSwiftUIText = false
        }

        if uiView.selectedRange != selectedRange {
            uiView.selectedRange = selectedRange
        }

        if let insertion, insertion.id != context.coordinator.lastInsertionID {
            context.coordinator.lastInsertionID = insertion.id
            context.coordinator.insert(text: insertion.text, into: uiView)
            DispatchQueue.main.async {
                self.insertion = nil
            }
        }

        context.coordinator.applyHighlights(to: uiView, highlights: highlights)
        context.coordinator.updateAccessory()

        if isFocused {
            if !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            }
        } else {
            if uiView.isFirstResponder {
                uiView.resignFirstResponder()
            }
        }
    }
}

extension LyricsTextView {
    final class Coordinator: NSObject, UITextViewDelegate {
        fileprivate var parent: LyricsTextView
        fileprivate var isApplyingSwiftUIText = false
        fileprivate var lastInsertionID: UUID?

        private var accessoryHost: UIHostingController<Accessory>?
        private var accessoryContainer: UIInputView?

        init(parent: LyricsTextView) {
            self.parent = parent
        }

        func configureAccessory(for textView: UITextView) {
            let host = UIHostingController(rootView: parent.accessory())
            host.view.backgroundColor = .clear
            host.view.translatesAutoresizingMaskIntoConstraints = false

            let container = UIInputView(frame: .zero, inputViewStyle: .keyboard)
            container.allowsSelfSizing = true
            container.backgroundColor = .clear
            container.translatesAutoresizingMaskIntoConstraints = false

            container.addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: container.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])

            textView.inputAccessoryView = container
            accessoryHost = host
            accessoryContainer = container
        }

        func updateAccessory() {
            accessoryHost?.rootView = parent.accessory()
            accessoryContainer?.setNeedsLayout()
            accessoryContainer?.layoutIfNeeded()
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingSwiftUIText else { return }
            parent.text = textView.text
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.selectedRange = textView.selectedRange
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused {
                parent.isFocused = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused {
                parent.isFocused = false
            }
        }

        func insert(text: String, into textView: UITextView) {
            let range = textView.selectedRange
            let nsText = textView.text as NSString
            let newText = nsText.replacingCharacters(in: range, with: text)
            textView.text = newText

            // Per product behavior: after inserting a suggestion, move the cursor
            // to the end of the inserted word.
            let newCursor = range.location + (text as NSString).length
            textView.selectedRange = NSRange(location: newCursor, length: 0)

            parent.text = newText
            parent.selectedRange = textView.selectedRange
        }

        func applyHighlights(to textView: UITextView, highlights: [TextHighlight]) {
            let fullRange = NSRange(location: 0, length: (textView.text as NSString).length)
            guard fullRange.length > 0 else { return }

            textView.textStorage.beginEditing()
            textView.textStorage.removeAttribute(.backgroundColor, range: fullRange)
            textView.textStorage.removeAttribute(.underlineStyle, range: fullRange)
            textView.textStorage.removeAttribute(.underlineColor, range: fullRange)

            for h in highlights {
                guard NSMaxRange(h.range) <= fullRange.length else { continue }
                switch h.style {
                case .end:
                    textView.textStorage.addAttribute(.backgroundColor, value: h.color.withAlphaComponent(0.26), range: h.range)
                case .internal:
                    let style = NSUnderlineStyle.single.rawValue
                    textView.textStorage.addAttribute(.underlineStyle, value: style, range: h.range)
                    textView.textStorage.addAttribute(.underlineColor, value: h.color.withAlphaComponent(0.68), range: h.range)
                case .near:
                    let style = NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue
                    textView.textStorage.addAttribute(.underlineStyle, value: style, range: h.range)
                    textView.textStorage.addAttribute(.underlineColor, value: h.color.withAlphaComponent(0.52), range: h.range)
                }
            }
            textView.textStorage.endEditing()
        }
    }
}

#else

// macOS build fallback: keep a plain SwiftUI editor so the target still compiles.
// Highlights/accessory are ignored here.
struct LyricsTextView<Accessory: View>: View {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var insertion: TextInsertion?
    @Binding var isFocused: Bool
    var highlights: [TextHighlight]
    var preferredColorScheme: ColorScheme? = nil
    var preferredTextColor: Color? = nil
    var preferredTintColor: Color? = nil
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        TextEditor(text: $text)
            .onChange(of: text) {
                // Best-effort selection tracking isn't available without a custom NSView wrapper.
                selectedRange = NSRange(location: (text as NSString).length, length: 0)
                insertion = nil
            }
    }
}

#endif
