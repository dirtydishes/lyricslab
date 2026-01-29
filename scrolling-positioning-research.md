# scrolling-positioning-research.md -- Research + plan for "bulletproof" scrolling & cursor positioning

This document is a deeper follow-up to `scrolling.md`. It focuses on the editor experience: caret visibility, stable scrolling, and a word-suggestion strip above the keyboard that inserts `word + " "` and leaves the cursor at the end.

The goal is an implementation that feels like a top-tier chat/notetaking app: it never "jumps" unexpectedly, never hides the caret behind the keyboard/suggestions bar, and remains reliable across keyboard modes (dock/undock/floating, hardware keyboards, iPad split-screen).

## What "bulletproof" means (product invariants)

### Caret visibility
- If the user types, the caret stays visible (preferably with a small vertical breathing room).
- If the user taps a suggestion chip, insertion happens at the caret/selection and the caret remains visible after insertion.
- If the user intentionally scrolls away from the caret (to read earlier lines) we avoid yanking the scroll position back unless the user performs an action that implies "return to editing" (typing, tapping a suggestion, tapping into the editor).

### Scroll stability
- Applying highlights (attributed styling) must not jump the scroll position.
- SwiftUI state updates must not repeatedly reset `UITextView.text` or `selectedRange` in a way that causes scroll jitter.
- Keyboard show/hide and interactive dismissal should not cause content to slide under the keyboard/suggestion bar.

### Suggestion insertion behavior
- Tap suggestion inserts `word` + one trailing space (no double spaces).
- Cursor ends up immediately after that space.
- If there is a selection, it's replaced.
- If there is an active IME composition (marked text), do not force insertion/selection changes mid-composition.

## Patterns from high-quality chat + note apps (behavioral)

Even without access to proprietary code, "best-in-class" iOS editors converge on a small set of behaviors:

### Chat apps (iMessage/Slack-like)
- The input UI is visually attached to the keyboard (or effectively behaves that way).
- The text input does not lose first-responder during quick interactions (tapping chips/emoji/autocomplete).
- Autocomplete confirmation commonly appends a space so the user can continue typing immediately.
- Keyboard interaction is expected to be smooth during scroll (interactive dismissal/pan).

Open-source signals that match this:
- Slack's legacy `SlackTextViewController` explicitly appends a space when accepting an autocomplete item ("Adding a space helps dismissing the auto-completion view").
  - Source: https://github.com/slackhq/SlackTextViewController (see "Autocompletion" -> "Confirmation" snippet).

### Notetaking apps (Apple Notes/Bear/Ulysses-like)
- A toolbar/suggestions strip sits above the keyboard.
- The editor's content area is resized/inset so the last line and caret are never hidden behind that strip.
- Styling updates (highlights, formatting) preserve scroll and selection.

## Technical building blocks (UIKit)

### Keyboard layout guide (preferred in modern iOS)

Apple's direction is clear: rely on `UIKeyboardLayoutGuide` instead of doing keyboard math from notifications.

- WWDC21 "Your guide to keyboard layout" introduces `view.keyboardLayoutGuide` and shows replacing the traditional notification-driven approach with a single constraint line.
  - Source (includes transcript + code snippets): https://developer.apple.com/videos/play/wwdc2021/10259/
- Use Your Loaf provides practical guidance + pitfalls for floating keyboards and split-screen.
  - Key takeaway: constrain your UI to the keyboard layout guide to avoid notifications; be careful about centering to the guide when the keyboard partially overlaps your window.
  - Source: https://useyourloaf.com/blog/keyboard-layout-guide/

### Input accessory views: powerful, but first-responder driven

`inputAccessoryView` is a great way to attach UI "to the keyboard", but it only appears when the owning view/controller is in the responder chain.

- MessageKit's FAQ calls out that if you embed `MessagesViewController` as a child, you may need to call `becomeFirstResponder()` because the `MessageInputBar` is an `inputAccessoryView`.
  - Source: https://raw.githubusercontent.com/MessageKit/MessageKit/main/Documentation/FAQs.md

For LyricsLab, this matters because the current implementation attaches `EditorSuggestionsBar` as a `UITextView.inputAccessoryView`.

### Autocomplete "append space" is an established pattern

- InputBarAccessoryView's `AutocompleteManager` has `appendSpaceOnCompletion = true` as a configurable behavior.
  - Source: https://raw.githubusercontent.com/nathantannar4/InputBarAccessoryView/master/GETTING_STARTED.md

This matches the desired UX: tap suggestion -> insert text + trailing space -> caret at end.

### Delegate-driven text + selection tracking

Apple's Text Programming Guide emphasizes using the `UITextViewDelegate` hooks (`textViewDidChange`, `textViewDidChangeSelection`, etc.) to react to edits and track selection.
  - Source: https://developer.apple.com/library/archive/documentation/StringsTextFonts/Conceptual/TextAndWebiPhoneOS/ManageTextFieldTextViews/ManageTextFieldTextViews.html

