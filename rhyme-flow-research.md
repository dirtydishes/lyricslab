# rhyme-flow-research.md

Research notes + implementation plan for:
- rhyme scheme highlighting
- rhyme suggestions + ranking (context + personalization)
- rhyme scheme detection (including rap/hip-hop)
- syllable-based cursor position inside a bar
- recognizing 4/8 bar sections

Repo context (LyricsLab)
- There is already a working on-device rhyme engine:
  - `LyricsLab/RhymeEngine/CMUDictionary.swift` (CMUdict indexing)
  - `LyricsLab/RhymeEngine/RhymeKey.swift` (rhyme key + near-rhyme similarity)
  - `LyricsLab/RhymeEngine/RhymeAnalyzer.swift` (end + internal + near highlight groups; simple scheme inference)
  - `LyricsLab/RhymeEngine/RhymeService.swift` (async service + suggestions)
- So this doc focuses on what the best apps tend to do beyond the MVP, and how to evolve the current implementation.

Sources referenced (public):
- CMU Pronouncing Dictionary (CMUdict): https://github.com/cmusphinx/cmudict
- pronouncing (CMUdict wrapper/reference logic): https://github.com/aparrish/pronouncingpy
- RiTa (lexicon search, syllables, stress, rhyme patterns): https://github.com/dhowe/rita
- wordfreq (Zipf-style frequency data; useful for ranking/filtering): https://github.com/rspeer/wordfreq
- Datamuse API (sound/meaning/context constraints; syllables, pronunciation metadata): https://www.datamuse.com/api/
- RhymeBrain API (rhymes + pronunciation + syllables + freq; rate limits + attribution requirements): https://rhymebrain.com/api.html
- Rhymer's Block product positioning (real-time rhyme suggestions + color-coded highlighting): https://rhymersblock.com
- Maximal Marginal Relevance (MMR) for diversity re-ranking: https://www.cs.cmu.edu/~jgc/publication/The_Use_MMR_Diversity_Based_LTMIR_1998.pdf
- Apple WWDC (NaturalLanguage embeddings / retrieval patterns):
  - WWDC19 Session 232: https://developer.apple.com/videos/play/wwdc2019/232/
  - WWDC20 Session 10657: https://developer.apple.com/videos/play/wwdc2020/10657/

Additional references for OOV (out-of-vocabulary) pronunciations (mostly server-side / training references):
- g2p-en (G2P; Apache-2.0; good reference for generating pronunciations): https://github.com/Kyubyong/g2p
- phonemizer (phonemization tooling; GPL-3.0, generally not App-Store-friendly if shipped in-app): https://github.com/bootphon/phonemizer

---

## 1) What "good" looks like in rhyme tools

Across rap/poetry-focused writing tools, the wins tend to come from the same product invariants:

1) Phonetics-first, spelling-second
- Spelling-based rhymes ("-ough") are unreliable.
- Phoneme + stress data (CMUdict/ARPAbet for English) produces stable and explainable rhyme groups.

2) Multi-syllable and phrase rhymes are first-class
- Rap rhymes often span multiple syllables and sometimes multiple words.
- A tool that only matches "last word" will feel wrong in hip-hop.

3) Highlighting is useful, not noisy
- Great apps highlight the *structure* (end rhymes, internal rhymes) without turning every line into confetti.
- Stable colors, stable grouping, predictable rules.

4) Suggestions are relevant, not just "technically rhyming"
- A user doesn't want obscure dictionary words.
- Ranking needs frequency, context, and personalization.

5) The editor stays responsive
- Analysis must be incremental, cached, and throttled.
- The UI should not jitter when highlights update.

---

## 2) Rhyme representation: beyond "last letters"

### 2.1 Baseline: last stressed vowel to end

This is a common and effective definition of a "perfect rhyme key" for English:
- Find the last stressed vowel nucleus in the pronunciation (stress digit 1 preferred, else 2, else 0).
- The rhyme tail is from that vowel phoneme through the end of the word.

LyricsLab today:
- `RhymeKey.fromPhonemes` already implements: "last stressed vowel to end", with a fallback.
- This is the right baseline.

Where it breaks for rap:
- Multi-syllable rhyme tails: you often want the last 2-4 vowel nuclei, not just the last stressed vowel.
- Phrase rhymes: the best rhyme might be the last stressed vowel in the *phrase-end*, not necessarily the last word.

