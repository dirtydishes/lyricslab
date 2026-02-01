#if canImport(UIKit)
import SwiftUI
import UIKit

@MainActor
final class EditorTextViewController: UIViewController {
    enum EnsureCaretReason {
        case typing
        case insertion
        case focus
        case layout
        case externalUpdate
    }

    var onTextChanged: ((String) -> Void)?
    var onSelectionChanged: ((NSRange) -> Void)?
    var onFocusChanged: ((Bool) -> Void)?
    var onSuggestionAccepted: ((String) -> Void)?
    var onEndRhymeTailLengthChanged: ((Int) -> Void)?
    var onSetSectionOverride: ((String, Int?) -> Void)?

    private(set) var textView = UITextView()

    private let sectionGutterView = EditorSectionGutterView()
    private let ruledBackgroundView = EditorRuledBackgroundView()

    private var suggestionsHostingController: UIHostingController<EditorSuggestionsBar>?

    private var textBottomToSuggestionsTop: NSLayoutConstraint?
    private var textBottomToSafeBottom: NSLayoutConstraint?
    private var suggestionsHeightZero: NSLayoutConstraint?

    private var isApplyingExternalText = false
    private var isApplyingExternalSelection = false
    private var isPerformingProgrammaticEdit = false
    private var isUserScrolling = false

    private var lastAppliedHighlights: [TextHighlight] = []

    private var lastAppliedSectionBrackets: [SectionBracket] = []

