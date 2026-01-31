# LyricsLab — plan.md (SwiftUI)

## 0) Project goals (MVP-first)
**Primary goal:** a fast, offline-first lyrics writing app with a great editor experience and rhyme highlighting/suggestions.  
**Not top priority (post-MVP):** AI co-writer, external APIs, Apple Music/YouTube integration, extra themes/icons, advanced player, etc.

**MVP must include:**
- SwiftUI-only UI (no UIKit view controllers; UIKit wrappers allowed only when strictly necessary, e.g. advanced text editing).
- Home view: compositions list + search that matches **titles and lyrics**.
- Editor view: title field at top, lyrics text editor, rhyme grouping + highlighting (end rhymes + near rhymes) using local `cmudict.txt`.
- Suggestions bar above keyboard: horizontally scrolling rhyme suggestions based on current line/rhyme scheme.
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
- Lyrics editor body (multi-line, `UITextView`-backed for cursor + styling reliability).
- Rhyme highlighting overlay (end rhymes + near rhymes) that preserves selection + scroll stability.
- Top-right: music player button (MVP: local files only; advanced later).
- Bottom mini-player bar appears when track playing:
  - Track name + artist (if available)
  - Animated visualizer
  - Tap to expand player (future)
- Above keyboard: suggestions bar (pinned above the keyboard via `UIKeyboardLayoutGuide`, not `inputAccessoryView`)
  - Horizontal scroll
  - Shows rhyme-matching words prioritized by relevance
  - Tap inserts `word` + exactly one trailing space at the caret/selection; caret remains visible afterward
  - Avoid interfering with IME composition (respect `markedTextRange`)

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

### 4.2.1 Tokenization + normalization (rap-friendly, MVP+)
- Tokenization:
  - Split hyphenated tokens (e.g. "late-night") for lookup.
  - Treat common rap tokens as first-class (numbers like "24/7", "808", "9mm"; hashtags; apostrophe drops like "gon'").
- Add a small normalization map *for lookup only* (keep original display text):
  - `runnin` -> `running`, `nothin` -> `nothing`, `gon`/`gon'` -> `gonna`, `'cause` -> `because`
- Highlighting can be conservative (skip unknown/weird tokens); suggestions should be aggressive (try multiple normalizations).

### 4.2.2 Multi-syllable rhyme tails (post-MVP, rap-first)
- Keep baseline: last stressed vowel nucleus -> end.
- Add optional `tail2`/`tail3`/`tail4` keys (last K vowel nuclei + codas) for punchier rap rhymes.
- Add a user toggle for end-rhyme targeting: `1-syllable` vs `2-syllable` (default TBD).
- Consider using the selected tail length for scheme letters + suggestions even if highlighting starts with tail1.

### 4.2.3 Phrase-end rhymes (multiword, post-MVP)
- For line ends, consider building a rhyme tail from the last N tokens (N=1..4), skipping ad-libs/fillers.
- Stage 1: use phrase tails for scheme inference / targeting only.
- Stage 2: optional phrase suggestions in a separate lane once phoneme->range mapping is solid.

### 4.3 Internal rhyme detection (MVP, cross-line up to 4 lines)
Definition (MVP):
- Detect rhyming words that occur inside lines and connect them across nearby lines, using a maximum span of 4 lines (current line ± 3).
- The end word can participate in an internal rhyme group (groups may contain both internal and end occurrences).

Algorithm (fast, deterministic, low-noise):
1) Split lyrics into lines and compute `lineIndex` per token.
2) Tokenize each line into word tokens, tracking:
   - `rangeInFullText`
   - `lineIndex`
   - `isLineFinalToken: Bool`
3) For each token, lookup CMU phonemes and compute a rhyme key (last stressed vowel → end).
4) Build occurrences: `Occurrence(word, rhymeKey, lineIndex, range, isFinal)`
5) Grouping with line-distance constraint:
   - Two occurrences with the same rhyme key are "connected" if `abs(lineA - lineB) <= 3` (within 4-line span).
   - Treat occurrences as nodes; add edges when connected; each connected component becomes a `RhymeGroup`.
   - This keeps groups local/stanza-like.