### 2.2 Multi-syllable rhyme tails (K-syllable tails)

Technique:
- Convert a word (or phrase) into a sequence of syllable nuclei (vowel phonemes) and their trailing consonant codas.
- Define tails:
  - `tail1`: last vowel nucleus + coda
  - `tail2`: last 2 vowel nuclei + codas
  - `tail3`, `tail4`: etc

Why this matters:
- Rappers often lock onto 2-3 syllables for the "punch" rhyme.
- Highlighting multi-syllable matches is a major "wow" feature.

Implementation steps (extend current engine):
- Add helpers to `RhymeKey`:
  - `func tails(fromPhonemes: [String], maxSyllables: Int) -> [String]`
  - A tail key format can stay ARPAbet-based, e.g. `"AY1 M | AY0"` or similar.
- Store additional indexes:
  - `tail2Key -> [word]`, `tail3Key -> [word]` (optional; start with tail1 only and compute multi-tail on demand).

### 2.3 Phrase-end rhymes (multiword)

In rap, the perceived rhyme at line-end can be a phrase:
- "... in the club" ("in-the-club")
- "... get your grub" ("get-your-grub")

Practical approach (incremental, no full NLP required):
- At the end of a line, consider building the rhyme tail from the last N tokens (N=1..4), skipping trailing fillers.
- Build a phoneme stream for the suffix phrase and extract tails from the stream.

Trade-offs:
- Full phrase rhyme matching requires mapping phonemes back to text ranges for highlighting.
- Suggesting phrases is higher friction than suggesting words; many apps ship words-first.

Recommendation:
- Stage 1: keep suggestions as words, but allow scheme detection / highlighting to use phrase tails.
- Stage 2: add optional phrase suggestions in a separate row or mode.

### 2.4 Tokenization + normalization (rap-friendly)

Tokenization is a surprisingly large part of perceived quality.

LyricsLab today:
- `RhymeAnalyzer` uses regex `"[A-Za-z']+"`.

Problems this causes in real lyrics:
- Hyphenated words: "late-night" should usually be two tokens.
- Numbers: "24/7", "808", "9mm" are common.
- Stylized tokens: "sumn", "finna", "gon'", "'cause".
- Non-ASCII letters (names) if you ever support them.

Pragmatic improvements:
- Expand tokenization to treat hyphen as a split.
- Add a small normalization map before dictionary lookup (rap spellings -> canonical spelling).
  - Example: `runnin` -> `running`, `nothin` -> `nothing`, `gon`/`gon'` -> `gonna` (or `going to` depending on style)
- Keep original display text; normalization is for lookup only.

Rule of thumb:
- Highlighting can be conservative (skip weird tokens).
- Suggestions should be aggressive about normalization (try hard to help).

---

## 3) Near rhymes (slant) without chaos

Users want:
- perfect rhyme options
- then *good* slant rhymes (assonance/consonance)
- not random "almost" matches

LyricsLab today:
- `RhymeKey.signature` clusters vowels into coarse groups and consonants into classes.
- `RhymeKey.similarity` combines vowel similarity + consonant similarity.
- `RhymeAnalyzer.clusterNearOccurrences` only highlights near rhymes for tokens not already in exact groups.
- This "exact first, near second" priority is a strong UX rule.

Improvements worth considering:

1) More nuance in vowel similarity
- Current grouping is rough but workable.
- A next step is a small explicit similarity table for vowel pairs (still fast, still explainable).
- If you ever move to IPA, feature-distance tooling exists (e.g. PanPhon), but that is probably overkill for the first iOS pass.

2) Treat stress mismatch as a penalty
- In rap, stress placement matters.
- Perfect rhyme usually wants the stress pattern to align for the rhyming syllable.

3) Different thresholds for different modes
- Users will want a toggle:
  - `Strict` (exact only)
  - `Rap` (exact + curated near)
  - `Wild` (assonance + consonance)

Implementation sketch:
- Keep `RhymeKey.similarity` but add a `mode` parameter that changes weights/thresholds.
- Feed that mode into both highlighting and suggestions.

---

## 4) Rhyme scheme detection (AABB / ABAB / ...)

### 4.1 What most apps do

1) Default to a simple scheme per section (often AABB)
2) Detect that the user is repeating or alternating rhymes
3) Suggest the expected rhyme family next

