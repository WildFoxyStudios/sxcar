# Tribes-as-filter Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development.

**Goal:** Add tribes filtering to the grid/nearby endpoint and the Flutter grid screen — users can filter the grid by one or more tribes.

**Architecture:** Backend adds `?tribes=bear,daddy,geek` query param to `/grid/nearby`. Flutter adds a tribe chip selector bar above the grid. 100% Grindr parity for this feature.

**Source:** `docs/superpowers/audits/2026-07-06-full-audit.md` — Tribes-as-filter listed as deferred Grindr parity feature.

## Global Constraints
- No git push. No secrets.
- TDD required.
- Reuse existing tribe lists from `GET /meta/filters` (already created in previous plan).
- Uses existing grid infrastructure (PostGIS, server-side filtering pattern).

### Task 1: Backend — add tribes filter to /grid/nearby

**Files:**
- Modify: `backend/crates/db/src/geo.rs` (the nearby query)
- Modify: `backend/crates/api/src/grid.rs` (parse query param, pass to geo query)

- [ ] Add `tribes: Option<Vec<String>>` param to the nearby handler
- [ ] In the query, add: `AND ($N::text[] IS NULL OR pt.tribe = ANY($N::text[]))` using a JOIN to `profile_tribes`
- [ ] Test: register 2 users (one with tribe "Bear", one with "Geek"), query with `?tribes=Bear` → only Bear user visible
- [ ] Commit: `feat(backend): add tribes filter to /grid/nearby`

### Task 2: Flutter — add tribe filter chips to grid screen

**Files:**
- Modify: `apps/app/lib/src/features/grid_search_screen.dart`

- [ ] Add a horizontal `FilterChip` bar above the grid, populated from `GET /meta/filters` tribes
- [ ] Selected tribes are passed as `?tribes=a,b,c` query param to the grid API
- [ ] Chips toggle on/off, grid refreshes on selection change
- [ ] Test: verify chips render, tap toggles selection
- [ ] Commit: `feat(app): add tribe filter chips to grid search screen`

### Task 3: Deploy + smoke

- [ ] Build, ship, deploy backend
- [ ] Smoke: register 2 users with different tribes, verify filter works