6) Noise control:
   - Only highlight groups with size ≥ 2.
   - Stricter near-rhyme threshold for internal than end rhymes.
   - Cap active groups per 4-line window if cluttered, prioritizing: (a) more occurrences, (b) groups with line-final token, (c) groups near cursor.

UI treatment:
- End occurrences: background fill (stronger).
- Internal occurrences: underline or faint tint (lighter).
- Mixed groups share color; style is per-occurrence.
- If token is line-final, always use end-occurrence styling.

**Near rhyme (slant rhyme):**
- Compute similarity between rhyme keys:
  - Compare last vowel phoneme class + ending consonant cluster similarity.
  - Provide threshold-based grouping.
- Add a near-rhyme mode used by both highlighting + suggestions:
  - `Strict` (exact only)
  - `Rap` (exact + curated near; default TBD)
  - `Wild` (assonance + consonance)
- Penalize stress mismatch for near rhymes to reduce false positives.

Output:
- `RhymeGroup { id, type: end/internal/near, key, colorIndex, occurrences[] }`

### 4.4 Highlighting strategy
- Highlight “rhyme words” in the editor, not entire lines.
- Colors:
  - Palette derived from theme accent + complementary tones.
  - Ensure readability (contrast).
- Highlight policy (avoid confetti):
  - Do not highlight singletons (group size must be >= 2).
  - Keep near rhymes opt-in or lower emphasis than exact.
- Stable color assignment:
  - Same rhyme family keeps the same color across edits (deterministic group IDs + colorIndex).
  - Only assign a new palette color when a genuinely new family appears.
- Practical highlight modes (persist per-song):
  - `End Only`
  - `End + Internal` (default TBD)
  - `End + Internal + Near`
- Implementation options:
  1) **AttributedString + TextEditor replacement** (hard in pure SwiftUI; fragile for caret + scroll).
  2) A UIKit editor host (recommended for MVP + "bulletproof" feel):
     - `UIViewControllerRepresentable` wrapper owns:
       - `UITextView` (scrolling + selection source of truth while editing)
       - Suggestions bar pinned above keyboard using `view.keyboardLayoutGuide`
       - A `UIHostingController` that hosts the SwiftUI `EditorSuggestionsBar`
     - Enables:
       - Accurate cursor insertion at caret/selection
       - Per-range highlighting (underline/background)
       - Reliable caret visibility (no hiding under keyboard/suggestions bar)
       - Interactive keyboard dismissal that feels native

**Decision:** Use a `UIViewControllerRepresentable` editor controller early (UITextView + pinned suggestions bar via `UIKeyboardLayoutGuide`) to avoid `TextEditor` limitations and reduce scroll/caret fragility.

### 4.4.1 "Bulletproof" scrolling + caret invariants (MVP)
Product invariants (editor must feel top-tier):
- Caret stays visible when typing and after suggestion insertion (with a small vertical breathing room).
- Applying highlights must not jump scroll position.
- If the user intentionally scrolls away from the caret, do not yank them back unless they perform an explicit "return to editing" action (typing, tapping a suggestion, tapping into the editor).

Implementation rules of thumb:
- Avoid `textView.text = ...` for suggestion insertion or highlight passes; use `textStorage.replaceCharacters` (or `UITextInput` replacement) and preserve selection explicitly.
- During active editing, treat the `UITextView` as the source of truth; SwiftUI receives updates but should not continuously push full text back into the view.
- Gate caret auto-scrolling during highlight updates if the user is actively scrolling/decelerating.

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
- Suggestions bar above keyboard with horizontal chips:
  - Word chip tap → insert
  - Long press → preview alternatives / pronunciation (future)

Internal rhyme interaction (MVP behavior):
- If cursor is mid-line, suggestions can target the last completed token (internal rhyme building) OR the active end-rhyme scheme.
- Keep this as a simple heuristic; avoid UI mode switches.