LyricsLab already does this:
- `RhymeSchemePlanner` supports AABB/ABAB/ABBA/ABCB/AAAA
- It infers scheme from line-ending rhyme keys within the current "section" (stanza = separated by blank lines)

### 4.2 Where scheme detection can improve

1) Scheme should be based on "bar lines", not just "text lines"
- Many writers treat one editor line == one bar, but not always.
- If you add a bar model (see syllable/bar sections), scheme inference should use *bars*.

2) Multi-syllable scheme letters
- You may want the scheme letter to lock to `tail2` in "multi" mode.
- Example: end words may match on last syllable but differ in the punchy 2-syllable tail.

3) Handle short "setup" lines and ad-libs
- Parenthetical ad-libs `(yeah)` and tags `[hook]` should usually not count toward scheme.

Implementation steps:
- Introduce a `LineRole` classifier (cheap heuristic):
  - `content`, `adlib`, `tag`, `blank`
- Only include `content` lines in scheme inference.
- Add a "scheme confidence" measure and avoid aggressive switching when confidence is low.

---

## 5) Highlighting (good vs bad)

### 5.1 Good highlighting

- Stable color assignment:
  - Same rhyme family should keep the same color across edits.
  - When a new family appears, assign the next palette color.
- Visual priority:
  - End rhymes are the primary signal.
  - Internal rhymes are secondary (often shown with a subtler tint).
  - Near rhymes should be opt-in or "low-noise".
- Avoid highlighting singletons:
  - No highlight unless it appears at least twice in scope.

LyricsLab already follows most of this.

### 5.2 Bad highlighting

- Confetti mode:
  - Every near rhyme highlighted everywhere.
  - Users can't see the structure.
- Jitter:
  - Colors change each time analysis runs.
  - Highlights reflow and cause scroll jumps.
- False-confidence:
  - Spelling matches treated as perfect rhymes.

### 5.3 Practical highlight modes to implement

Consider offering 3 modes (persist per-song):
- `End Only` (fast, clean)
- `End + Internal` (default for rap)
- `End + Internal + Near` (creative exploration)

Implementation steps:
- Reuse `RhymeGroup.type` (`.end`, `.internal`, `.near`) as the backbone.
- In the editor, apply different alpha/underline styles by group type.

---

## 6) Rhyme suggestions: candidate generation + ranking

### 6.1 How the best tools feel

When you tap into a line, the top suggestions should look like:
- real words
- fitting the voice/topic of what you are writing
- matching the rhyme target (strictly or slantly)
- not repeating what you already used

Rhymer's Block positions itself as a "real-time rhyme suggestion engine" with color-coded rhyme highlighting.
Source: https://rhymersblock.com

LyricsLab today:
- Suggestions are generated by rhyme key + "nearby keys", and filtered for basic word quality.
- There is no semantic/context scoring or personalization yet.

### 6.2 The ranking pipeline that tends to work best

Think in 3 stages:

1) Candidate generation (high recall, cheap)
- Exact rhymes: `dictionary.words(forRhymeKey: targetKey)`
- Near rhymes: `dictionary.nearbyRhymeKeys(to: targetKey)` then union their words
- User dictionary candidates (global + song)
- Optional: external APIs for OOV or "meaning-related" candidates (Datamuse/RhymeBrain) if you are OK with network.

2) Feature scoring (mid cost)
- `rhymeScore`: perfect/slant strength (0..1)
- `frequencyScore`: word commonness (avoid obscure)
  - If you want an offline dataset, `wordfreq` is a good reference for Zipf-style frequency scoring.
    - https://github.com/rspeer/wordfreq
- `contextScore`: semantic relatedness to recent content / topic
- `fitScore`: basic language-model / part-of-speech fit
  - A pragmatic offline approach is a small word-level n-gram model trained offline and shipped as a compact table.
  - You do not need "LLM autocomplete" to get a big boost in perceived quality.
- `personalScore`: boost words the user uses/accepts often
- `recencyPenalty`: down-rank words shown/used recently

3) Diversity re-ranking (top-K only)
- Use MMR-style re-ranking to avoid 12 variants of the same thing.
Source: https://www.cs.cmu.edu/~jgc/publication/The_Use_MMR_Diversity_Based_LTMIR_1998.pdf

### 6.3 Recommended default scoring (simple and debuggable)

Start with a gated linear model:
- If `rhymeScore < threshold` then discard or show in a separate "Near" lane.
- Else:

