# LyricsLab — plan.md (SwiftUI)

## 0) Project goals (MVP-first)
**Primary goal:** a fast, offline-first lyrics writing app with a great editor experience and rhyme highlighting/suggestions.  
**Not top priority (post-MVP):** AI co-writer, external APIs, Apple Music/YouTube integration, extra themes/icons, advanced player, etc.

**MVP must include:**
- SwiftUI-only UI (no UIKit view controllers; UIKit wrappers allowed only when strictly necessary, e.g. advanced text editing).
- Home view: compositions list + search that matches **titles and lyrics**.
- Editor view: title field at top, lyrics text editor, rhyme grouping + highlighting (end rhymes + near rhymes) using local `cmudict.txt`.
- Keyboard accessory bar: horizontally scrolling rhyme suggestions based on current line/rhyme scheme.
- Settings: spinning gear button on main view → settings screen.
- iCloud sync option (enabled by default).
- App is responsive, optimized, and stable.

**Paid features (locked behind IAP, not required for MVP to ship):**
- Additional themes beyond Default + Light/Dark + DirtyDishes.
- Additional icons beyond defaults.
- External rhyme APIs fallback.
- AI suggestions.
- Music player beyond local files (Apple Music + YouTube).
- When user taps paid feature: show a “pretty little card” paywall + free trial messaging.
- Dev-only setting toggle: “Bypass IAP”.

---

## 1) Tech stack & architecture
### 1.1 Swift / SwiftUI
- SwiftUI views, `NavigationStack`.
- State management: `@StateObject` view models + `@Observable` (if using Swift 5.9+) or Combine.
- Concurrency: Swift Concurrency (async/await) for parsing CMU dict, indexing text, iCloud operations.

### 1.2 Data layer (offline-first)
Use **SwiftData** (preferred) or **Core Data** if needed for CloudKit flexibility.
- Entities:
  - `Composition`
    - `id: UUID`
    - `title: String`
    - `lyrics: String`
    - `createdAt: Date`
    - `updatedAt: Date`
    - `lastOpenedAt: Date?`
    - `themeOverride: ThemeID?` (optional, future)
    - `rhymeAnalysisCache: Data?` (optional cache, versioned)
  - (Future) `TrackReference`, `UserPreferences`

### 1.3 iCloud sync
- Default ON.
- Implement via **CloudKit-backed** persistence (SwiftData + CloudKit, or Core Data + NSPersistentCloudKitContainer).
- Settings toggle to disable sync:
  - If OFF: use local store only.
  - Provide clear UI explanation and safe migration path.

### 1.4 Modules (logical)
- `LyricsLabApp/` (app entry + environment)
- `Features/Home/`
- `Features/Editor/`
- `Features/Settings/`
- `DesignSystem/` (themes, typography, components, animations)
- `RhymeEngine/` (CMU parsing, rhyme matching, suggestion generation)
- `Persistence/`
- `IAP/` (stubbed early; real StoreKit later)
- `Audio/` (local-only for MVP; expanded later)

---

## 2) UX overview (core flows)
### 2.1 Home (Compositions)
**Default home view:**
- Top: App title “LyricsLab”
- Search bar:
  - Filters by `title` OR `lyrics` content (case-insensitive).
  - Fast for large text bodies (indexing plan below).
- List of compositions:
  - Title
  - Last updated
  - Short snippet preview (first non-empty line or substring)
- Actions:
  - Create new composition
  - Tap composition → Editor

**Settings button:**
- Top-right: **spinning gear** icon button (subtle rotation animation on tap / open).

### 2.2 Editor (Lyrics writing)
Layout:
- Title input at top (single-line, prominent).
- Lyrics editor body (multi-line).
- Rhyme highlighting overlay (end rhymes + near rhymes).
- Top-right: music player button (MVP: local files only; advanced later).
- Bottom mini-player bar appears when track playing:
  - Track name + artist (if available)
  - Animated visualizer
  - Tap to expand player (future)
- Above keyboard: suggestions bar
  - Horizontal scroll
  - Shows rhyme-matching words prioritized by relevance
  - Tap inserts word at cursor (or appends if cursor unknown)

**Reference inspiration:** “Rhymers Block” for the rhyme/suggestion feel, but maintain LyricsLab’s retro-futuristic baseline aesthetic and “liquid glass” polish.

---

## 3) Design system (themes, liquid glass, animations)
### 3.1 Themes
Include these unlocked by default:
- `RetroFuturistic` (default)
- `PlainLight`
- `PlainDark`
- `DirtyDishes` (Catppuccin Mocha lavender vibe)

Theme tokens:
- Colors: background, surface, elevated surface, text primary/secondary, accent, selection, highlight palette (for rhyme groups).
- Typography: title, editor body, UI labels (monospaced optional toggle later).
- Materials: “liquid glass” effect using `Material` + blur + vibrancy-like layering.

### 3.2 Theme switcher
- Settings screen: theme picker.
- Apply globally via environment object (e.g. `ThemeManager`).
- Ensure theme transitions are smooth (crossfade) and do not cause jank.