Cross-line behavior:
- Prioritize suggestions matching the most recently active rhyme group within the last 4 lines.

Suggestion insertion mechanics (MVP):
- Tap suggestion inserts `word` + one trailing space (no double spaces).
- If there is a selection, replace it.
- If there's active IME composition (`markedTextRange != nil`), do not force insertion/selection changes mid-composition.
- After insertion, ensure caret visibility (generally non-animated) without fighting intentional user scrolling.

### 4.5.1 Suggestion ranking pipeline (MVP+, debuggable)
Candidate generation (high recall, cheap):
- Exact rhymes: `rhymeKey -> [word]`
- Near rhymes: union of nearby keys (mode-controlled)
- Merge user lexicon candidates (global + per-song)
- Optional (post-MVP): API augmentation for OOV/meaning-related candidates

Feature scoring (mid cost):
- `rhymeScore` (0..1) as a hard gate
- `frequencyScore` (avoid obscure)
- `personalScore` (boost words the user accepts/uses)
- `fitScore` (basic "does this fit here" heuristics; start simple)
- `contextScore` (optional; semantic relatedness)
- `recencyPenalty` (avoid repeats)

Default scoring (start simple and tune with real stanzas):
```text
score = 0.45*rhymeScore
      + 0.20*fitScore
      + 0.15*contextScore
      + 0.10*personalScore
      + 0.10*frequencyScore
      - 0.25*recencyPenalty
```

Diversity + stability (top-K only):
- Cap 1-2 per lemma family and 1-2 per rhymeKey bucket.
- Optional: MMR-style reranking for the final 12.
- Cache suggestions by `(targetKey, mode, stanzaHash)` and add hysteresis so the list doesn’t shuffle on every keystroke.

### 4.5.2 Context scoring (post-MVP)
- Offline-first: `NLEmbedding`-based similarity using keywords from the last 1-4 lines (stopword-filtered).
- Optional online augmentation (paid): Datamuse / RhymeBrain (cache results; handle attribution + rate limits).

### 4.6 User dictionary + personalization (MVP+)
Two-layer model (merge at query time):
- Global user lexicon:
  - preferred casing, tags/topics
  - accept count + last used
  - syllable override
  - pronunciation override (ARPAbet tail or full pronunciation)
- Per-song lexicon:
  - auto-collected from the current song (frequent tokens, named entities)
  - user can pin words/phrases

Implementation note:
- Expose a single `Lexicon` interface used by both:
  - rhyme lookup/normalization
  - suggestion candidate generation + `personalScore`
- UI escape hatch: tap a word -> "Sound" sheet to override syllables/pronunciation.

### 4.7 Syllable counting + caret position inside a bar (post-MVP)
- Primary syllable source: CMUdict pronunciation (count vowel phonemes).
- Fallback: heuristic syllable estimate (mark low confidence; allow overrides).
- Baseline bar model: 1 text line == 1 bar (common in rap writing). Later: allow 2 lines per bar or explicit bar markers.
- Caret -> syllable index:
  - tokenize bar with character ranges
  - sum syllables before caret, snapping to token boundaries to avoid jitter
- Map to a 16-step grid and render a subtle per-line bar ruler + current caret step highlight.

### 4.8 Recognizing 4/8 bar sections (post-MVP)
- Split into stanzas by blank lines (already a strong signal).
- Estimate bars per stanza (baseline: line count), optionally adjusted by syllable consistency.
- Snap and label when near {4, 8, 12, 16} within a tolerance band.
- UI: show a gutter bracket (e.g. "8 bars") with a quick tap override to lock it.