```
score = 0.45*rhymeScore
      + 0.20*fitScore
      + 0.15*contextScore
      + 0.10*personalScore
      + 0.10*frequencyScore
      - 0.25*recencyPenalty
```

Then apply diversity:
- limit 1-2 per lemma family (time/times/timing)
- limit 1-2 per rhymeKey bucket
- MMR for the final 12.

Why this works:
- Rhyme stays the "must have".
- Context/personalization shape the top of the list.
- The list feels fresh.

### 6.4 Context scoring options (on-device vs API)

Offline-first (recommended for LyricsLab)
- Use Apple NaturalLanguage embeddings (`NLEmbedding`) for word/sentence similarity.
  - WWDC19 232 and WWDC20 10657 show retrieval patterns and embedding use.
  - https://developer.apple.com/videos/play/wwdc2019/232/
  - https://developer.apple.com/videos/play/wwdc2020/10657/
- Implementation idea:
  - Extract topic keywords from the last 1-4 lines (excluding stopwords).
  - Embed keywords and candidate word; average cosine similarities.

Online fallback (optional)
- Datamuse can return candidates based on meaning and context (`ml`, `topics`, `lc`, `rc`) and can return syllables/pronunciation metadata (`md=srpf`).
  - https://www.datamuse.com/api/
- RhymeBrain can provide rhymes, pronunciation, syllables, and frequency (but has rate limiting and requires attribution).
  - https://rhymebrain.com/api.html

Recommendation:
- Keep base engine offline using CMUdict.
- Add optional API augmentation behind a user setting (and cache results).

### 6.5 Indexing + caching strategies that scale

The core performance rule: candidate generation must be O(1) or O(log N) for the common case.

Good options:
- Exact rhymes: `rhymeKey -> [word]` (you already have this)
- Multi-syllable tails: `tail2Key -> [word]`, `tail3Key -> [word]` (optional)
- Near rhymes (fast candidate lookup):
  - Pre-bucket by vowel group + consonant class (LyricsLab already does this in `CMUDictionary`)
  - Or build a BK-tree over rhyme tails using your distance metric (more complex, but powerful)
- Phrase candidates (optional):
  - Build a small per-song phrase table from what the user already wrote (2-4 grams)

Stability tricks (UX):
- Cache the last suggestion result keyed by (targetRhymeKey, mode, stanzaHash)
- Add hysteresis: don't reorder the top few items unless scores change beyond a threshold

---

## 7) User dictionary (global + per-song)

### 7.1 Why you need it

Rap is full of OOV tokens:
- names, places
- slang spellings ("sumn", "finna", "gon'")
- creative stylization

If the user's personal vocabulary doesn't rank highly, the app feels generic.

### 7.2 Data model

Two layers (merge at query time):

1) Global user lexicon
- Entries: words + optional pronunciations + metadata
  - preferred casing ("LA" vs "la")
  - tags/topics ("cars", "street", "faith")
  - user-defined syllable count (override)
  - user-defined pronunciation (ARPAbet tail, or full pronunciation)
- Signals:
  - accept count
  - last used time

2) Per-song lexicon
- Automatically collected from the current song:
  - words that appear frequently
  - named entities (caps, hashtags)
- User can pin words/phrases.

Implementation steps (LyricsLab)
- Create a new type, conceptually:
  - `UserLexiconStore` (SwiftData or file-backed)
  - `SongLexicon` attached to the document model
- Merge into a single `Lexicon` interface used by:
  - `RhymeAnalyzer` (pronunciation lookup and normalization)
  - `RhymeSuggester` (candidate generation + personalization)

### 7.3 Pronunciation overrides (critical escape hatch)

You will never have perfect pronunciations for rap spellings.
So you need:
- per-word syllable override
- per-word pronunciation override

UI concept:
- Tap word -> "Sound" sheet
  - syllables: +/-
  - choose from known pronunciations
  - or edit a simple phonetic spelling (advanced)

---

## 8) Hip-hop lyric optimization metrics (what to measure)

These features help users improve writing without forcing a style:

1) Rhyme density
- Count of rhyming syllables per bar/line.
- Highlight high-density pockets.

2) Multi-syllable rhyme strength
- Prefer matches on 2-3 syllables.
- Show "2-syllable end rhyme" badges.

3) Internal rhyme placement
- Show internal rhymes that connect to end rhymes or repeat across adjacent lines.
- Avoid highlighting long-distance single matches.