### 3.3 Custom app icons
- Settings: icon picker (locked behind IAP for non-default icons).
- Implement via `UIApplication.shared.setAlternateIconName` (requires small UIKit bridge; still “pure SwiftUI UI”).

### 3.4 Animations
- “Slick animations” but performance-first:
  - Use `matchedGeometryEffect` sparingly.
  - Avoid heavy blur over large scrolling regions.
  - Keep animations under 200–350ms by default.
- Gear spin:
  - On tap, rotate 180–360 degrees with spring easing.

---

## 4) Rhyme system (MVP: offline CMU dictionary)
### 4.1 Dictionary source
- Bundle `cmudict.txt` locally.
- Parse on first launch (or first use) into an efficient structure.
- Store parsed result in on-disk cache (e.g. `Application Support`) to avoid re-parsing.

### 4.2 Pronunciation model
CMU entries map word → one or more pronunciations (phoneme arrays).
- Normalize word lookup:
  - Lowercase
  - Strip punctuation
  - Handle apostrophes (e.g. “don’t”)
  - Simple stemming optional (future)

### 4.3 Rhyme matching rules (MVP)
**End rhyme detection:**
- For each line, identify last “word-like token”.
- Get its phonemes.
- Determine rhyme key:
  - From last stressed vowel phoneme to end (common rhyme heuristic).
- Group lines/words with same rhyme key.

**Near rhyme (slant rhyme):**
- Compute similarity between rhyme keys:
  - Compare last vowel phoneme class + ending consonant cluster similarity.
  - Provide threshold-based grouping.

Output:
- `RhymeGroup { id, type: end/near, key, colorIndex, occurrences[] }`

### 4.4 Highlighting strategy
- Highlight “rhyme words” in the editor, not entire lines.
- Colors:
  - Palette derived from theme accent + complementary tones.
  - Ensure readability (contrast).
- Implementation options:
  1) **AttributedString + TextEditor replacement** (hard in pure SwiftUI).
  2) A custom text view wrapper (UIKit `UITextView`) for attributed text editing (recommended for MVP feasibility).
     - Still keep the app UI SwiftUI; only the editor control is wrapped.
     - Enables:
       - Accurate cursor insertion
       - Per-range highlighting
       - Underlines / backgrounds for rhyme groups

**Decision:** Use a `UITextView` wrapper early to avoid fighting SwiftUI `TextEditor` limitations.

### 4.5 Suggestions engine (MVP)
Inputs:
- Current line end word (or target rhyme group)
- Known rhyme scheme context (simple heuristic: detect repeated rhyme keys in recent lines)
Outputs:
- Ranked list of candidate words:
  - Exact rhyme > near rhyme
  - Frequency (optional: use word frequency list later)
  - User vocabulary personalization (future: learn from user’s lyrics)

UI:
- Keyboard accessory bar with horizontal chips:
  - Word chip tap → insert
  - Long press → preview alternatives / pronunciation (future)

---

## 5) Search (titles + lyrics) and performance
### 5.1 Search requirements
- Matches in:
  - Title
  - Lyrics body
- Fast enough for large libraries.

### 5.2 Implementation approach
MVP:
- Load compositions list from persistence.
- On search query change:
  - Debounce (150–250ms).
  - Filter in memory for small libraries.
Optimization step:
- Add a lightweight index:
  - Store `searchBlob = (title + " " + lyrics).lowercased()` (computed on save)
  - Search against `searchBlob.contains(queryLowercased)`
- For very large text sets (later): consider SQLite FTS.

---

## 6) Music player (MVP: local files only)
### 6.1 MVP scope
- Import/select local audio files (Files app picker).
- Playback using `AVAudioPlayer` or `AVPlayer`.
- Show mini-player bar in editor when playing:
  - Track title (filename)
  - Play/pause
  - Animated visualizer (simple bar animation driven by timer; not real FFT).

### 6.2 Loop section feature
- Allow user to set A/B loop points:
  - UI in expanded player (sheet from top-right button).
  - Loop toggle + start/end time selectors (scrubber with two handles).
- Implementation:
  - Observe playback time; when reaching B, seek to A.

### 6.3 Post-MVP expansions (IAP locked)
- Apple Music integration (MusicKit).
- YouTube integration (requires careful policy/compliance + likely web player).
- Better visualizer (audio metering/FFT).

---

## 7) Settings & monetization gating (IAP-ready)
### 7.1 Settings screen content
- Theme picker (default themes visible; premium themes locked)
- App icon picker (premium icons locked)
- iCloud Sync toggle (default ON)
- “Bypass IAP (Dev)” toggle (only in debug builds)
- About / version
- (Future) Export/import, fonts, backup

### 7.2 IAP gating UX
When user taps a locked feature:
- Present a compact, attractive paywall card (sheet/overlay):
  - Feature list (Themes, Icons, Advanced rhymes/API, AI co-writer, Music integrations)
  - Trial info
  - Subscribe button
  - Restore purchases
