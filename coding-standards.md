# coding-standards.md — Swift/SwiftUI conventions

## Swift formatting
- Use SwiftFormat/SwiftLint if desired; otherwise keep style consistent:
  - 2-space indentation not standard; use Xcode default (4 spaces)
  - Keep functions focused; avoid massive view bodies

## SwiftUI performance
- Minimize `@State` churn; prefer `@StateObject` view models.
- Debounce text-driven heavy work (rhyme analysis).
- Avoid expensive modifiers (large-area blur/material) inside scrolling containers.

## Concurrency
- CMU parsing and rhyme analysis run off-main.
- UI updates applied on main actor.
- Prefer structured concurrency; avoid unbounded Tasks.

## Error handling
- Fail gracefully:
  - if dictionary not loaded, show suggestions as empty and retry load
  - never block typing

## Logging
- Use `os.Logger` with categories:
  - `persistence`, `rhyme`, `editor`, `audio`, `iap`
- Avoid logging user lyrics content in production builds.
