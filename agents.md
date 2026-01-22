# agents.md — LyricsLab (Codex)

## Purpose
This repo uses multiple “agents” (roles) to parallelize work. Each agent owns a domain, proposes changes via PRs/patches, and writes/updates tests and docs for their area.

## Global rules (all agents)
- MVP-first. If a feature is marked post-MVP, do not implement it unless explicitly approved.
- Performance is a feature: debounce expensive work, avoid unnecessary re-renders, measure before optimizing.
- Offline-first: CMU dict is primary; external APIs/AI are post-MVP and IAP-locked.
- Keep SwiftUI UI “pure”; UIKit wrappers are allowed only where SwiftUI cannot meet requirements (notably rich text editing).
- Every non-trivial change updates relevant docs and adds tests where feasible.

## Agents / Roles

### 1) Product/Spec Agent
**Owner:** Requirements, scope control, acceptance criteria.  
**Responsibilities:**
- Maintain `requirements.md`, `tasks.md`, and milestone definitions.
- Resolve open questions and document decisions (persistence choice, rhyme heuristics).
**Outputs:** Updated specs, prioritized backlog, acceptance criteria.

### 2) iOS App Agent (SwiftUI + Navigation)
**Owner:** App shell, navigation, Home, Settings plumbing.  
**Responsibilities:**
- SwiftUI structure (`NavigationStack`), environment injection, theme manager integration.
- Home list + search (title+lyrics).
- Settings button (spinning gear) + settings UI.
**Outputs:** Views, view models, routing, performance considerations.

### 3) Persistence + iCloud Agent
**Owner:** Data model, persistence stack, CloudKit sync toggle behavior.  
**Responsibilities:**
- Implement SwiftData/Core Data store(s).
- iCloud enabled-by-default; robust switching between local/cloud stores.
- Data migrations/versioning strategy.
**Outputs:** Storage layer, migration notes, tests for persistence.

### 4) Editor Agent (Text Editing + Highlighting Surface)
**Owner:** Lyrics editor UX and text system.  
**Responsibilities:**
- Implement `UITextView` wrapper for attributed editing (cursor insertion, highlight ranges).
- Title field + layout, keyboard accessory integration hooks.
- Efficient update pipeline (debounced analysis -> apply attributes).
**Outputs:** Editor view, text wrapper, insertion API, perf notes.

### 5) Rhyme Engine Agent (CMU Dict + Suggestions)
**Owner:** Rhyme detection, grouping, ranking suggestions.  
**Responsibilities:**
- Parse `cmudict.txt`, cache parsed dictionary, fast lookup.
- End rhyme + near rhyme heuristics, stable grouping, deterministic colors/IDs.
- Suggestion ranking based on current line/rhyme key.
**Outputs:** `RhymeEngine` module, unit tests, benchmark harness (optional).

### 6) Design System Agent (Themes, “Liquid Glass”, Icons)
**Owner:** Theme tokens, components, animations.  
**Responsibilities:**
- Implement default themes: RetroFuturistic, PlainLight, PlainDark, DirtyDishes.
- Highlight palette that remains legible per theme.
- Icon switching UI (IAP-locked for non-default).
**Outputs:** `DesignSystem/`, theme manager, reusable components.

### 7) Audio Agent (MVP local player)
**Owner:** Local file playback, loop A/B, mini-player bar.  
**Responsibilities:**
- Local file picker + playback via AVFoundation.
- Mini-player bar in editor + simple visualizer animation.
- Looping segment reliability while typing.
**Outputs:** Audio module + UI sheet, tests where possible.

### 8) Monetization/IAP Agent (post-MVP scaffolding allowed)
**Owner:** Feature gating, paywall card, StoreKit 2 integration (later).  
**Responsibilities:**
- Provide gating APIs + paywall UI.
- Dev “Bypass IAP” toggle (Debug only).
- StoreKit 2 products + restore flow (post-MVP).
**Outputs:** `IAP/` module, paywall view, gating helpers.

### 9) QA/Test Agent
**Owner:** Test strategy, UI tests, regression coverage.  
**Responsibilities:**
- Create test plan for rhyme engine, persistence, search, editor insertion.
- Add snapshot-like verification where possible (or golden text attribute tests).
**Outputs:** `testing.md`, test suites, CI suggestions.

## Communication protocol
- Any agent can edit docs, but must keep specs consistent.
- If scope creep is detected, agent must open an issue and mark it post-MVP.
- Conflicts resolved by Product/Spec Agent decisions recorded in `requirements.md` “Decisions” section.
