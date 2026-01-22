# testing.md — Test plan

## Unit tests
### RhymeEngine
- CMU parsing:
  - loads dictionary, handles alternate pronunciations
- Rhyme key extraction:
  - identical keys for known rhyming pairs
  - different keys for non-rhyming pairs
- Near rhyme:
  - similarity threshold tests (golden cases)
- Suggestions:
  - ranking favors exact rhyme over near rhyme
  - deterministic ordering for stable UI

### Search
- Query matches:
  - title hits
  - lyrics hits
  - case-insensitivity
- Debounce behavior (where feasible)

### Persistence
- Save/load composition integrity
- updatedAt changes on edit
- iCloud/local switching logic (if implemented)

## UI tests (XCUITest)
- Create composition, type lyrics, verify it persists after relaunch
- Search returns lyrics match
- Theme switch updates UI without breaking editor
- Suggestions chip inserts text (basic)

## Performance checks
- Typing latency in editor with rhyme highlighting on
- CMU parse time (first run) + cache load time (subsequent runs)
- Memory footprint of dictionary index (sanity)