## Why LyricsLab's current approach is "good but fragile"

Current implementation (see `scrolling.md`):
- Vertical scrolling is owned by `UITextView` inside `LyricsLab/Features/Editor/LyricsTextView.swift`.
- Suggestions UI is attached as an `inputAccessoryView` hosting `EditorSuggestionsBar`.
- Suggestion insertion currently replaces `textView.text` directly and updates `selectedRange`.
- Highlighting re-writes attributes over the whole document on each update.

This works, but these are the typical fragility points in production apps:

1) Full-text replacement (`textView.text = ...`) is the #1 cause of scroll/caret/undo weirdness.
   - It can reset typing attributes, disrupt undo grouping, and sometimes produce small scroll jumps.

2) SwiftUI <-> UIKit feedback loops.
    - If SwiftUI pushes selection/text changes back into the text view too aggressively (especially during `updateUIView`), you can get "micro-jumps" when scrolling or when the keyboard changes.

3) Highlights applied by clearing attributes across the entire range.
   - This can cause layout work that is visible as lag, and can also cause scroll offset adjustments if layout timing changes.

## Recommended architecture (best option)

### Recommendation: move to a UIViewController-based editor with a pinned suggestion bar

Instead of relying on `inputAccessoryView`, build a small UIKit controller that contains:
- a `UITextView` (scrolls vertically)
- a "suggestions bar" view pinned above the keyboard using `view.keyboardLayoutGuide`

This approach gives the most control and is the most "bulletproof":
- The suggestions bar is in your view hierarchy (measurable, testable, animatable).
- You can resize the editor area by constraints (no guessing contentInsets).
- Interactive keyboard dismissal behaves naturally when constraints are tied to the keyboard guide.

Suggested constraint layout (iOS 17+ safe):

```text
root view
  |- textView (top/leading/trailing)
  `- suggestionsHostView (leading/trailing = safeArea; bottom = keyboardLayoutGuide.top)