    private var lastAppliedEditorTextAlignment: EditorTextAlignment?
    private var lastAppliedRuledLinesEnabled: Bool?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        configureTextView()
        configureSuggestionsBar()
        configureLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        ensureCaretVisible(reason: .layout, animated: false)
        sectionGutterView.setNeedsDisplay()
        if ruledBackgroundView.isEnabled {
            ruledBackgroundView.setNeedsDisplay()
        }
    }

    func update(
        text: String,
        selectedRange: NSRange,
        isFocused: Bool,
        highlights: [TextHighlight],
        suggestions: [String],
        isLoadingSuggestions: Bool,
        barPosition: BarPosition?,
        endRhymeTailLength: Int,
        sectionBrackets: [SectionBracket],
        editorTextAlignment: EditorTextAlignment,
        showsRuledLines: Bool,
        preferredColorScheme: ColorScheme?,
        preferredTextColor: Color?,
        preferredTintColor: Color?
    ) {
        applyAppearance(preferredColorScheme: preferredColorScheme, preferredTextColor: preferredTextColor, preferredTintColor: preferredTintColor)
        applyTextIfNeeded(text)
        applySelectionIfNeeded(selectedRange)
        applyEditorPreferencesIfNeeded(editorTextAlignment: editorTextAlignment, showsRuledLines: showsRuledLines)
        applyHighlightsIfNeeded(highlights)
        applySectionBracketsIfNeeded(sectionBrackets)
        updateSuggestionsBar(
            suggestions: suggestions,
            isLoading: isLoadingSuggestions,
            barPosition: barPosition,
            endRhymeTailLength: endRhymeTailLength
        )
        setSuggestionsVisible(isFocused)
        setFocus(isFocused)
    }

    private func configureTextView() {
        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textAlignment = .left
        textView.textContainer.lineFragmentPadding = 0
        // Reserve a small gutter for section brackets.
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 56, bottom: 12, right: 12)
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = true

        textView.delegate = self
        textView.scrollsToTop = true

        ruledBackgroundView.textView = textView
        ruledBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        textView.insertSubview(ruledBackgroundView, at: 0)
        NSLayoutConstraint.activate([
            ruledBackgroundView.leadingAnchor.constraint(equalTo: textView.frameLayoutGuide.leadingAnchor),
            ruledBackgroundView.trailingAnchor.constraint(equalTo: textView.frameLayoutGuide.trailingAnchor),
            ruledBackgroundView.topAnchor.constraint(equalTo: textView.contentLayoutGuide.topAnchor),
            ruledBackgroundView.bottomAnchor.constraint(equalTo: textView.contentLayoutGuide.bottomAnchor),
        ])

        sectionGutterView.textView = textView
        sectionGutterView.translatesAutoresizingMaskIntoConstraints = false
        sectionGutterView.onTapBracket = { [weak self] bracket in
            self?.presentSectionOverrideSheet(for: bracket)
        }
        textView.addSubview(sectionGutterView)
        NSLayoutConstraint.activate([
            sectionGutterView.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            sectionGutterView.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
            sectionGutterView.topAnchor.constraint(equalTo: textView.topAnchor),
            sectionGutterView.bottomAnchor.constraint(equalTo: textView.bottomAnchor),
        ])
    }

    private func applyEditorPreferencesIfNeeded(editorTextAlignment: EditorTextAlignment, showsRuledLines: Bool) {
        if lastAppliedEditorTextAlignment != editorTextAlignment {
            lastAppliedEditorTextAlignment = editorTextAlignment
            applyParagraphAlignment(editorTextAlignment.nsTextAlignment)
        }

        if lastAppliedRuledLinesEnabled != showsRuledLines {
            lastAppliedRuledLinesEnabled = showsRuledLines
            ruledBackgroundView.isEnabled = showsRuledLines
        }
    }

    private func applyParagraphAlignment(_ alignment: NSTextAlignment) {
        textView.textAlignment = alignment

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment

        // Ensure both existing text and typing attributes match.
        let fullRange = NSRange(location: 0, length: (textView.text as NSString).length)
        if fullRange.length > 0 {
            textView.textStorage.beginEditing()
            textView.textStorage.addAttribute(.paragraphStyle, value: paragraph, range: fullRange)
            textView.textStorage.endEditing()
        }

        var attrs = textView.typingAttributes
        attrs[.paragraphStyle] = paragraph
        textView.typingAttributes = attrs
    }

    private func applySectionBracketsIfNeeded(_ next: [SectionBracket]) {
        guard next != lastAppliedSectionBrackets else { return }
        lastAppliedSectionBrackets = next
        sectionGutterView.brackets = next
    }

    private func presentSectionOverrideSheet(for bracket: SectionBracket) {
        let title = bracket.labelText ?? "Section"
        let message = "Lock this stanza to a bar count"

        let sheet = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)

        for bars in [4, 8, 12, 16] {
            sheet.addAction(UIAlertAction(title: "\(bars) bars", style: .default) { [weak self] _ in
                self?.onSetSectionOverride?(bracket.anchor, bars)
            })
        }
        sheet.addAction(UIAlertAction(title: "Clear Override", style: .destructive) { [weak self] _ in
            self?.onSetSectionOverride?(bracket.anchor, nil)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let pop = sheet.popoverPresentationController {
            pop.sourceView = sectionGutterView
            pop.sourceRect = CGRect(x: 28, y: sectionGutterView.bounds.midY, width: 1, height: 1)
        }

        present(sheet, animated: true)
    }

    private func configureSuggestionsBar() {
        let host = UIHostingController(
            rootView: EditorSuggestionsBar(
                suggestions: [],
                isLoading: false,
                barPosition: nil,
                endRhymeTailLength: 1,
                onSetEndRhymeTailLength: { [weak self] next in
                    self?.onEndRhymeTailLengthChanged?(next)
                }
            ) { [weak self] word in
                self?.insertSuggestion(word)
            }
        )
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.sizingOptions = [.intrinsicContentSize]

        host.view.setContentCompressionResistancePriority(.required, for: .vertical)
        host.view.setContentHuggingPriority(.required, for: .vertical)

        host.view.setContentCompressionResistancePriority(.required, for: .horizontal)
        host.view.setContentHuggingPriority(.defaultLow, for: .horizontal)

        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        suggestionsHostingController = host
    }

    private func configureLayout() {
        textView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(textView)

        guard let suggestionsView = suggestionsHostingController?.view else {
            assertionFailure("Expected suggestionsHostingController to exist")
            return
        }

        view.bringSubviewToFront(suggestionsView)

        textBottomToSuggestionsTop = textView.bottomAnchor.constraint(equalTo: suggestionsView.topAnchor)
        textBottomToSafeBottom = textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)

        // When suggestions are hidden, collapse their height so the text view can fill.
        suggestionsHeightZero = suggestionsView.heightAnchor.constraint(equalToConstant: 0)
        suggestionsHeightZero?.priority = .required

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.topAnchor.constraint(equalTo: view.topAnchor),

            suggestionsView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            suggestionsView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            suggestionsView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])

        // Default: hidden until focused.
        textBottomToSafeBottom?.isActive = true
        textBottomToSuggestionsTop?.isActive = false
        suggestionsHeightZero?.isActive = true
    }

    private func applyAppearance(preferredColorScheme: ColorScheme?, preferredTextColor: Color?, preferredTintColor: Color?) {
        if let preferredColorScheme {
            textView.keyboardAppearance = preferredColorScheme == .dark ? .dark : .light
        }
        if let preferredTextColor {
            textView.textColor = UIColor(preferredTextColor)
        }
        if let preferredTintColor {
            textView.tintColor = UIColor(preferredTintColor)
        }
    }

    private func applyTextIfNeeded(_ nextText: String) {
        guard textView.text != nextText else { return }
        isApplyingExternalText = true
        textView.text = nextText
        isApplyingExternalText = false
    }

    private func applySelectionIfNeeded(_ nextRange: NSRange) {
        let textLength = (textView.text as NSString).length
        var clamped = nextRange
        if clamped.location < 0 { clamped.location = 0 }
        if clamped.location > textLength { clamped.location = textLength }
        if clamped.length < 0 { clamped.length = 0 }
        if clamped.location + clamped.length > textLength {
            clamped.length = max(0, textLength - clamped.location)
        }

        guard textView.selectedRange != clamped else { return }
        isApplyingExternalSelection = true
        textView.selectedRange = clamped
        isApplyingExternalSelection = false
    }

    private func applyHighlightsIfNeeded(_ highlights: [TextHighlight]) {
        guard highlights != lastAppliedHighlights else { return }
        lastAppliedHighlights = highlights

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

    private func updateSuggestionsBar(suggestions: [String], isLoading: Bool, barPosition: BarPosition?, endRhymeTailLength: Int) {
        guard let host = suggestionsHostingController else { return }
        host.rootView = EditorSuggestionsBar(
            suggestions: suggestions,
            isLoading: isLoading,
            barPosition: barPosition,
            endRhymeTailLength: endRhymeTailLength,
            onSetEndRhymeTailLength: { [weak self] next in
                self?.onEndRhymeTailLengthChanged?(next)
            }
        ) { [weak self] word in
            self?.insertSuggestion(word)
        }
    }

    private func setSuggestionsVisible(_ isVisible: Bool) {
        let shouldShow = isVisible

        guard let suggestionsView = suggestionsHostingController?.view else { return }

        if shouldShow {
            if suggestionsHeightZero?.isActive == true {
                suggestionsHeightZero?.isActive = false
            }
            textBottomToSafeBottom?.isActive = false
            textBottomToSuggestionsTop?.isActive = true
            suggestionsView.isHidden = false
        } else {
            textBottomToSuggestionsTop?.isActive = false
            textBottomToSafeBottom?.isActive = true
            suggestionsHeightZero?.isActive = true
            suggestionsView.isHidden = true
        }
    }

    private func setFocus(_ isFocused: Bool) {
        if isFocused {
            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
        } else {
            if textView.isFirstResponder {
                textView.resignFirstResponder()
            }
        }
    }

    private func ensureCaretVisible(reason: EnsureCaretReason, animated: Bool) {
        // Let UIKit keep the caret visible during user-driven typing.
        if isUserScrolling {
            // Don't fight the user's scroll.
            return
        }
        guard textView.isFirstResponder else { return }
        guard let selectedTextRange = textView.selectedTextRange else { return }

        let caret = textView.caretRect(for: selectedTextRange.end)
        let paddingTop: CGFloat = 12
        let paddingBottom: CGFloat = 18

        var target = caret
        target.origin.y -= paddingTop
        target.size.height += paddingTop + paddingBottom

        // Avoid excessive scrolling during background updates.
        switch reason {
        case .insertion, .focus:
            break
        case .typing, .layout, .externalUpdate:
            break
        }

        textView.scrollRectToVisible(target, animated: animated)
    }

    private func insertSuggestion(_ word: String) {
        guard textView.markedTextRange == nil else { return }

        let selected = textView.selectedRange
        let nsText = textView.text as NSString? ?? "" as NSString

        var suffix = " "
        let insertionEnd = selected.location + selected.length
        if insertionEnd < nsText.length {
            let next = nsText.character(at: insertionEnd)
            if let scalar = UnicodeScalar(next), CharacterSet.whitespacesAndNewlines.contains(scalar) {
                suffix = ""
            }
        }

        let replacement = word + suffix

        isPerformingProgrammaticEdit = true
        if let range = textView.selectedTextRange {
            textView.replace(range, withText: replacement)
        } else {
            // Fallback to textStorage replacement.
            textView.textStorage.replaceCharacters(in: selected, with: replacement)
        }

        let newCursor = selected.location + (replacement as NSString).length
        textView.selectedRange = NSRange(location: newCursor, length: 0)
        isPerformingProgrammaticEdit = false

        onTextChanged?(textView.text)
        onSelectionChanged?(textView.selectedRange)
        onSuggestionAccepted?(word)

        ensureCaretVisible(reason: .insertion, animated: false)
    }
}

extension EditorTextViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        guard !isApplyingExternalText else { return }
        guard !isPerformingProgrammaticEdit else { return }
        onTextChanged?(textView.text)
        ensureCaretVisible(reason: .typing, animated: false)
        sectionGutterView.setNeedsDisplay()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        guard !isApplyingExternalSelection else { return }
        guard !isPerformingProgrammaticEdit else { return }
        onSelectionChanged?(textView.selectedRange)
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        onFocusChanged?(true)
        ensureCaretVisible(reason: .focus, animated: false)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        onFocusChanged?(false)
    }
}

extension EditorTextViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        sectionGutterView.setNeedsDisplay()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isUserScrolling = true
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            isUserScrolling = false
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        isUserScrolling = false
    }
}

#endif