4) Repetition management
- Detect repeated end words.
- Suggest synonyms that preserve rhyme tail.

5) Flow / stress alignment (optional, but high value)
- With CMU stress patterns, estimate whether stressed syllables land on strong beats.
- Present as a "flow grid" rather than a judgment.

Open-source reference point:
- RiTa explicitly supports searching by syllable/stress/rhyme patterns and includes a letter-to-sound engine.
  - https://github.com/dhowe/rita

---

## 9) Syllable counting + cursor position inside a bar

### 9.1 Why syllables are the best proxy for rap timing (without audio)

Without recorded audio, you can't know exact durations.
But syllable counts give a stable way to reason about density and placement.

### 9.2 Syllable sources: dictionary first, heuristics second

Best (when available):
- CMUdict pronunciation -> syllable count = number of vowel phonemes (digits 0/1/2)

Fallbacks:
- G2P (if you add it)
- heuristics (vowel-group counting + adjustments)

Recommendation:
- In LyricsLab, reuse the existing CMUdict infrastructure for syllable counts.
- Add a heuristic fallback, but label it low confidence.

### 9.3 Caret -> syllable index -> beat grid

Baseline algorithm (stable and UI-friendly):

1) Define bar scope
- Start simple: 1 text line == 1 bar (common in rap writing)
- Later: allow user to switch to 2 lines per bar, or explicit bar markers.

2) Tokenize the current bar with character ranges
- You already have a regex-based tokenizer in `RhymeAnalyzer`.
- For syllables, split hyphenated words into sub-tokens.

3) Compute syllable counts per token
- Dictionary -> count vowel phonemes
- else heuristics

4) Compute caret position
- `syllablesBeforeCaret = sum(tokenSyllables for tokens fully before caret)`
- If caret is mid-token, snap to the token boundary (avoid jitter).

5) Map to beats
- Assume 4/4, 16-step grid.
- `pos = syllablesBeforeCaret / max(1, totalSyllablesInBar)`
- `step = round(pos * 16)`
- Display as `beat = 1 + (step / 4)`.

Upgraded algorithm (optional):
- Use stress patterns to prefer stressed syllables on beats 1 and 3.
- Solve with dynamic programming per bar (Viterbi-style alignment).

### 9.4 Good vs bad syllable UX

Good:
- deterministic (same text -> same syllable counts)
- confidence cues (low-confidence words subtly marked)
- easy overrides

Bad:
- syllable counts jump wildly as you type (no caching / no snapping)
- no way to correct obvious miscounts

---

## 10) Recognizing 4/8 bar sections

### 10.1 What "4/8 bar" means in a text editor

Most lyric editors approximate bars as lines.
So "4 bars" often means "4 lines".

But the best experience is:
- suggest a structure
- let the user correct it
- keep it stable once corrected

### 10.2 Reliable structure signals

1) Blank lines
- Treat blank lines as section boundaries (already used in `RhymeSchemePlanner`).

2) Line syllable consistency
- Within a verse, line syllable counts are often within a tolerance band.

3) Repetition
- Repeated or near-duplicate stanzas often indicate hooks.

### 10.3 Heuristic segmentation approach (editable)

1) Split into stanzas by blank lines
2) For each stanza:
  - estimate bars as number of lines (baseline)
  - optionally adjust bars based on syllables-per-line and a target syllables-per-bar
3) Snap/label:
  - if bar count is near {4, 8, 12, 16} within tolerance +/-1, label it
4) Provide UI affordances:
  - show a bracket in the gutter: "8 bars"
  - tap to change to 4/8/16

---

## 11) Concrete implementation plan for LyricsLab (phased)

### Phase 1: Make suggestions feel personal and relevant (no new ML)

- Add `UserLexiconStore` and `SongLexicon` models.
- Update `RhymeSuggester` in `LyricsLab/RhymeEngine/RhymeService.swift`:
  - merge user candidates into the candidate set
  - add a recency penalty (avoid repeats)
  - add a diversity pass (simple caps per lemma/rhymeKey)

Deliverable:
- Top suggestions include the user's vocabulary and don't repeat aggressively.

### Phase 2: Add syllables and a basic bar ruler

- Build a `SyllableEngine` backed by CMUdict vowels-per-word.
- In the editor UI:
  - show a subtle 16-step bar ruler per line
  - highlight caret's step