### 4.9 Hip-hop lyric optimization metrics (post-MVP)
- Rhyme density: rhyming syllables per bar/line.
- Multi-syllable strength: show when end rhymes match on 2-3 syllables.
- Repetition management: detect repeated end words; suggest synonyms that preserve the rhyme tail.
- Flow/stress alignment (optional): use stress patterns to estimate beat placement; present as a "flow grid" (not judgment).

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
- Implement a UIKit-backed editor using `UIViewControllerRepresentable`:
  - Controller owns `UITextView` + pinned suggestions bar (via `UIKeyboardLayoutGuide`)
  - Keep `UITextView` as the source of truth during active editing to avoid SwiftUI feedback loops
  - Provide insertion API for suggestion chips (no full-text replacement; preserve undo + selection)
  - Ensure caret visibility policy (typing + insertion) without yanking user scroll position while reading
- Title field at top.
- Likely implementation files:
  - Add `LyricsLab/Features/Editor/EditorTextViewController.swift`
  - Add `LyricsLab/Features/Editor/EditorTextViewControllerRepresentable.swift`
  - Update `LyricsLab/Features/Editor/EditorView.swift` to use the controller-backed editor
  - Keep `LyricsLab/Features/Editor/EditorSuggestionsBar.swift` (hosted inside the controller via `UIHostingController`)
  - Reduce/replace `LyricsLab/Features/Editor/LyricsTextView.swift` (inputAccessory-based approach)

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
- Implement near rhyme similarity heuristic (mode-controlled: `Strict` / `Rap` / `Wild`).
- Suggestions bar above keyboard:
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

### Milestone 10 — Rap/flow writing tools (post-MVP, phased)
- Phase 1: Suggestions feel personal
  - Global + per-song lexicon, `personalScore`, recency/diversity, hysteresis + caching.
- Phase 2: Syllables + bar ruler
  - `SyllableEngine` + caret-to-step mapping, low-confidence cues + overrides.
- Phase 3: Multi-syllable rhyme keys
  - `tail2`/`tail3` keys + end-rhyme target toggle; scheme uses selected tail.
- Phase 4: Context-aware ranking (offline)
  - `NLEmbedding` context scoring; keep rhymeScore as a hard gate.
- Phase 5: Section detection
  - 4/8 bar brackets with quick user overrides.

**Acceptance:**
- Suggestions reflect the user's vocabulary and remain stable while typing.
- Bar ruler/caret step is deterministic and doesn’t jitter.
- Multi-syllable rhyme mode noticeably improves rap end rhymes.

---

## 11) Key performance considerations
- Debounce expensive operations:
  - Rhyme analysis after typing pauses (e.g. 250–400ms).
- Parse CMU dict once; cache parsed output.
- Highlight updates should touch only changed ranges when possible (optimize later), and must avoid full `textView.text` resets.
- Gate highlight application while the user is actively scrolling/decelerating to avoid visible jitter.
- Suggestion ranking should be stable:
  - cache by `(targetKey, mode, stanzaHash)`
  - add hysteresis to avoid reshuffling on small score changes
- Keep candidate generation near O(1) using indexes (`rhymeKey -> [word]`, optional `tail2Key -> [word]`).
- Avoid heavy blur layers in scrolling lists and the editor background.
- Use Instruments early (Time Profiler, Allocations).

---

## 12) Open questions / decisions to finalize
1) Persistence choice: SwiftData+CloudKit vs CoreData+CloudKit (pick one early).
2) Exact rhyme heuristic: last stressed vowel → end (standard) vs alternative.
3) Near rhyme similarity method + thresholds (tune with test lyrics).
4) Text editor implementation details:
   - `UIViewControllerRepresentable` editor host: caret visibility policy, scroll stability, insertion mechanics, undo/redo.
5) Highlight palette rules per theme to guarantee accessibility contrast.
6) Tokenization + normalization map scope (hyphens, numbers, slang spellings) and how conservative highlighting should be vs suggestions.
7) Multi-syllable rhyme tail length (tail2/tail3/tail4) and the default end-rhyme target toggle.
8) Bar model choice for the editor (1 line == 1 bar vs 2 lines == 1 bar vs explicit markers) and per-song overrides.
9) Personalization storage choice (SwiftData vs file-backed) and privacy posture (no lyric content logging).
10) Context scoring approach (simple n-grams vs `NLEmbedding`) and when to keep it post-MVP.


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