textView.bottom = suggestionsHostView.top
suggestionsHostView.height = intrinsic (self-sizing)
```

Important detail: keep the suggestions bar width anchored to `safeAreaLayoutGuide` rather than to the keyboard guide's leading/trailing/center. As Use Your Loaf explains, the keyboard guide width can shrink when the keyboard partially overlaps your window in iPad split-screen.

### Keep SwiftUI, but change the wrapper

Use `UIViewControllerRepresentable` instead of `UIViewRepresentable` so the controller can:
- own keyboard-guide constraints reliably
- coordinate "scroll caret into view" after layout/rotation
- host the SwiftUI `EditorSuggestionsBar` in a `UIHostingController`

## Cursor + scroll management algorithms (implementation-level)

### 1) Single source of truth for text while editing

Rule: during active typing, the `UITextView` is the source of truth. SwiftUI receives updates (bindings), but should not continuously push full text back into the view.

Practical strategy:
- On initial load: set `textView.text` once.
- On user edits: update SwiftUI binding from `textViewDidChange`.
- On external model changes (rare in editor): apply a patch/replace, but do it in a controlled code path and preserve selection + scroll.

### 2) Insertion that preserves undo + caret + scroll

Do not set `textView.text` for insertion.

Prefer one of:
- `UITextInput` replacement (`textView.replace(textRange, withText:)`) when you can produce a `UITextRange`, OR
- `textView.textStorage.replaceCharacters(in:with:)` plus an explicit `selectedRange` update.

Suggested insertion behavior (always adds exactly one trailing space):

```swift
func insertSuggestion(_ word: String) {
    // Avoid interfering with IME composition.
    guard textView.markedTextRange == nil else { return }

    let selected = textView.selectedRange
    let nsText = textView.text as NSString? ?? "" as NSString

    // Decide whether to add a trailing space.
    // Insert exactly one space unless the character after the selection is already whitespace/newline.
    var suffix = " "
    let insertionEnd = selected.location + selected.length
    if insertionEnd < nsText.length {
        let next = nsText.character(at: insertionEnd)
        if CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(next)!) {
            suffix = "" // avoid double spaces
        }
    }

    let replacement = word + suffix

    textView.textStorage.beginEditing()
    textView.textStorage.replaceCharacters(in: selected, with: replacement)
    textView.textStorage.endEditing()

    let newCursor = selected.location + (replacement as NSString).length
    textView.selectedRange = NSRange(location: newCursor, length: 0)

    // Push updates to SwiftUI/model.
    onTextChanged(textView.text)
    onSelectionChanged(textView.selectedRange)

    ensureCaretVisible(reason: .insertion, animated: false)
}
```

Notes:
- Many predictive systems replace the *current token* rather than the raw selection. That's optional for LyricsLab; you can add it later by expanding the selected range to the "word under caret" before replacing.

### 3) Ensuring the caret is visible (without fighting the user)

Implement a single helper that:
- computes the caret rect
- expands it with padding (top/bottom)
- scrolls it into view (usually not animated)

Pseudo:

```swift
func ensureCaretVisible(reason: Reason, animated: Bool) {
    guard let selectedTextRange = textView.selectedTextRange else { return }
    let caret = textView.caretRect(for: selectedTextRange.end)

    // Expand by padding so caret isn't glued to the edge.
    let paddingTop: CGFloat = 12
    let paddingBottom: CGFloat = 18
    var target = caret
    target.origin.y -= paddingTop
    target.size.height += paddingTop + paddingBottom

    // Avoid yanking scroll position when the user is reading.
    if isUserScrolling, reason == .highlightUpdate { return }

    textView.scrollRectToVisible(target, animated: animated)
}
```

When to call it:
- after suggestion insertion
- after explicit focus changes (when the user taps the editor)
- after keyboard layout changes (e.g., device rotation)
- *not* on every highlight update

### 4) Highlighting without scroll jumps

Current code clears and reapplies attributes across the full text on each update. That is fine for MVP, but for a "bulletproof" feel:

- Preserve and restore selection explicitly (you already do this with `selectedRange`).
- Avoid calling `textView.text = ...` during highlight passes.
- Avoid doing highlight work if the text view is mid-scroll (e.g., during deceleration).
- Prefer incremental attribute updates, or at least avoid a full `removeAttribute` sweep when nothing changed.

## Plan (step-by-step)

### Phase 1 - New editor host controller (layout correctness)
- Create a UIKit controller that owns the text view and a pinned suggestions bar.
- Use `view.keyboardLayoutGuide` for the suggestions bar's bottom anchor.
- Constrain suggestions bar horizontally to `view.safeAreaLayoutGuide`.
- Set `textView.keyboardDismissMode = .interactive` and `alwaysBounceVertical = true`.

Deliverable: caret never hidden behind keyboard or suggestions bar; interactive dismissal feels native.

### Phase 2 - Robust insertion engine
- Implement insertion via `textStorage.replaceCharacters` (no `textView.text` replacement).
- Enforce "exactly one trailing space" behavior.
- Respect `markedTextRange` (IME).
- Centralize this logic so both taps and future keyboard shortcuts use the same path.

Deliverable: tapping chips feels instantaneous; undo/redo behaves like a real editor.

### Phase 3 - Scroll + caret policy
- Track whether the user is actively scrolling (dragging/decelerating).
- Gate caret auto-scrolling during highlight updates.
- Ensure caret is scrolled into view on explicit user editing actions.

Deliverable: no surprise scroll jumps while reading.

### Phase 4 - Highlight performance + stability
- Add a cheap "no-op" detection (same text + same highlight ranges -> skip).
- Consider incremental attribute updates for changed ranges only.
- If needed, move highlight application to a throttled pipeline so it doesn't contend with scrolling.

Deliverable: smooth scrolling even with lots of highlights.

### Phase 5 - QA checklist + tests

Manual QA scenarios (high value):
- Rapid typing while suggestions update.
- Tap suggestion mid-document; caret remains visible.
- Select a range across lines; tap suggestion; selection replaced; caret at end.
- Scroll away from caret; highlights update; scroll does not jump.
- Rotate device with keyboard shown.
- iPad split-screen + floating keyboard (if you support iPad).

Automated (best-effort) UI tests:
- Validate inserted text includes trailing space.
- Validate insertion happens at the right position by typing after insertion and checking resulting string.

## "Best choice" file paths (what I would change/add)

Recommended implementation (pinned bar with keyboardLayoutGuide):
- Add `LyricsLab/Features/Editor/EditorTextViewController.swift`
- Add `LyricsLab/Features/Editor/EditorTextViewControllerRepresentable.swift`
- Update `LyricsLab/Features/Editor/EditorView.swift`
- Keep (or adapt) `LyricsLab/Features/Editor/EditorSuggestionsBar.swift` (host it in the controller)

Likely to be replaced or reduced in scope:
- `LyricsLab/Features/Editor/LyricsTextView.swift` (current `UITextView` wrapper + inputAccessory approach)

Optional supporting utilities:
- Add `LyricsLab/Features/Editor/TextInsertionEngine.swift` (token range + spacing rules)
- Add `LyricsLab/Features/Editor/CaretVisibilityPolicy.swift`

## Notes about this repo's current state

- LyricsLab currently uses SwiftData and SwiftUI. That strongly suggests a modern iOS baseline, making `UIKeyboardLayoutGuide` a safe default choice.
- Current `LyricsTextView` already demonstrates the correct instinct: use UIKit for the text control and keep SwiftUI around it.