- During development:
  - If “Bypass IAP” ON → unlock everything locally without StoreKit.

### 7.3 StoreKit (post-MVP)
- Use StoreKit 2.
- Products:
  - Subscription: “LyricsLab Plus” (trial)
- Keep the app usable without subscription.

---

## 8) AI + external APIs (explicitly post-MVP)
### 8.1 External rhyme API fallback (paid)
- Only used if CMU lookup fails or for slang/new words.
- Cache results locally.
- Respect rate limits.

### 8.2 AI co-writer (paid)
Behavior:
- “In the room brainstorming”, not replacing the writer.
- Suggestions based on:
  - Rhyme target
  - Current verse context
  - Style/subject inferred from text
UI principles (avoid clutter):
- Keep suggestions in the existing keyboard bar.
- Add a subtle “spark” toggle in the bar:
  - OFF: only rhyme engine
  - ON: AI-augmented suggestions (clearly labeled)
- Provide short suggestions first; expandable to “full bar” insert.

---

## 9) File/export features (nice-to-have after MVP)
- Export composition as:
  - Plain text
  - PDF (later)
- Share sheet integration.

---

## 10) Development milestones (ordered)
### Milestone 1 — App skeleton + persistence
- Project setup, SwiftUI navigation.
- SwiftData/Core Data models for `Composition`.
- Home view list + create/edit/delete.
- Settings button (spinning gear) → placeholder settings.

**Acceptance:**
- Can create compositions, reopen them, edits persist.
- UI is smooth.

### Milestone 2 — Editor control (robust text editing)
- Implement `UITextView` SwiftUI wrapper:
  - Bind to lyrics string
  - Maintain cursor position
  - Provide insertion API for suggestion chips
- Title field at top.

**Acceptance:**
- Typing feels native, no lag.
- Suggestions can insert at cursor.

### Milestone 3 — CMU dict parsing + rhyme detection
- Bundle `cmudict.txt`, parse async.
- Implement rhyme key extraction + end rhyme grouping.
- Apply highlight attributes to rhyme word ranges.

**Acceptance:**
- Common words rhyme correctly.
- Highlighting updates as text changes (debounced).

### Milestone 4 — Near rhyme + suggestions bar
- Implement near rhyme similarity heuristic.
- Keyboard accessory bar:
  - Horizontal scroll
  - Ranked suggestions
- Rhyme scheme heuristics (simple):
  - Look at recent line endings; infer active rhyme group.

**Acceptance:**
- Suggestions feel relevant and stable.
- UI not cluttered.

### Milestone 5 — Themes + DirtyDishes
- Theme manager + tokens.
- Implement default themes.
- Ensure highlights adapt per theme.

**Acceptance:**
- Theme switch is instant and consistent.
- No unreadable highlight colors.

### Milestone 6 — Search
- Search matches titles + lyrics with debounce.
- Optimize with `searchBlob`.

**Acceptance:**
- Search feels instant for typical usage.

### Milestone 7 — iCloud sync toggle
- Add iCloud-backed store (if chosen).
- Settings toggle; verify behavior.

**Acceptance:**
- Works across devices (basic test).
- Disabling sync doesn’t delete local data.

### Milestone 8 — Local music player (MVP)
- File picker import + play.
- Mini-player bar with visualizer.
- Loop A/B in expanded player sheet.

**Acceptance:**
- Can loop a section reliably while typing.
- Player button top-right in editor works.

### Milestone 9 — IAP scaffolding + paywall card (no real products yet)
- Feature gating helpers.
- Paywall card UI.
- Dev bypass toggle.

**Acceptance:**
- Locked features show paywall.
- Bypass unlocks without StoreKit.

---

## 11) Key performance considerations
- Debounce expensive operations:
  - Rhyme analysis after typing pauses (e.g. 250–400ms).
- Parse CMU dict once; cache parsed output.
- Highlight updates should touch only changed ranges when possible (optimize later).
- Avoid heavy blur layers in scrolling lists and the editor background.
- Use Instruments early (Time Profiler, Allocations).

---

## 12) Open questions / decisions to finalize
1) Persistence choice: SwiftData+CloudKit vs CoreData+CloudKit (pick one early).
2) Exact rhyme heuristic: last stressed vowel → end (standard) vs alternative.
3) Near rhyme similarity method + thresholds (tune with test lyrics).
4) Text editor implementation details:
   - `UITextView` wrapper API for ranges, attributes, insertion, undo/redo.
5) Highlight palette rules per theme to guarantee accessibility contrast.

---

## 13) Deliverables checklist (MVP)
- [ ] Home: list, create, delete, search title+lyrics
- [ ] Editor: title, lyrics editing, rhyme highlights
- [ ] CMU dict local rhyme engine + caching
- [ ] Suggestions bar above keyboard (rhyme-based)
- [ ] Settings: gear button (spin), theme switcher, iCloud toggle
- [ ] Default themes including DirtyDishes
- [ ] App performance pass (no obvious lag)
- [ ] Basic local music playback + loop + mini-player bar (if included in MVP scope)

---
