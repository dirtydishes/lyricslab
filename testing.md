# testing.md — Test strategy (lean + fast)

## Goals
- Keep feedback loops fast (seconds, not minutes).
- Cover the rhyme engine core logic with a small set of high-value unit tests.
- Use UI tests sparingly (smoke tests only).
- Run expensive tests only on demand or nightly CI.

---

## Test tiers (when to run)

### Tier 0 — “Always” (local + CI on every PR)
Target runtime: < 30–60 seconds.
- Small unit tests only:
  - Rhyme key extraction correctness (a few golden pairs)
  - Suggestion ranking basic rules (exact > near)
  - Search matching title+lyrics (2–3 cases)
- No UI tests
- No large dictionary parsing benchmarks

### Tier 1 — “PR Gate” (CI only, optional locally)
Target runtime: < 2–4 minutes.
- Adds:
  - CMU dict parse sanity test (tiny sample dict, not full `cmudict.txt`)
  - Persistence save/load smoke test (local store only)
- Still avoids XCUITest unless absolutely needed

### Tier 2 — “Nightly / Manual”
Target runtime: can be longer.
- Full integration checks:
  - iCloud/CloudKit behaviors (if implemented)
  - UI smoke flows (1–2 tests max)
  - Performance measurements (typing latency, dict parse time) as Instruments runs,
    not unit tests

---

## What we test (minimal set)

## 1) RhymeEngine (Tier 0)
### 1.1 Rhyme key extraction (golden cases)
Use a hardcoded mini phoneme map; do NOT require CMU parsing.

Cases (examples; keep to ~6–10 total assertions):
- Exact rhyme should match:
  - “time” vs “rhyme”
  - “cat” vs “hat”
- Non-rhyme should differ:
  - “time” vs “team”
- Handles punctuation normalization:
  - “time,” -> “time”
- Handles case:
  - “Time” -> “time”

### 1.2 Suggestion ordering
Given a target rhyme key:
- Exact rhymes appear before near rhymes
- Ordering is deterministic (stable sort)

## 2) Search (Tier 0)
- Query matches title
- Query matches lyrics
- Case-insensitive match
(3 tests max)

## 3) Persistence (Tier 1)
- Save + load one `Composition` (title + lyrics)
- Update `updatedAt` changes when editing
(Keep it to 1–2 tests)

---

## What we do NOT test frequently
- Full `cmudict.txt` parsing in unit tests (too slow, too flaky in CI).
- UI tests for every PR (they’re slow and brittle).
- CloudKit in CI by default (painful + environment-dependent).

---

## Performance verification (manual / nightly)
Instead of constant performance tests:
- Run Instruments Time Profiler manually when:
  - editor feels laggy
  - rhyme highlighting changes
  - dictionary parsing/indexing changes
- Keep a simple checklist in `perf-checklist.md` (optional):
  - Typing latency with rhyme highlighting ON
  - Time to first suggestions (cold start vs warm cache)
  - Memory footprint of dictionary index

---

## UI tests (Tier 2 only; keep to 1–2)
If we keep any XCUITests at all, make them smoke-only:
1) Create composition → type line → close → reopen → text persists
2) Search finds lyrics match

If they get flaky, disable by default and run manually.

---

## CI recommendations
- PR pipeline:
  - Tier 0 always
  - Tier 1 on PR merge or “Run Extended Tests” label
- Nightly:
  - Tier 2

---

## Practical tips to keep tests fast
- Use a tiny test dictionary fixture (10–50 entries) for parser tests.
- Prefer pure functions for rhyme key and similarity so they’re easy to test.
- Avoid spinning up the whole SwiftUI app in tests unless absolutely necessary.
