# requirements.md — LyricsLab

## MVP (must ship)
### Core writing experience
- Compositions list (Home) with:
  - Create, open, delete compositions
  - Search that matches both title and lyrics (case-insensitive)
- Editor with:
  - Title field at top
  - Lyrics editing (fast, stable, good cursor behavior)
  - Rhyme grouping + highlighting:
    - End rhymes
    - Near rhymes (slant rhymes)
  - Keyboard accessory bar with horizontally scrolling rhyme suggestions
- Settings:
  - Accessed via spinning gear button on Home
  - Theme switcher (default themes included)
  - iCloud sync toggle (default ON)

### Themes (unlocked)
- RetroFuturistic (default)
- Plain Light
- Plain Dark
- DirtyDishes (Catppuccin Mocha lavender-inspired)

### Non-functional requirements
- Fast and efficient:
  - Debounce rhyme analysis
  - Cache CMU dict parse
  - Avoid heavy blur in scrolling regions
- Offline-first:
  - CMU dict local is primary rhyme source
- Privacy:
  - No external calls in MVP (unless user explicitly opts in post-MVP)

## Post-MVP (planned; not required)
- External rhyme API fallback (IAP-locked)
- AI co-writer suggestions (IAP-locked)
- Music player expansions:
  - Apple Music (IAP-locked)
  - YouTube (IAP-locked; policy review needed)
- Custom themes beyond defaults (IAP-locked)
- Custom icons beyond defaults (IAP-locked)
- Advanced export (PDF), collaboration, etc.

## Monetization requirements
- Paid features show a “pretty little” paywall card when accessed.
- Free trial (details TBD).
- Dev-only setting: “Bypass IAP” for development/testing.

## Decisions (to finalize early)
1) Persistence: SwiftData+CloudKit vs CoreData+CloudKit.
2) Editor: `UITextView` wrapper (recommended) vs pure SwiftUI (likely insufficient for highlights).
3) Near-rhyme similarity metric + thresholds.
4) Search indexing approach: in-memory filter vs stored `searchBlob`.

## Acceptance criteria (MVP)
- Typing remains responsive with rhyme highlighting enabled.
- Rhyme highlights are stable and understandable (no flicker, no random regrouping).
- Suggestions insert correctly at cursor.
- Search returns results from lyrics body and titles.
- Theme switching keeps editor readable (contrast).
- iCloud sync works on two devices (basic sanity test).
