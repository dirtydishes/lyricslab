# architecture.md — LyricsLab

## High-level
SwiftUI app with layered architecture:
- UI (SwiftUI views)
- View models/state
- Services (RhymeEngine, Persistence, Theme, Audio)
- Infrastructure (CloudKit, AVFoundation, StoreKit later)

## Modules (folders)
- `App/` (entry, environment setup)
- `DesignSystem/` (themes, components, animations)
- `Persistence/` (models, store setup, migrations, iCloud toggle)
- `Features/Home/`
- `Features/Editor/`
- `Features/Settings/`
- `RhymeEngine/` (CMU parsing, rhyme keys, near-rhyme, suggestions)
- `Audio/` (local playback MVP)
- `IAP/` (gating + paywall, StoreKit later)

## Key architectural choices
### Text editor
Use a SwiftUI wrapper around `UITextView` to support:
- attributed highlighting ranges
- reliable cursor insertion
- undo/redo behavior
SwiftUI remains the app’s UI layer; UIKit is a single control wrapper.

### Rhyme pipeline (debounced)
- User types -> lyrics string updates
- Debounce (e.g. 300ms)
- Tokenize lines -> extract end words -> lookup phonemes -> compute rhyme keys
- Build groups (end/near)
- Apply attributes only where needed (optimize later)

### CMU dict parsing & caching
- Parse `cmudict.txt` in background on first use
- Cache serialized structure to disk
- Keep in-memory index for fast lookup (word -> pronunciations)

### Persistence + iCloud
- Default: iCloud ON
- Provide safe switching:
  - cloud store (CloudKit-backed)
  - local store
- Avoid data loss:
  - if switching, migrate/copy compositions (strategy documented in Persistence)

### Feature gating
- Central gatekeeper:
  - `FeatureFlags` (dev bypass)
  - `Entitlements` (StoreKit later)
- UI calls `require(.premiumFeature)`:
  - if locked -> show paywall card

## Data flow summary
Home:
- Fetch compositions -> display -> search filter -> open composition

Editor:
- Load composition -> bind title/lyrics -> on edit -> persist -> rhyme analysis -> highlights + suggestions

Audio:
- Player state observed by editor -> mini bar visible when playing

Settings:
- Theme + iCloud + dev toggles update environment/store
