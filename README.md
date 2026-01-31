<pre style="line-height: 1.1;">
<span style="color: #ff5ea8;">    __               _           __          __  </span>
<span style="color: #ff5ea8;">   / /   __  _______(_)_________/ /   ____ _/ /_ </span>
<span style="color: #ff5ea8;">  / /   / / / / ___/ / ___/ ___/ /   / __ `/ __ \</span>
<span style="color: #b45cff;"> / /___/ /_/ / /  / / /__(__  ) /___/ /_/ / /_/ /</span>
<span style="color: #b45cff;">/_____/\__, /_/  /_/\___/____/_____/\__,_/_.___/ </span>
<span style="color: #b45cff;">      /____/                                     </span>
</pre>

# LyricsLab

I'm a musical artist, and for a decade I've been unsatisfied with every single songwriting tool I've found.
So I'm building the app I always wanted: a fast, offline-first writing workspace for hip hop artists and songwriters.
By an artist, for artists - built by somebody who understands real workflows through personal experience and years of working with other artists.

LyricsLab is focused on the craft fundamentals: writing quickly, seeing rhyme structure clearly, and getting rhyme suggestions without breaking your flow.

---

## Current Status

Core writing MVP is working end-to-end.

Core Writing MVP
<progress value="6" max="6"></progress>

- [x] Home: compositions list + create/delete
- [x] Search: matches titles + lyrics via `searchBlob`
- [x] Editor: robust `UITextView`-backed editing (caret stability, selection, IME-safe insert)
- [x] Rhyme highlighting: end rhymes + internal rhymes + near rhymes (low-noise)
- [x] Suggestions bar: rhyme suggestions pinned above the keyboard
- [x] Settings: theme picker + iCloud Sync toggle

Full Vision (selected milestones)
<progress value="7" max="16"></progress>

- [x] Offline-first rhyme engine using bundled `cmudict.txt`
- [x] CMU dictionary parsing + on-disk cache
- [x] Internal rhyme mode (suggestions can target last completed token)
- [x] Theme system (including artist theme support)
- [ ] User dictionary (global + per-song) + pronunciation/syllable overrides
- [ ] Tokenization + normalization improvements for rap writing (hyphens, numbers, slang spellings)
- [ ] Multi-syllable rhyme targets (tail2/tail3) and optional phrase-end rhyme analysis
- [ ] Smarter ranking: frequency + context + personalization + diversity + stability (hysteresis)
- [ ] Syllable grid + cursor-in-bar position (16-step ruler)
- [ ] 4/8 bar section detection + editable structure brackets
- [ ] Audio module (local playback + loop A/B) for writing to a beat
- [ ] IAP gating + paywall card (StoreKit 2 later)
- [ ] External rhyme APIs (opt-in, cached)
- [ ] AI co-writer mode (post-MVP, clearly labeled)

Research notes for the next phase live in:
- `rhyme-flow-research.md`
- `scrolling-positioning-research.md`

---

## What It Does Today

- Write lyrics in a real editor (UIKit-backed) with stable selection and predictable scrolling.
- Automatically highlight rhyme structure:
  - End rhymes (stronger highlight)
  - Internal rhymes (lighter treatment)
  - Near rhymes (low-noise; only when they form real groups and aren't already exact)
- Suggest rhymes above the keyboard:
  - Targets the active end-rhyme key inferred from recent line endings
  - If the cursor is mid-line, can target internal-rhyme building based on the last completed token
- Store compositions locally (SwiftData) and optionally sync via iCloud (restart required after toggling).
- Theme the full UI with consistent color tokens.

Built-in themes (currently):
- `RetroFuturistic` (default)
- `Plain Light`
- `Plain Dark`
- `dirtydishes` (calm lavender, catppuccin mocha inspired)
- `Davy Dolla$` (money-green paper vibe, gold accents; title becomes `Lyric$Lab`)

---

## Next Phase (Rap/Flow Tools)

These are explicitly post-MVP and are being designed to stay deterministic, debuggable, and offline-first:

1) Make suggestions feel personal
- Global + per-song lexicon
- Recency penalties + diversity caps + caching/hysteresis (avoid "shuffling")

2) Syllables + a basic bar ruler
- CMUdict-backed syllable counts (heuristics only as a fallback with low-confidence UI)
- Caret -> syllable index -> 16-step grid highlight

3) Multi-syllable rhyme keys
- Tail keys (`tail2`/`tail3`/`tail4`) for punchier rap rhymes
- Optional end-rhyme target toggle (1-syllable vs 2-syllable)

4) Context-aware ranking (offline)
- `NLEmbedding`-based context scoring layered on top of rhyme-first gating

5) Structure detection
- 4/8 bar brackets inferred from blank lines + syllable consistency + repetition
- User overrides to lock the structure

---

## How It Works (Architecture)

High level
- SwiftUI app shell + navigation (`NavigationStack`)
- SwiftData persistence (`Composition` model)
- Rhyme engine powered by CMU Pronouncing Dictionary data (`cmudict.txt`)
- A UIKit editor surface where SwiftUI is not enough (attributed highlights + reliable caret)

Key modules (folders)
- `LyricsLab/Features/Home/` - compositions list + search
- `LyricsLab/Features/Editor/` - editor UI and keyboard-pinned suggestions
- `LyricsLab/Features/Settings/` - theme + iCloud toggle
- `LyricsLab/RhymeEngine/` - CMU parsing/index, rhyme analysis, suggestions
- `LyricsLab/DesignSystem/` - themes
- `LyricsLab/Persistence/` - SwiftData models + container factory

Editor implementation notes
- `EditorTextViewController` uses a `UITextView` and hosts `EditorSuggestionsBar` pinned to `view.keyboardLayoutGuide`.
- Suggestion insertion avoids full `textView.text` replacement and avoids interfering with IME (`markedTextRange`).
- The caret/scroll behavior is treated as product-critical; details and invariants are documented in `scrolling-positioning-research.md`.

Rhyme engine implementation notes
- `cmudict.txt` is parsed into a compact index and cached on disk (`CMUDictionaryStore`).
- Baseline rhyme key: last stressed vowel to end (ARPAbet tail).
- Internal rhyme grouping is local (bounded by a 4-line window) to prevent visual noise.

---

## Getting Started (Development)

Prereqs
- macOS + Xcode (project currently targets iOS 26.0)

Run in Xcode
1) Open `LyricsLab.xcodeproj`
2) Select the `LyricsLab` scheme
3) Run on a simulator or device

Run from CLI (build)
```bash
xcodebuild -scheme LyricsLab -configuration Debug   -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2" build
```

Run tests
```bash
xcodebuild -scheme LyricsLab -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2" test
```

---

## Project Docs

If you're trying to understand the project quickly:
- `plan.md` - MVP plan + milestones (including post-MVP rap/flow phases)
- `requirements.md` - current MVP requirements
- `architecture.md` - architectural overview
- `testing.md` - lean test strategy
- `scrolling.md` - earlier editor scrolling/caret notes
- `scrolling-positioning-research.md` - "bulletproof" scrolling/caret + pinned suggestions bar research
- `rhyme-flow-research.md` - rhyme/suggestions/flow research + phased plan

---

## Known Gaps (Intentional)

These are not "bugs" as much as "not implemented yet":
- No audio module yet (no local beat playback/looping inside the editor)
- No user dictionary / pronunciation + syllable overrides yet
- Suggestion ranking is currently rhyme-first (no full frequency/context/personalization pipeline yet)
- No multi-syllable rhyme target toggle yet (tail2/tail3)
- Tokenization is conservative; stylized tokens/numbers/rap spellings are a next-phase improvement
- No syllable bar ruler or 4/8 bar section brackets yet

---

## Contributing / Direction

This repo is opinionated: the writing experience comes first.
If you change something that affects typing latency, caret stability, or highlight stability, treat it like a product-critical change.

Good next contributions tend to be:
- deterministic (and stable) candidate ranking for suggestions
- user dictionary + per-song vocabulary + pronunciation overrides
- multi-syllable rhyme keys and better rap-oriented tokenization
- syllable counting + bar/section tooling