Deliverable:
- Users can see "where they are" in the bar as they type.

### Phase 3: Multi-syllable rhyme keys (better rap rhymes)

- Extend `RhymeKey` to compute tail2/tail3.
- Add a UI toggle: `1-syllable` vs `2-syllable` end rhyme target.
- Update scheme detection to use the selected tail.

Deliverable:
- End-rhyme highlights and suggestions match the punchier multi-syllable patterns.

### Phase 4: Context-aware ranking (on-device)

- Add NaturalLanguage embedding scoring (word or sentence embeddings) to adjust ranking.
- Keep rhymeScore as a hard gate.

Deliverable:
- Suggestions feel "about what you're writing", not just rhyming.

### Phase 5: Section detection + 4/8 bar brackets

- Add stanza + bar grouping heuristics.
- Show inferred brackets in the gutter with quick overrides.

Deliverable:
- Users can write in 4/8-bar chunks with visible structure.

---

## 12) Examples of good vs bad implementations

### Example A: spelling-based rhyme detection (bad)

Input:

```
I cough
You doff
We laugh
```

Spelling tails:
- cough ~ doff (looks different)
- laugh ends in -augh (looks similar to cough, but pronunciation differs)

Result:
- spelling-based method will mis-group.

Phonetic tails (good):
- cough: K AO1 F
- doff: D AO1 F
- laugh: L AE1 F
So cough/doff rhyme better than laugh.

### Example B: near-rhyme confetti (bad)

If you highlight any vowel-group similarity everywhere, lines become unreadable.

Fix:
- Only highlight near rhymes when:
  - they appear at least twice
  - they are within a limited line distance
  - the token is not already in an exact group

LyricsLab already follows this pattern in `LyricsLab/RhymeEngine/RhymeAnalyzer.swift`.

### Example C: suggestions that ignore frequency (bad)

If the top list is:
- obscure proper nouns
- archaic words
- weird spellings

Users will stop trusting the tool.

Fix:
- add frequencyScore
- add userScore
- add diversity + recency penalties

### Example D: suggestions that shuffle on every keystroke (bad)

Fix:
- add hysteresis: keep ordering unless score changes materially
- cache and only recompute within the active stanza/window

---

## 13) Open-source + external systems you can learn from

Even if you don't ship these components directly, they're useful as reference implementations:

- CMUdict: the standard English pronunciation resource
  - https://github.com/cmusphinx/cmudict

- pronouncing: simple rhyme logic built on CMUdict
  - https://github.com/aparrish/pronouncingpy

- RiTa: lexicon search by syllables/stress/rhyme patterns; letter-to-sound engine
  - https://github.com/dhowe/rita

- Datamuse API: word-finding engine that supports sound/meaning/context constraints and returns syllable + pronunciation metadata
  - https://www.datamuse.com/api/

- RhymeBrain API: rhymes + pronunciation + syllables + frequency, but includes rate limiting and attribution requirements
  - https://rhymebrain.com/api.html

---

## 14) Licensing + distribution notes (iOS)

If you plan to ship on-device and stay App-Store-friendly:

- CMUdict is widely used and is generally permissive for commercial use (see its repository/license).
  - https://github.com/cmusphinx/cmudict

- Be careful with phonemization/G2P tool licenses.
  - Example: `phonemizer` is GPL-3.0, which is usually a non-starter for proprietary App Store distribution if bundled.
    - https://github.com/bootphon/phonemizer
  - Safer pattern: train a model using permissive data/tools, then ship your own Core ML model.

- API attribution requirements:
  - RhymeBrain requires acknowledgment in-app and rate-limits requests.
    - https://rhymebrain.com/api.html
  - Datamuse asks for acknowledgment and has usage limits.
    - https://www.datamuse.com/api/

---

## 15) Testing + evaluation (how to know it works)

Unit tests (fast feedback):
- rhymeKey extraction (last stressed vowel)
- tail2/tail3 extraction
- near-rhyme similarity thresholds
- scheme inference on small examples
- suggestion ranking stability (same input -> stable top N)

Golden-corpus tests (quality):
- Maintain a small set of rap-like lyric stanzas with expected rhyme groupings.
- Track regression when you tune thresholds.

UX evaluation signals (in-app analytics, privacy-respecting):
- suggestion acceptance rate
- average time to accept a suggestion
- how often users open the "Sound" override sheet (signals OOV / mispronunciations)
