# scrolling.md — Scrolling management (current)

This doc describes how LyricsLab currently handles scrolling across the app, with special focus on the editor (where we rely on UIKit).

## Where scrolling happens

### Home (composition list)
- `LyricsLab/Features/Home/HomeView.swift` uses a SwiftUI `List` for vertical scrolling.
- The list’s default scroll behavior is used (no explicit scroll position storage/restoration, no programmatic `scrollTo`).
- Visual/background handling while scrolling:
  - `themeManager.theme.backgroundGradient` sits behind the list.
  - `.scrollContentBackground(.hidden)` removes the default list background so the gradient shows through.
  - Each row sets `.listRowBackground(themeManager.theme.surface)` so rows remain readable while the list scrolls.

### Settings (preferences)
- `LyricsLab/Features/Settings/SettingsView.swift` uses a SwiftUI `List` (sections, picker, toggles) for vertical scrolling.
- Same background approach as Home:
  - gradient behind the list
  - `.scrollContentBackground(.hidden)` to avoid the default list background

### Editor (lyrics input)
The editor’s main vertical scrolling surface is the lyrics text control, not a SwiftUI `ScrollView`.

- `LyricsLab/Features/Editor/EditorView.swift` embeds `LyricsTextView`, which wraps a UIKit `UITextView`.
- `UITextView` provides the actual scrolling and caret visibility behavior.

Key configuration in `LyricsLab/Features/Editor/LyricsTextView.swift`:
- `textView.alwaysBounceVertical = true` keeps the editor feeling scrollable even for short text.
- `textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)` adds breathing room so the first/last lines aren’t pinned to edges.
- `textView.keyboardDismissMode = .interactive` enables swipe-down interactive keyboard dismissal while scrolling.

## Keyboard + accessory bar

The editor shows suggestions in a keyboard accessory view (so it stays “attached” to the keyboard instead of stealing vertical space).

- `LyricsLab/Features/Editor/LyricsTextView.swift` creates a `UIHostingController` for the SwiftUI accessory content and mounts it into a `UIInputView`.
- That `UIInputView` is assigned to `textView.inputAccessoryView`.
- The accessory itself (`LyricsLab/Features/Editor/EditorSuggestionsBar.swift`) contains a horizontal `ScrollView(.horizontal, showsIndicators: false)` for scrolling through suggestion chips.

## Selection + programmatic insertion

Scrolling is not managed directly during insertions; instead, we rely on `UITextView`’s built-in behavior for keeping the insertion point visible.

- Selection is bridged via a binding:
  - `UITextViewDelegate.textViewDidChangeSelection` updates `selectedRange`.
  - `updateUIView` pushes SwiftUI’s `selectedRange` back into `uiView.selectedRange` when needed.
- Insertion from the suggestions bar:
  - `EditorView` sets `pendingInsertion`.
  - `LyricsTextView.updateUIView` detects a new `TextInsertion.id`, then calls `Coordinator.insert(text:into:)`.
  - The coordinator replaces the selected range, moves the cursor to the end of the inserted word, and uses `forcedSelectedRange` to prevent SwiftUI/UITextView selection feedback loops.

Notably:
- There is no explicit call to `scrollRangeToVisible` or manual `contentOffset` adjustment.
- There is no scroll position persistence/restoration when leaving and re-entering the editor.

## Highlighting (rhyme UI)

- `LyricsLab/Features/Editor/LyricsTextView.swift` applies highlights by mutating `textView.textStorage` (background/underline attributes).
- This does not change scroll position; it’s purely visual.

## Current non-goals / limitations

- No global “scroll to top” behavior.
- No explicit scroll restoration across navigation (Home <-> Editor) or app relaunch.
- No explicit “keep caret above keyboard” logic beyond UIKit defaults (no keyboard notifications, no custom insets).
- EditorSuggestionsBar scrolls horizontally only; vertical scrolling remains owned by `UITextView`.
